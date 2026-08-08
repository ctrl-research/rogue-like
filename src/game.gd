extends Node2D
## Run orchestrator. The server owns all game state (waves, oxygen, XP,
## objectives) and mirrors what the HUD needs to clients via RPC. Clients only
## render synced state and forward their own input to their diver.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const DEPTH_CHARGE_SCENE := preload("res://scenes/depth_charge.tscn")
const GEM_SCENE := preload("res://scenes/xp_gem.tscn")
const RING_SCENE := preload("res://scenes/sonar_ring.tscn")
const SLASH_SCENE := preload("res://scenes/slash.tscn")
const CRATE_SCENE := preload("res://scenes/salvage_crate.tscn")
const BELL_SCENE := preload("res://scenes/dive_bell.tscn")
const NUGGET_SCENE := preload("res://scenes/salvage_nugget.tscn")
const RELAY_SCENE := preload("res://scenes/relay.tscn")
const PAYLOAD_SCENE := preload("res://scenes/payload.tscn")

const HUD_SYNC_INTERVAL := 0.25
const WALL_LAYER := 4

# Ambient light lives in Settings, because the player's brightness calibration
# has to be folded into it and the menu needs the same shade to calibrate
# against. Unlit terrain sits at that ambient: barely a silhouette, so what you
# have not lit you cannot really see. What makes this work for co-op without any
# extra code is that 2D lighting composites per pixel — every diver's lamp is
# present on every peer, so the crew's vision is additive, and any light source
# added later joins in for free (issue #20).

## Shadow spread and drop per loot kind — pickups are small and sit low, the
## bell is a machine. Drop has to clear the sprite's own feet or the shadow's
## dense middle hides behind it (see Fx.attach_shadow).
const LOOT_SHADOW := {
	"gem": Vector2(0.6, 4.0),
	"nugget": Vector2(0.6, 4.0),
	"crate": Vector2(1.0, 6.0),
	"bell": Vector2(1.2, 6.0),
	"relay": Vector2(1.0, 6.0),
	"payload": Vector2(0.7, 5.0),
}

## Marker lights for the things a quest sends the crew to find. Without these
## the dark ambient turns every objective into a search of an unlit room. Gems
## and nuggets deliberately have none: you collect those by walking over them,
## which means your own lamp is already on them, and there can be dozens.
const LOOT_BEACON := {
	"crate": Color(1.0, 0.85, 0.45),
	"bell": Color(0.55, 1.0, 0.75),
	"relay": Color(0.5, 0.9, 1.0),
	"payload": Color(1.0, 0.82, 0.5),
}

# State the HUD reads. Kept current on clients via _rpc_hud / _rpc_game_over.
var oxygen := GameRules.OXYGEN_TIME
var crates_left := GameRules.CRATE_COUNT
var quest_kind := "crates"  # this depth's mini quest (see GameRules.QUEST_KINDS)
var quest_progress := 0.0  # swarm: seconds left (crates use crates_left)
var quest_done := false  # objective complete, bell is down
var team_level := 1
var team_xp := 0
var xp_needed := GameRules.xp_needed(1)
var elapsed := 0.0
var extraction_progress := 0.0
var depth := 1
var salvage_earned := 0
var awaiting_choice := false  # bell reached; host is picking extract/descend
var decision_left := 0.0
var game_over := false
var victory := false
var banked_salvage := 0  # set on game over (win)

# Server-only state.
var _started := false
var _ready_peers := {}
var _metas := {}  # pid -> station meta dict (from the ready handshake)
var _max_oxygen := GameRules.OXYGEN_TIME
var _spawn_accum := 0.0
var _hud_accum := 0.0
var _bell: Area2D
var _maw_spawned := false  # one Trench Maw per site (crate quests only)
var _quest_bag: Array = []  # shuffled draw pile for per-depth quest rolls
var _site_started := 0.0  # `elapsed` when this site began (swarm timer)
var _ping_cd := 0.0  # hunt quest: sonar ping cadence
var _carrier: Player  # escort quest: whoever is towing the payload
var _rng := RandomNumberGenerator.new()

@onready var players: Node2D = $Players
@onready var enemies: Node2D = $Enemies
@onready var loot: Node2D = $Loot
@onready var projectiles: Node2D = $Projectiles
@onready var terrain: Terrain = $Terrain

var terrain_initial_cells := 0  # determinism fingerprints (see e2e)
var terrain_initial_ore := 0

var _murk_depth := 1  # last depth the ambient was set for, to re-apply on retune


