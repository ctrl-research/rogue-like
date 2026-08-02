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

const HUD_SYNC_INTERVAL := 0.25
const WALL_LAYER := 4

# State the HUD reads. Kept current on clients via _rpc_hud / _rpc_game_over.
var oxygen := GameRules.OXYGEN_TIME
var crates_left := GameRules.CRATE_COUNT
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
var _maw_spawned := false  # one Trench Maw per site
var _rng := RandomNumberGenerator.new()

@onready var players: Node2D = $Players
@onready var enemies: Node2D = $Enemies
@onready var loot: Node2D = $Loot
@onready var projectiles: Node2D = $Projectiles
@onready var terrain: Terrain = $Terrain

var terrain_initial_cells := 0  # determinism fingerprint (see e2e)


func _ready() -> void:
	$PlayerSpawner.spawn_function = _spawn_player
	$EnemySpawner.spawn_function = _spawn_enemy
	$LootSpawner.spawn_function = _spawn_loot
	$ProjectileSpawner.spawn_function = _spawn_projectile
	_build_walls()
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_left)
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
		_spawn_waves(delta)
		_check_extraction(delta)

	_hud_accum += delta
	if _hud_accum >= HUD_SYNC_INTERVAL:
		_hud_accum = 0.0
		_rpc_hud.rpc(oxygen, crates_left, team_level, team_xp, xp_needed, elapsed,
				extraction_progress, depth, salvage_earned, awaiting_choice, decision_left)


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
		_spawn_loot_deferred.call_deferred("bell", GameRules.ARENA_SIZE / 2.0)
		_rpc_toast.rpc("All salvage secured! The dive bell has dropped — get to it!")


func _spawn_loot_deferred(kind: String, pos: Vector2) -> void:
	if game_over:
		return
	var node: Node = $LootSpawner.spawn({"kind": kind, "pos": pos})
	if kind == "bell":
		_bell = node as Area2D


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
	return node


func _spawn_enemy(data: Variant) -> Node:
	var node: Enemy = ENEMY_SCENE.instantiate()
	node.position = data.pos
	node.game = self
	node.setup(data.kind, data.hp_scale)
	return node


func _spawn_loot(data: Variant) -> Node:
	var node: Area2D
	match data.kind:
		"gem":
			node = GEM_SCENE.instantiate()
		"crate":
			node = CRATE_SCENE.instantiate()
		"bell":
			node = BELL_SCENE.instantiate()
			Sfx.play("bell", -5.0, 0.0)  # spawn replicates: rings on every peer
	node.position = data.pos
	node.set("game", self)
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
		_mark_ready(multiplayer.get_remote_sender_id(), meta)


func _mark_ready(pid: int, meta: Dictionary) -> void:
	_ready_peers[pid] = true
	_metas[pid] = meta
	if _started:
		return
	var expected: Array[int] = [1]
	for p in multiplayer.get_peers():
		expected.append(p)
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

	_build_site()
	var offsets := _spawn_offsets()
	for i in pids.size():
		$PlayerSpawner.spawn({
			"pid": pids[i],
			"index": i,
			"pos": GameRules.ARENA_SIZE / 2.0 + offsets[i % offsets.size()],
			"meta": _metas.get(pids[i], {}),
		})
	_rpc_toast.rpc("Recover %d salvage crates, then reach the dive bell. Watch your O2." % GameRules.CRATE_COUNT)


## Server: roll the site layout, broadcast so every peer builds identical
## terrain, then place the crates in their carved clearings.
func _build_site() -> void:
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
	for spot in spots:
		$LootSpawner.spawn({"kind": "crate", "pos": spot})


@rpc("authority", "call_local", "reliable")
func _rpc_build_site(map_seed: int, site_depth: int, crate_spots: PackedVector2Array) -> void:
	terrain.build(map_seed, site_depth, crate_spots)
	terrain_initial_cells = terrain.get_used_cells().size()


func _spawn_offsets() -> Array[Vector2]:
	return [Vector2(-16, -16), Vector2(16, -16), Vector2(-16, 16), Vector2(16, 16)]


func _spawn_waves(delta: float) -> void:
	_spawn_accum += delta
	var interval := clampf(1.8 - elapsed * 0.008, 0.4, 1.8) * GameRules.depth_interval_scale(depth)
	if _spawn_accum < interval or enemies.get_child_count() >= GameRules.ENEMY_CAP:
		return
	_spawn_accum = 0.0

	var alive := _active_players()
	if alive.is_empty():
		return
	var count := 1 + int(elapsed / 45.0) + (Net.player_count() - 1)
	var hp_scale := (1.0 + 0.35 * (Net.player_count() - 1)) * GameRules.depth_hp_scale(depth)
	var brute_chance := minf(0.35, elapsed / 600.0) + GameRules.depth_brute_bonus(depth)
	for i in count:
		if enemies.get_child_count() >= GameRules.ENEMY_CAP:
			break
		var anchor: Player = alive[_rng.randi() % alive.size()]
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(260.0, 400.0)
		var pos := anchor.global_position + Vector2.from_angle(angle) * dist
		pos = pos.clamp(Vector2(24, 24), GameRules.ARENA_SIZE - Vector2(24, 24))
		pos = terrain.find_open_near(pos)
		$EnemySpawner.spawn({"kind": _roll_kind(brute_chance), "pos": pos, "hp_scale": hp_scale})


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
	crates_left = GameRules.CRATE_COUNT
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
			extraction_progress, depth, salvage_earned, awaiting_choice, decision_left)
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
		d: int, salvage: int, awaiting: bool, decision: float) -> void:
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


@rpc("authority", "call_local", "reliable")
func _rpc_toast(text: String) -> void:
	$HUD.show_toast(text)


@rpc("authority", "call_local", "reliable")
func _rpc_game_over(win: bool, banked: int) -> void:
	game_over = true
	victory = win
	banked_salvage = banked
	awaiting_choice = false
	if win:
		# Every diver banks the full team haul into their own station.
		Station.bank_salvage(banked)
