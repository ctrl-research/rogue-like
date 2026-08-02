class_name Enemy
extends CharacterBody2D
## Abyssal fauna. Simulated on the server only; clients receive position via
## the MultiplayerSynchronizer and derive sprite flip / lurker camouflage
## from observed motion, so no extra state needs syncing.

const TEXTURES := {
	"barbfish": preload("res://assets/sprites/barbfish.png"),
	"brute": preload("res://assets/sprites/brute.png"),
	"lurker": preload("res://assets/sprites/lurker.png"),
	"jelly": preload("res://assets/sprites/jelly.png"),
	"jelly_small": preload("res://assets/sprites/jelly.png"),
	"maw": preload("res://assets/sprites/maw.png"),
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
}

const AMBUSH_RANGE := 110.0
const LURKER_HIDDEN_ALPHA := 0.35

var kind := "barbfish"
var game  # the Game node; untyped to avoid a class_name dependency cycle
var speed := 42.0
var hp := 12.0:
	set = _set_hp
var contact_damage := 6.0
var xp_value := 1

const CHEW_TIME := 1.2  # seconds of pushing against rock before it gives

var _ambushing := false
var _stun_left := 0.0
var _home := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _idle_time := 0.0
var _chew := 0.0


func setup(new_kind: String, hp_scale: float) -> void:
	kind = new_kind
	var spec: Dictionary = KINDS[kind]
	speed = spec.speed
	hp = spec.hp * hp_scale
	contact_damage = spec.damage
	xp_value = spec.xp
	scale = Vector2.ONE * float(spec.get("scale", 1.0))
	_ambushing = bool(spec.get("ambush", false))
	$Sprite.texture = TEXTURES[kind]


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
	if kind == "maw":
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
	velocity = dir * speed
	move_and_slide()
	_chew_rock(dir, delta)


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
		if d < best_d:
			best_d = d
			best = player
	return best


func _ambush_kind() -> bool:
	return bool(KINDS[kind].get("ambush", false))