func _ready() -> void:
	$PlayerSpawner.spawn_function = _spawn_player
	$EnemySpawner.spawn_function = _spawn_enemy
	$LootSpawner.spawn_function = _spawn_loot
	$ProjectileSpawner.spawn_function = _spawn_projectile
	_build_walls()
	# Re-tuning brightness mid-dive takes effect immediately rather than at the
	# next site, which matters because a dive is where you notice it's wrong.
	Settings.changed.connect(func() -> void: _apply_depth_murk(_murk_depth))
	if multiplayer.is_server():
		terrain.ore_mined.connect(_on_ore_mined)
		multiplayer.peer_disconnected.connect(_on_peer_left)
		# A dedicated server contributes no diver and has no Station, so it must not
		# mark itself ready — doing so would spawn a phantom player and pool a
		# non-existent diver's upgrades into the shared oxygen tank.
		if not Net.is_dedicated():
			_mark_ready(1, Station.meta_dict())
	else:
		_rpc_notify_ready.rpc_id(1, Station.meta_dict())


func _process(delta: float) -> void:
	if not multiplayer.is_server() or not _started or game_over:
		return

	elapsed += delta
	oxygen = maxf(0.0, oxygen - delta)
	if oxygen <= 0.0:
		for p in _active_players():
			p.take_damage(GameRules.SUFFOCATION_DPS * delta)

	if awaiting_choice:
		decision_left -= delta
		if decision_left <= 0.0:
			choose_extract()
	else:
		_tick_quest(delta)
		_spawn_waves(delta)
		_check_extraction(delta)

	_hud_accum += delta
	if _hud_accum >= HUD_SYNC_INTERVAL:
		_hud_accum = 0.0
		_rpc_hud.rpc(oxygen, crates_left, team_level, team_xp, xp_needed, elapsed,
				extraction_progress, depth, salvage_earned, awaiting_choice, decision_left,
				quest_kind, quest_progress, quest_done)


# --- Server API called by gameplay nodes ---------------------------------


func fire_bolt(from: Vector2, dir: Vector2, damage: float, pierce: int, tint: Color, sprite_scale: Vector2, speed: float, bounces := 0) -> void:
	$ProjectileSpawner.spawn({
		"type": "bolt",
		"pos": from,
		"dir": dir,
		"damage": damage,
		"pierce": pierce,
		"tint": tint,
		"scale": sprite_scale,
		"speed": speed,
		"bounces": bounces,
	})


func drop_charge(at: Vector2, damage: float, radius: float, stun := 0.0) -> void:
	$ProjectileSpawner.spawn({
		"type": "charge", "pos": at, "damage": damage, "radius": radius, "stun": stun,
	})


## Cosmetic sonar ring, replicated so every peer sees the pulse.
func spawn_ring(at: Vector2, radius: float) -> void:
	$ProjectileSpawner.spawn({"type": "ring", "pos": at, "radius": radius})


## Cosmetic melee impact, replicated so every peer sees the slash.
func spawn_slash(at: Vector2, angle: float, tint: Color, visual_scale: float) -> void:
	$ProjectileSpawner.spawn({
		"type": "slash", "pos": at, "angle": angle, "tint": tint, "vscale": visual_scale,
	})


func add_oxygen(seconds: float) -> void:
	oxygen += seconds
	announce("Rebreather kicked in — +%ds O2" % int(seconds))


func announce(text: String) -> void:
	_rpc_toast.rpc(text)


func on_enemy_killed(enemy: Enemy) -> void:
	# Deferred: kills happen inside physics callbacks, and spawning nodes
	# there would register collision shapes while the physics server is
	# flushing queries.
	_spawn_loot_deferred.call_deferred("gem", enemy.global_position)
	match enemy.kind:
		"jelly":
			# The bloom splits.
			for offset in [Vector2(-14, 0), Vector2(14, 0)]:
				_spawn_enemy_deferred.call_deferred("jelly_small", enemy.global_position + offset)
		"beast":
			on_beast_killed(enemy.global_position)
		"warden":
			on_warden_killed(enemy.global_position)
		"maw":
			salvage_earned += 10 * depth
			for i in 4:
				_spawn_loot_deferred.call_deferred(
					"gem", enemy.global_position + Vector2.from_angle(TAU * i / 4.0) * 18.0)
			_rpc_toast.rpc("The Trench Maw is slain! Prime salvage recovered (+%d)." % (10 * depth))
	enemy.queue_free()


func _spawn_enemy_deferred(kind: String, pos: Vector2) -> void:
	if game_over or enemies.get_child_count() >= GameRules.ENEMY_CAP:
		return
	var hp_scale := (1.0 + 0.35 * (Net.player_count() - 1)) * GameRules.depth_hp_scale(depth)
	$EnemySpawner.spawn({"kind": kind, "pos": pos, "hp_scale": hp_scale})


func add_xp(amount: int) -> void:
	team_xp += amount
	while team_xp >= xp_needed:
		team_xp -= xp_needed
		team_level += 1
		xp_needed = GameRules.xp_needed(team_level)
		_offer_upgrades()


func on_crate_collected() -> void:
	crates_left -= 1
	salvage_earned += GameRules.crate_value(depth)
	if crates_left == 2 and not _maw_spawned:
		_maw_spawned = true
		_spawn_maw.call_deferred()
	if crates_left > 0:
		_rpc_toast.rpc("Salvage secured (+%d) — %d left" % [GameRules.crate_value(depth), crates_left])
	else:
		_complete_quest("All salvage secured!")


