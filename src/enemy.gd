class_name Enemy
extends CharacterBody2D
## Abyssal fauna. Simulated on the server only; clients receive position via
## the MultiplayerSynchronizer and derive sprite flip / lurker camouflage
## from observed motion, so no extra state needs syncing.

const TEXTURES := {
	"barbfish": preload("res://assets/sprites/barbfish.png"),
	"brute": preload("res://assets/sprites/brute.png"),
	"warden": preload("res://assets/sprites/warden.png"),
	"lurker": preload("res://assets/sprites/lurker.png"),
	"jelly": preload("res://assets/sprites/jelly.png"),
	"jelly_small": preload("res://assets/sprites/jelly.png"),
	"maw": preload("res://assets/sprites/maw.png"),
	"beast": preload("res://assets/sprites/lurker.png"),
}

## kind -> stats and behavior flags. "ambush": sit camouflaged until a diver
## comes close, then strike. "scale": node scale (affects collision too).
const KINDS := {
	"barbfish": {"speed": 42.0, "hp": 12.0, "damage": 6.0, "xp": 1},
	"brute": {"speed": 26.0, "hp": 60.0, "damage": 18.0, "xp": 3},
	"lurker": {"speed": 78.0, "hp": 25.0, "damage": 14.0, "xp": 3, "ambush": true},
	"jelly": {"speed": 12.0, "hp": 45.0, "damage": 20.0, "xp": 2},
	"jelly_small": {"speed": 30.0, "hp": 10.0, "damage": 8.0, "xp": 1, "scale": 0.6},
	# Leashed: the Maw guards the salvage zone it spawned in and returns home
	# rather than chasing across the map — crates spawn >= 220px from the
	# arena center, so it can never end up camping the dive bell.
	"maw": {"speed": 18.0, "hp": 480.0, "damage": 30.0, "xp": 10, "scale": 1.25, "leash": 170.0},
	# The hunt quest's quarry: a scarred alpha lurker lairing in a clearing.
	# Leashed for the same bell-safety reason, and so the hunt means going to
	# it — the sonar pings lead the way.
	"beast": {"speed": 62.0, "hp": 300.0, "damage": 24.0, "xp": 8, "scale": 1.5,
			"leash": 240.0, "tint": Color(1.0, 0.6, 0.5)},
	# The Trench Warden: boss-lair guardian (every 5th depth). Slow stalker
	# that periodically winds up and charges, smashing through rock, and
	# calls lurkers up from the dark. Wide leash — it owns the whole lair.
	"warden": {"speed": 26.0, "hp": 2400.0, "damage": 34.0, "xp": 30, "scale": 2.0,
			"leash": 340.0, "charge": true, "summon": true},
}

# Warden charge attack: stop and telegraph, then dash — the dash carves
# through rock, so there is no safe pocket to hide in.
const CHARGE_CD := 6.5
const CHARGE_WINDUP := 0.8
const CHARGE_SPEED := 300.0
const CHARGE_TIME := 0.7
const CHARGE_RANGE := 420.0
const SUMMON_CD := 9.0
const SUMMON_COUNT := 2

const AMBUSH_RANGE := 110.0
const LURKER_HIDDEN_ALPHA := 0.35

var kind := "barbfish"
var game  # the Game node; untyped to avoid a class_name dependency cycle
var speed := 42.0
var hp := 12.0:
	set = _set_hp
var max_hp := 12.0  # set once in setup; the HUD boss bar reads hp/max_hp
var contact_damage := 6.0
var xp_value := 1

const CHEW_TIME := 1.2  # seconds of pushing against rock before it gives

var _ambushing := false
var _stun_left := 0.0
var _home := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _idle_time := 0.0
var _chew := 0.0
var _charge_cd := CHARGE_CD  # warden: countdown to the next charge
var _windup := 0.0  # warden: telegraph time left before the dash
var _dash := 0.0  # warden: dash time left
var _dash_dir := Vector2.ZERO
var _summon_cd := SUMMON_CD