# --- Mini quests -----------------------------------------------------------


## Server: per-site quest ticking — the swarm timer and the hunt's sonar
## pings. Crates complete via on_crate_collected instead.
func _tick_quest(delta: float) -> void:
	if quest_done:
		return
	match quest_kind:
		"swarm":
			quest_progress = maxf(0.0, GameRules.SWARM_TIME - (elapsed - _site_started))
			if quest_progress <= 0.0:
				salvage_earned += GameRules.quest_reward(depth)
				_complete_quest("The swarm relents — hazard pay earned (+%d)!" % GameRules.quest_reward(depth))
		"hunt":
			_ping_cd -= delta
			var beast := _find_beast()
			if beast != null and _ping_cd <= 0.0:
				_ping_cd = 5.0
				spawn_ring(beast.global_position, 90.0)
		"repair":
			_tick_repair(delta)
		"escort":
			_tick_escort(delta)


## Progress accrues while any active diver holds inside the relay's radius —
## a second diver on the spot speeds it up, the rest hold off the waves.
func _tick_repair(delta: float) -> void:
	var relay := _find_in_loot("relay")
	if relay == null:
		return
	var nearby := 0
	for p in _active_players():
		if p.global_position.distance_to(relay.global_position) <= GameRules.REPAIR_RADIUS:
			nearby += 1
	if nearby == 0:
		return
	quest_progress += delta * (1.0 + 0.5 * (nearby - 1))
	if quest_progress >= GameRules.REPAIR_TIME:
		salvage_earned += GameRules.quest_reward(depth)
		_complete_quest("The relay hums back to life — contract paid (+%d)!" % GameRules.quest_reward(depth))


## The payload trails whoever grabbed it; the carrier swims heavy and the
## fauna smell easy prey (see player.towing / enemy targeting bias).
func _tick_escort(delta: float) -> void:
	var payload := _find_in_loot("payload")
	if payload == null:
		return
	if _carrier != null:
		if not is_instance_valid(_carrier) or _carrier.is_queued_for_deletion():
			_carrier = null  # left the crew mid-tow
		elif _carrier.dead or _carrier.downed:
			_carrier.towing = false
			_carrier = null
			_rpc_toast.rpc("The payload drifts free — someone grab it!")
	if _carrier == null:
		for p in _active_players():
			if p.global_position.distance_to(payload.global_position) <= GameRules.TOW_GRAB_RADIUS:
				_carrier = p
				p.towing = true
				_rpc_toast.rpc("%s has the payload — cover them!" % p.display_name())
				break
	if _carrier != null:
		var to_carrier := _carrier.global_position - payload.global_position
		if to_carrier.length() > 14.0:
			payload.global_position += to_carrier.normalized() \
					* minf(to_carrier.length() - 14.0, 150.0 * delta)
	if payload.global_position.distance_to(GameRules.ARENA_SIZE / 2.0) <= GameRules.DELIVER_RADIUS:
		if _carrier != null and is_instance_valid(_carrier):
			_carrier.towing = false
		_carrier = null
		payload.queue_free()
		salvage_earned += GameRules.quest_reward(depth)
		_complete_quest("Payload secured at the bell zone (+%d)!" % GameRules.quest_reward(depth))


func _find_in_loot(group: String) -> Node2D:
	for n in loot.get_children():
		if n.is_in_group(group) and not n.is_queued_for_deletion():
			return n
	return null


func on_beast_killed(pos: Vector2) -> void:
	salvage_earned += GameRules.quest_reward(depth)
	for i in 4:
		_spawn_loot_deferred.call_deferred(
				"gem", pos + Vector2.from_angle(TAU * i / 4.0) * 18.0)
	_complete_quest("The beast is slain — its hoard is yours (+%d)!" % GameRules.quest_reward(depth))


func on_warden_killed(pos: Vector2) -> void:
	salvage_earned += GameRules.boss_reward(depth)
	for i in 8:
		_spawn_loot_deferred.call_deferred(
				"gem", pos + Vector2.from_angle(TAU * i / 8.0) * 24.0)
	_rpc_record_lair.rpc(depth)
	_complete_quest("The Warden falls — the trench yields its prize (+%d)!" % GameRules.boss_reward(depth))


## Every diver's station remembers the cleared lair — it unlocks buying the
## next winch-refit checkpoint between dives.
@rpc("authority", "call_local", "reliable")
func _rpc_record_lair(lair_depth: int) -> void:
	if Net.is_dedicated():
		return  # no progression of its own to record
	Station.record_lair_cleared(lair_depth)


## Server: the site objective is met — drop the bell and say so in one toast
## (toasts overwrite each other, so the flourish and the bell share a line).
func _complete_quest(flourish: String) -> void:
	if quest_done:
		return
	quest_done = true
	_spawn_loot_deferred.call_deferred("bell", GameRules.ARENA_SIZE / 2.0)
	_rpc_toast.rpc("%s The dive bell has dropped — get to it!" % flourish)


## Depth 1 always teaches the classic crate quest; every 5th depth is a boss
## lair; other depths draw from a shuffled bag so a run sees every quest
## before any repeat.
func _roll_quest() -> String:
	if GameRules.is_boss_depth(depth):
		return "boss"
	if depth == 1:
		return "crates"
	if _quest_bag.is_empty():
		_quest_bag = GameRules.QUEST_KINDS.duplicate()
	var i := _rng.randi() % _quest_bag.size()
	var kind: String = _quest_bag[i]
	_quest_bag.remove_at(i)
	return kind


func _find_beast() -> Enemy:
	for e in enemies.get_children():
		if e is Enemy and e.kind == "beast" and not e.is_queued_for_deletion():
			return e
	return null


## Digging into an ore seam shakes a nugget loose. Deferred: destruction is
## triggered from physics callbacks (mining, charges, fauna chewing).
func _on_ore_mined(pos: Vector2) -> void:
	_spawn_loot_deferred.call_deferred("nugget", pos)


func add_salvage(amount: int) -> void:
	salvage_earned += amount


func _spawn_loot_deferred(kind: String, pos: Vector2) -> void:
	if game_over:
		return
	var node: Node = $LootSpawner.spawn({"kind": kind, "pos": pos})
	if kind == "bell":
		_bell = node as Area2D


## Every peer stops streaming its own diver, ahead of despawn_all(). The host
## frees its copies first and clients only follow once the despawn replicates,
## so without this pause a client spends that gap syncing position to nodes
## the host no longer has ("failed to get cached node" on the host's side).
func quiesce_sync() -> void:
	if multiplayer.is_server():
		_rpc_quiesce.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_quiesce() -> void:
	for p in players.get_children():
		if p is Player:
			p.stop_syncing()


## Server: free every spawner-tracked node so despawns replicate while all
## peers still have the game scene. Called before leaving the scene — a raw
## scene change would race the despawn broadcasts against clients' own
## teardown and spray ERR_UNAUTHORIZED on their side.
func despawn_all() -> void:
	for holder: Node2D in [players, enemies, loot, projectiles]:
		for child in holder.get_children():
			child.queue_free()


func on_player_downed(p: Player) -> void:
	if _active_players().is_empty():
		_finish(false)
	else:
		_rpc_toast.rpc("%s is down — get to them!" % p.display_name())


func on_player_died() -> void:
	if _active_players().is_empty():
		_finish(false)
	else:
		_rpc_toast.rpc("A diver was lost to the deep.")


# --- Spawn functions (run on every peer when the spawner replicates) ------


func _spawn_player(data: Variant) -> Node:
	var node: Player = PLAYER_SCENE.instantiate()
	node.name = "Player%d" % data.pid
	node.peer_id = data.pid
	node.player_index = data.index
	node.position = data.pos
	node.meta = data.get("meta", {})
	node.game = self
	Fx.attach_shadow(node)
	return node


func _spawn_enemy(data: Variant) -> Node:
	var node: Enemy = ENEMY_SCENE.instantiate()
	node.position = data.pos
	node.game = self
	node.setup(data.kind, data.hp_scale)
	# setup() has already applied the kind's scale, and the shadow rides it.
	Fx.attach_shadow(node, 1.0, 7.0)
	if data.kind == "warden":
		# The lair guardian carries its own lure-light. A boss you cannot see is
		# just a hazard; the beast stays unlit on purpose, because tracking it by
		# sonar IS the hunt.
		Fx.attach_beacon(node, Color(1.0, 0.72, 0.42), 0.5, 0.85)
	return node


func _spawn_loot(data: Variant) -> Node:
	# Node2D, not Area2D: the relay and payload are plain nodes — only the
	# pickups and the bell need overlap detection.
	var node: Node2D
	match data.kind:
		"gem":
			node = GEM_SCENE.instantiate()
		"nugget":
			node = NUGGET_SCENE.instantiate()
		"relay":
			node = RELAY_SCENE.instantiate()
		"payload":
			node = PAYLOAD_SCENE.instantiate()
		"crate":
			node = CRATE_SCENE.instantiate()
		"bell":
			node = BELL_SCENE.instantiate()
			Sfx.play("bell", -5.0, 0.0)  # spawn replicates: rings on every peer
	node.position = data.pos
	node.set("game", self)
	var shadow: Vector2 = LOOT_SHADOW.get(data.kind, Vector2(0.8, 5.0))
	Fx.attach_shadow(node, shadow.x, shadow.y)
	if LOOT_BEACON.has(data.kind):
		# The bell is the way out, so it burns brighter and further than the
		# rest — it should be findable from across a dark site.
		# Explicit bool: data is a Variant, so `:=` cannot infer a comparison on it.
		var bright: bool = data.kind == "bell"
		Fx.attach_beacon(node, LOOT_BEACON[data.kind],
				0.62 if bright else 0.42, 1.1 if bright else 0.6)
	return node