func setup(new_kind: String, hp_scale: float) -> void:
	kind = new_kind
	var spec: Dictionary = KINDS[kind]
	speed = spec.speed
	hp = spec.hp * hp_scale
	contact_damage = spec.damage
	xp_value = spec.xp
	scale = Vector2.ONE * float(spec.get("scale", 1.0))
	_ambushing = bool(spec.get("ambush", false))
	max_hp = hp
	$Sprite.texture = TEXTURES[kind]
	# Whole-node modulate, not Sprite.self_modulate — hit flashes tween
	# self_modulate back to white and would wipe a tint stored there.
	modulate = spec.get("tint", Color.WHITE)


func _ready() -> void:
	add_to_group("enemies")
	_home = global_position
	_last_pos = global_position
	tree_exiting.connect(_on_exiting)
	if multiplayer.is_server():
		$DamageTimer.timeout.connect(_on_damage_tick)


## Hit feedback on every peer: hp replicates on change, so the setter fires
## locally wherever damage lands — no extra rpcs.
func _set_hp(value: float) -> void:
	var old := hp
	hp = value
	if not is_node_ready() or value >= old:
		return
	Fx.damage_number(self, global_position, old - value)
	Sfx.play_at("hit", global_position, -10.0)
	$Sprite.self_modulate = Color(1.0, 0.4, 0.4)
	$Sprite.scale = Vector2(1.15, 1.15)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property($Sprite, "self_modulate", Color.WHITE, 0.15)
	tween.tween_property($Sprite, "scale", Vector2.ONE, 0.12)


func _on_exiting() -> void:
	# Death (and site-clear) feedback: despawns replicate, so this pops on
	# every peer without extra sync.
	if game == null or game.game_over or not is_inside_tree():
		return
	Fx.poof(game, global_position, Color(0.75, 0.45, 0.6))
	Sfx.play_at("kill", global_position, -8.0)
	if kind in ["maw", "beast", "warden"]:
		Sfx.play_at("explosion", global_position, -2.0)
		Fx.shake_near(game, global_position, 420.0, 5.0)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_tick(delta)

	# Visuals on every peer, derived from observed motion.
	var moved := global_position.distance_squared_to(_last_pos) > 0.0001
	_idle_time = 0.0 if moved else _idle_time + delta
	if absf(global_position.x - _last_pos.x) > 0.01:
		$Sprite.flip_h = global_position.x < _last_pos.x
	if _ambush_kind():
		$Sprite.modulate.a = LURKER_HIDDEN_ALPHA if _idle_time > 0.25 else 1.0
	_last_pos = global_position


## Server only: brief stun (pressure bomb).
func stun(duration: float) -> void:
	_stun_left = maxf(_stun_left, duration)


## Server only.
func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		game.on_enemy_killed(self)