func _spawn_projectile(data: Variant) -> Node:
	if data.type == "charge":
		var charge: Node2D = DEPTH_CHARGE_SCENE.instantiate()
		charge.position = data.pos
		charge.damage = data.damage
		charge.radius = data.radius
		charge.stun = data.get("stun", 0.0)
		return charge
	if data.type == "ring":
		var ring: Node2D = RING_SCENE.instantiate()
		ring.position = data.pos
		ring.radius = data.radius
		return ring
	if data.type == "slash":
		var slash: Node2D = SLASH_SCENE.instantiate()
		slash.position = data.pos
		slash.rotation = data.angle
		slash.tint = data.tint
		slash.visual_scale = data.vscale
		return slash
	var node: Area2D = PROJECTILE_SCENE.instantiate()
	node.position = data.pos
	node.dir = data.dir
	node.damage = data.damage
	node.pierce = data.pierce
	node.tint = data.tint
	node.sprite_scale = data["scale"]
	node.speed = data.speed
	node.bounces = data.get("bounces", 0)
	return node


# --- Run lifecycle ---------------------------------------------------------


@rpc("any_peer", "reliable")
func _rpc_notify_ready(meta: Dictionary) -> void:
	if multiplayer.is_server():
		# Clamped at the trust boundary: this is any_peer, so on a public server the
		# dict is attacker-controlled and it drives hp, speed, damage and the crew's
		# shared oxygen. See Station.sanitize_meta.
		_mark_ready(multiplayer.get_remote_sender_id(), Station.sanitize_meta(meta))


func _mark_ready(pid: int, meta: Dictionary) -> void:
	_ready_peers[pid] = true
	_metas[pid] = meta
	if _started:
		return
	# Who the dive is waiting on, and who gets a diver spawned — the same list.
	#
	# A dedicated server is neither. It never marks itself ready (see _ready), so
	# including peer 1 unconditionally meant waiting forever for a report that would
	# never arrive: the crew reached the arena and nobody ever spawned. Had the gate
	# passed, _start_run would then have spawned a body for the server and pooled a
	# non-existent diver's O2 upgrades into the shared tank.
	var expected: Array[int] = []
	if not Net.is_dedicated():
		expected.append(1)
	for p in multiplayer.get_peers():
		expected.append(p)
	if expected.is_empty():
		return  # a dedicated server with no divers aboard: nothing to start
	for p in expected:
		if not _ready_peers.has(p):
			return
	_started = true
	_start_run(expected)


func _start_run(pids: Array[int]) -> void:
	_rng.randomize()
	# Everyone's O2 Reserve upgrades pool into the shared tank.
	var o2_bonus := 0.0
	for pid in pids:
		o2_bonus += Station.O2_PER_LEVEL * int(_metas.get(pid, {}).get("o2", 0))
	_max_oxygen = GameRules.OXYGEN_TIME + o2_bonus
	oxygen = _max_oxygen

	# The depth the diver who started the dive asked for. Was the host's own
	# Station.dive_depth, which a dedicated server does not have.
	depth = maxi(1, Net.requested_depth)
	if depth > 1:
		_rpc_toast.rpc("The winch lowers the crew straight to depth %d." % depth)

	_build_site()
	var offsets := _spawn_offsets()
	for i in pids.size():
		$PlayerSpawner.spawn({
			"pid": pids[i],
			"index": i,
			"pos": GameRules.ARENA_SIZE / 2.0 + offsets[i % offsets.size()],
			"meta": _metas.get(pids[i], {}),
		})


## Server: roll the quest and the site layout, broadcast so every peer builds
## identical terrain, then stage the quest in the carved clearings.
func _build_site() -> void:
	quest_kind = _roll_quest()
	quest_done = false
	quest_progress = GameRules.SWARM_TIME if quest_kind == "swarm" else 0.0
	crates_left = GameRules.CRATE_COUNT if quest_kind == "crates" else 0
	_site_started = elapsed
	_ping_cd = 0.0
	if _carrier != null and is_instance_valid(_carrier):
		_carrier.towing = false
	_carrier = null

	var spots := PackedVector2Array()
	var center := GameRules.ARENA_SIZE / 2.0
	for i in GameRules.CRATE_COUNT:
		var pos := center
		while pos.distance_to(center) < 220.0:
			pos = Vector2(
				_rng.randf_range(100.0, GameRules.ARENA_SIZE.x - 100.0),
				_rng.randf_range(100.0, GameRules.ARENA_SIZE.y - 100.0),
			)
		spots.append(pos)
	_rpc_build_site.rpc(_rng.randi(), depth, spots)

	match quest_kind:
		"crates":
			for spot in spots:
				$LootSpawner.spawn({"kind": "crate", "pos": spot})
			_rpc_toast.rpc("Quest: recover %d salvage crates. Watch your O2." % GameRules.CRATE_COUNT)
		"swarm":
			_rpc_toast.rpc("Quest: the water boils — survive the swarm for %ds!" % int(GameRules.SWARM_TIME))
		"hunt":
			_spawn_beast(spots[_rng.randi() % spots.size()])
			_rpc_toast.rpc("Quest: hunt the beast — follow the sonar pings.")
		"repair":
			var relay_spot: Vector2 = spots[_rng.randi() % spots.size()]
			$LootSpawner.spawn({"kind": "relay", "pos": terrain.find_open_near(relay_spot)})
			_rpc_toast.rpc("Quest: find the wrecked relay and hold position while it repairs.")
		"escort":
			var pod_spot: Vector2 = spots[_rng.randi() % spots.size()]
			$LootSpawner.spawn({"kind": "payload", "pos": terrain.find_open_near(pod_spot)})
			_rpc_toast.rpc("Quest: tow the payload to the bell zone — its carrier swims heavy.")
		"boss":
			_spawn_warden()
			_rpc_toast.rpc("BOSS LAIR — the Trench Warden guards the descent. Slay it.")


@rpc("authority", "call_local", "reliable")
func _rpc_build_site(map_seed: int, site_depth: int, crate_spots: PackedVector2Array) -> void:
	terrain.build(map_seed, site_depth, crate_spots)
	terrain_initial_cells = terrain.get_used_cells().size()
	terrain_initial_ore = terrain.initial_ore_cells
	# Runs on every peer, so the crew's ambient light dims in step.
	_apply_depth_murk(site_depth)


## The deep gets murkier: ambient light drops and pulls toward the trench's
## blue-green, and the vignette closes in. Depth was already the difficulty
## axis; this makes it the visibility axis too.
func _apply_depth_murk(site_depth: int) -> void:
	_murk_depth = site_depth
	$Darkness.color = Settings.ambient_for_depth(site_depth)
	$Water.set_depth(site_depth)


func _spawn_offsets() -> Array[Vector2]:
	return [Vector2(-16, -16), Vector2(16, -16), Vector2(-16, 16), Vector2(16, 16)]


func _spawn_waves(delta: float) -> void:
	_spawn_accum += delta
	var interval := clampf(1.8 - elapsed * 0.008, 0.4, 1.8) * GameRules.depth_interval_scale(depth)
	if not quest_done:
		if quest_kind == "swarm":
			interval *= GameRules.SWARM_SPAWN_SCALE
		elif quest_kind == "repair":
			interval *= GameRules.REPAIR_SPAWN_SCALE
	var wave_cap := _wave_cap()
	if _spawn_accum < interval or enemies.get_child_count() >= wave_cap:
		return
	_spawn_accum = 0.0

	var alive := _active_players()
	if alive.is_empty():
		return
	var count := 1 + int(elapsed / 45.0) + (Net.player_count() - 1)
	var hp_scale := (1.0 + 0.35 * (Net.player_count() - 1)) * GameRules.depth_hp_scale(depth)
	var brute_chance := minf(0.35, elapsed / 600.0) + GameRules.depth_brute_bonus(depth)
	for i in count:
		if enemies.get_child_count() >= wave_cap:
			break
		var anchor: Player = alive[_rng.randi() % alive.size()]
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(260.0, 400.0)
		var pos := anchor.global_position + Vector2.from_angle(angle) * dist
		pos = pos.clamp(Vector2(24, 24), GameRules.ARENA_SIZE - Vector2(24, 24))
		pos = terrain.find_open_near(pos)
		$EnemySpawner.spawn({"kind": _roll_kind(brute_chance), "pos": pos, "hp_scale": hp_scale})


## Ceiling for ordinary wave spawns. A lair keeps slots in reserve: the
## guardian's summons come through _spawn_enemy_deferred against the hard cap,
## so without this the trash crowds the boss's own mechanic out of existence.
func _wave_cap() -> int:
	if quest_kind == "boss" and not quest_done:
		return GameRules.ENEMY_CAP - GameRules.BOSS_WAVE_HEADROOM
	return GameRules.ENEMY_CAP


## Weighted spawn table; the deep gets stranger with time and depth.
func _roll_kind(brute_chance: float) -> String:
	var weights := {"barbfish": 1.0, "brute": brute_chance}
	if elapsed > 60.0 or depth > 1:
		weights["lurker"] = 0.12 + 0.03 * depth
	if elapsed > 90.0 or depth > 1:
		weights["jelly"] = 0.10 + 0.02 * depth
	var total := 0.0
	for kind in weights:
		total += weights[kind]
	var roll := _rng.randf() * total
	for kind in weights:
		roll -= weights[kind]
		if roll <= 0.0:
			return kind
	return "barbfish"


## The hunt's quarry: a leashed elite lairing in one of the carved clearings.
## Spawned directly (not via _spawn_enemy_deferred) so the enemy cap can never
## leave the quest unwinnable.
func _spawn_beast(lair: Vector2) -> void:
	if game_over:
		return
	var hp_scale := (1.0 + 0.35 * (Net.player_count() - 1)) * GameRules.depth_hp_scale(depth)
	$EnemySpawner.spawn({"kind": "beast", "pos": terrain.find_open_near(lair), "hp_scale": hp_scale})