func _server_tick(delta: float) -> void:
	if game == null or game.game_over:
		velocity = Vector2.ZERO
		return
	if _stun_left > 0.0:
		_stun_left -= delta
		velocity = Vector2.ZERO
		return
	if bool(KINDS[kind].get("summon", false)):
		_summon_tick(delta)
	if bool(KINDS[kind].get("charge", false)) and _charge_tick(delta):
		return
	var target := _nearest_player()
	var leash: float = KINDS[kind].get("leash", 0.0)
	if leash > 0.0:
		# Zone guardian: only chase divers inside the home radius; otherwise
		# swim back to the post.
		if target != null and _home.distance_to(target.global_position) > leash:
			target = null
		if target == null:
			if global_position.distance_to(_home) > 8.0:
				velocity = (_home - global_position).normalized() * speed
				move_and_slide()
			else:
				velocity = Vector2.ZERO
			return
	if target == null:
		velocity = Vector2.ZERO
		return
	if _ambushing:
		if global_position.distance_to(target.global_position) <= AMBUSH_RANGE:
			_ambushing = false  # strike, and stay aggressive
		else:
			velocity = Vector2.ZERO
			return
	var dir := (target.global_position - global_position).normalized()
	# The bell's safe zone is closed to monsters. One check on the single movement
	# path every enemy type funnels through, rather than per-behaviour.
	if game != null:
		var centre: Variant = game.bell_safe_center()
		if centre != null:
			var to_centre: Vector2 = (centre as Vector2) - global_position
			var dist := to_centre.length()
			if dist <= GameRules.BELL_SAFE_RADIUS:
				# Caught inside when the bell landed: shoved out rather than killed,
				# because something invulnerable and harmless parked in the middle of
				# the crew's breathing room is worse than a brief shove.
				velocity = -to_centre.normalized() * GameRules.BELL_PUSH_SPEED
				move_and_slide()
				return
			# Heading in: slide along the edge instead of pushing through it.
			if dist - GameRules.BELL_SAFE_RADIUS < speed * delta and dir.dot(to_centre) > 0.0:
				velocity = dir.orthogonal() * speed
				move_and_slide()
				return
	velocity = dir * speed
	move_and_slide()
	_chew_rock(dir, delta)


## Warden: calls lurkers up from the dark on a fixed cadence.
func _summon_tick(delta: float) -> void:
	_summon_cd -= delta
	if _summon_cd > 0.0:
		return
	_summon_cd = SUMMON_CD
	for i in SUMMON_COUNT:
		game._spawn_enemy_deferred("lurker",
				global_position + Vector2.from_angle(randf() * TAU) * 44.0)


## Warden charge: stop and telegraph, then a rock-smashing dash toward the
## nearest diver. Returns true while the charge owns this frame's movement.
func _charge_tick(delta: float) -> bool:
	if _dash > 0.0:
		_dash -= delta
		velocity = _dash_dir * CHARGE_SPEED
		move_and_slide()
		# The dash carves through rock — a drilled pocket is no shelter.
		game.terrain.destroy_in_radius(global_position + _dash_dir * 18.0, 14.0)
		return true
	if _windup > 0.0:
		_windup -= delta
		velocity = Vector2.ZERO
		if _windup <= 0.0:
			var target := _nearest_player()
			if target != null:
				_dash = CHARGE_TIME
				_dash_dir = (target.global_position - global_position).normalized()
				Sfx.play_at("explosion", global_position, -8.0)
		return true
	_charge_cd -= delta
	if _charge_cd <= 0.0:
		var target := _nearest_player()
		if target != null and global_position.distance_to(target.global_position) <= CHARGE_RANGE:
			_charge_cd = CHARGE_CD
			_windup = CHARGE_WINDUP
			game.spawn_ring(global_position, 60.0)  # telegraph on every peer
			return true
	return false


## No pathfinding in the trench: fauna blocked by rock slowly eat through
## it. Hiding in a drilled pocket buys time, not safety.
func _chew_rock(dir: Vector2, delta: float) -> void:
	var blocked := false
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() is TileMapLayer:
			blocked = true
			break
	if not blocked:
		_chew = 0.0
		return
	_chew += delta
	if _chew >= CHEW_TIME:
		_chew = 0.0
		game.terrain.destroy_in_radius(global_position + dir * 12.0, 10.0)


func _on_damage_tick() -> void:
	if game == null or game.game_over:
		return
	for body in $DamageArea.get_overlapping_bodies():
		if body is Player and not body.dead and not body.downed:
			body.take_damage(contact_damage)


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in game.players.get_children():
		var player := p as Player
		if player.dead or player.downed:
			continue
		var d := global_position.distance_squared_to(player.global_position)
		if player.towing:
			# Fauna smell easy prey: the payload carrier reads as much
			# closer than they are, so the escort draws the horde.
			d *= 0.15
		if d < best_d:
			best_d = d
			best = player
	return best


func _ambush_kind() -> bool:
	return bool(KINDS[kind].get("ambush", false))