## The lair's guardian stalks the middle ground between the crew and the
## bell zone. Direct spawn for the same cap-safety reason as the beast.
func _spawn_warden() -> void:
	if game_over:
		return
	var center := GameRules.ARENA_SIZE / 2.0
	var post := center + Vector2.from_angle(_rng.randf() * TAU) * 260.0
	var hp_scale := (1.0 + 0.35 * (Net.player_count() - 1)) * GameRules.depth_hp_scale(depth)
	$EnemySpawner.spawn({"kind": "warden", "pos": terrain.find_open_near(post), "hp_scale": hp_scale})


## The Maw guards the last of the salvage: spawns near a remaining crate.
func _spawn_maw() -> void:
	if game_over:
		return
	var crates := get_tree().get_nodes_in_group("crates")
	var pos := GameRules.ARENA_SIZE / 2.0
	if not crates.is_empty():
		pos = (crates[_rng.randi() % crates.size()] as Node2D).global_position + Vector2(30, 0)
	var hp_scale := (1.0 + 0.35 * (Net.player_count() - 1)) * GameRules.depth_hp_scale(depth)
	$EnemySpawner.spawn({"kind": "maw", "pos": pos, "hp_scale": hp_scale})
	_rpc_toast.rpc("Something enormous stirs near the salvage...")


func _check_extraction(delta: float) -> void:
	if _bell == null or not is_instance_valid(_bell):
		return
	var alive := _active_players()
	if alive.is_empty():
		return
	var inside := _bell.get_overlapping_bodies()
	var all_in := true
	for p in alive:
		if not inside.has(p):
			all_in = false
			break
	if all_in:
		extraction_progress += delta
		if extraction_progress >= GameRules.EXTRACTION_TIME:
			awaiting_choice = true
			decision_left = GameRules.DECISION_TIME
			_rpc_toast.rpc("Dive bell secured — the lead diver is deciding...")
	else:
		extraction_progress = 0.0


## The lead diver: the earliest-joined crew member still aboard.
##
## Peer ids are handed out in join order, so the lowest id among the spawned divers is
## whoever joined first — and when they disconnect their player node goes with them, so
## this silently becomes whoever joined next. No extra state to replicate and no
## election to get wrong, and every peer computes the same answer locally.
##
## A dedicated server is id 1 but spawns no diver, so it is excluded by construction.
## On a listen server the host IS a diver with id 1 and so leads, which is what it did
## before any of this.
func leader_peer_id() -> int:
	var lead := 0
	for p in players.get_children():
		if p is Player and not p.is_queued_for_deletion():
			if lead == 0 or p.peer_id < lead:
				lead = p.peer_id
	return lead


## The lead diver's call at the bell.
##
## Was gated on multiplayer.is_server(), which with a dedicated server meant NOBODY
## could decide: no player is the server, so the choice never appeared for anyone, the
## timer ran out and the server auto-extracted the crew mid-run. Exactly the same
## mistake as the dive hatch, which was fixed and then not checked for siblings.
##
## Authorised here rather than only hidden in the HUD. Hiding a button is a UI
## nicety; this is the check that actually holds, since any peer can call an any_peer
## rpc whatever its own interface shows.
@rpc("any_peer", "reliable")
func request_choice(descend: bool) -> void:
	if not multiplayer.is_server() or game_over or not awaiting_choice:
		return
	# 0 means the call came from this process — a listen-server host pressing its own
	# button rather than an rpc arriving over the wire.
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != leader_peer_id():
		push_warning("peer %d tried to call the bell but the lead diver is %d"
				% [sender, leader_peer_id()])
		return
	if descend:
		choose_descend()
	else:
		choose_extract()



## Server (host UI): bank the haul and end the run.
func choose_extract() -> void:
	if not multiplayer.is_server() or game_over:
		return
	awaiting_choice = false
	_finish(true)


## Server (host UI): push deeper — reset the site, harder and richer.
func choose_descend() -> void:
	if not multiplayer.is_server() or game_over or not awaiting_choice:
		return
	awaiting_choice = false
	depth += 1
	oxygen = minf(oxygen + GameRules.DESCEND_O2_BONUS, _max_oxygen)
	extraction_progress = 0.0
	_bell = null
	_maw_spawned = false
	for holder: Node2D in [enemies, loot, projectiles]:
		for child in holder.get_children():
			child.queue_free()
	var offsets := _spawn_offsets()
	var i := 0
	for p in players.get_children():
		if not p is Player or p.is_queued_for_deletion():
			continue
		var diver := p as Player
		if diver.downed:
			# The pressure drop snaps them back on their feet.
			diver.downed = false
			diver.revive_progress = 0.0
			diver.hp = diver.max_hp * GameRules.BLEED_FRACTION
		diver.teleport.rpc(GameRules.ARENA_SIZE / 2.0 + offsets[i % offsets.size()])
		i += 1
	_build_site.call_deferred()
	_rpc_toast.rpc("Descending... depth %d. The trench grows hungrier." % depth)


func _offer_upgrades() -> void:
	_rpc_toast.rpc("Level %d — choose your upgrade!" % team_level)
	for p in players.get_children():
		if p is Player and not p.dead and not p.is_queued_for_deletion():
			p.queue_offer(_roll_offer(p))


## Roll up to 3 distinct options for one player: new weapons (if a slot is
## free), level-ups for owned weapons, and passives below their cap. An
## available evolution always claims the first slot — it's the jackpot card.
func _roll_offer(p: Player) -> Array:
	var options: Array = []
	for id in p.weapons:
		if p.weapons[id] == GameRules.WEAPON_MAX_LEVEL and Weapons.EVOLUTIONS.has(id) \
				and p.passives.get(Weapons.EVOLUTIONS[id].requires, 0) > 0:
			options.append("evolve_" + id)
			break
	var pool: Array = []
	for id in Weapons.WEAPONS:
		if p.weapons.has(id):
			if p.weapons[id] < GameRules.WEAPON_MAX_LEVEL:
				pool.append(id)
		elif p.weapons.size() < GameRules.MAX_WEAPONS:
			pool.append(id)
	for id in Weapons.PASSIVES:
		if p.passives.get(id, 0) < GameRules.PASSIVE_MAX_LEVEL:
			pool.append(id)
	while options.size() < 3 and not pool.is_empty():
		var i := _rng.randi() % pool.size()
		options.append(pool[i])
		pool.remove_at(i)
	return options


func _finish(win: bool) -> void:
	_rpc_hud.rpc(oxygen, crates_left, team_level, team_xp, xp_needed, elapsed,
			extraction_progress, depth, salvage_earned, awaiting_choice, decision_left,
			quest_kind, quest_progress, quest_done)
	_rpc_game_over.rpc(win, salvage_earned if win else 0)
	for e in enemies.get_children():
		e.queue_free()


func _on_peer_left(pid: int) -> void:
	var node := players.get_node_or_null("Player%d" % pid)
	if node != null:
		node.queue_free()
	if _started and not game_over:
		# Deferred so the freed node no longer counts among the living.
		_check_wipe.call_deferred()


func _check_wipe() -> void:
	if not game_over and _started and _active_players().is_empty():
		_finish(false)


## Players who can still act: not dead, not downed.
func _active_players() -> Array[Player]:
	var out: Array[Player] = []
	for p in players.get_children():
		if p is Player and not p.dead and not p.downed and not p.is_queued_for_deletion():
			out.append(p)
	return out


func _build_walls() -> void:
	var size := GameRules.ARENA_SIZE
	var thickness := 32.0
	var specs := [
		[Vector2(size.x / 2, -thickness / 2), Vector2(size.x + thickness * 2, thickness)],
		[Vector2(size.x / 2, size.y + thickness / 2), Vector2(size.x + thickness * 2, thickness)],
		[Vector2(-thickness / 2, size.y / 2), Vector2(thickness, size.y + thickness * 2)],
		[Vector2(size.x + thickness / 2, size.y / 2), Vector2(thickness, size.y + thickness * 2)],
	]
	for spec in specs:
		var wall := StaticBody2D.new()
		wall.collision_layer = WALL_LAYER
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = spec[1]
		shape.shape = rect
		wall.add_child(shape)
		wall.position = spec[0]
		add_child(wall)


# --- Client-side state mirrors --------------------------------------------


@rpc("authority", "unreliable_ordered")
func _rpc_hud(o: float, c: int, lvl: int, xp: int, need: int, t: float, ext: float,
		d: int, salvage: int, awaiting: bool, decision: float,
		qk: String, qp: float, qd: bool) -> void:
	oxygen = o
	crates_left = c
	team_level = lvl
	team_xp = xp
	xp_needed = need
	elapsed = t
	extraction_progress = ext
	depth = d
	salvage_earned = salvage
	awaiting_choice = awaiting
	decision_left = decision
	quest_kind = qk
	quest_progress = qp
	quest_done = qd


@rpc("authority", "call_local", "reliable")
func _rpc_toast(text: String) -> void:
	$HUD.show_toast(text)


@rpc("authority", "call_local", "reliable")
func _rpc_game_over(win: bool, banked: int) -> void:
	game_over = true
	victory = win
	banked_salvage = banked
	awaiting_choice = false
	# Progression is client-owned: this rpc is authority/call_local, so every diver
	# banks the team haul into their OWN station. A dedicated server has no
	# progression to keep, and letting it run this would write a save file inside
	# the container for a diver that does not exist.
	if not Net.is_dedicated():
		# Each dive is a day: every diver's calendar turns when the run ends.
		Station.advance_day()
		if win:
			Station.bank_salvage(banked)
