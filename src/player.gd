class_name Player
extends CharacterBody2D
## A diver. Movement is client-authoritative (synced via MovementSync, whose
## authority is the owning peer); hp/dead are server-authoritative (StateSync,
## authority 1). Auto-fire runs on the server only.

const TINTS: Array[Color] = [
	Color.WHITE,
	Color(0.65, 0.9, 1.0),
	Color(0.7, 1.0, 0.7),
	Color(1.0, 0.75, 0.85),
]
const FIRE_RANGE := 230.0

var peer_id := 1
var player_index := 0
var game  # the Game node; untyped to avoid a class_name dependency cycle

var move_speed := 90.0
var fire_rate := 1.1  # shots per second
var damage := 10.0
var max_hp := 100.0
var hp := 100.0
var dead := false:
	set = _set_dead

var _fire_cd := 0.0


func _ready() -> void:
	$MovementSync.set_multiplayer_authority(peer_id)
	$Camera.enabled = _is_local()
	$Sprite.self_modulate = TINTS[player_index % TINTS.size()]
	$NameLabel.text = "P%d" % (player_index + 1)
	$Camera.limit_left = 0
	$Camera.limit_top = 0
	$Camera.limit_right = int(GameRules.ARENA_SIZE.x)
	$Camera.limit_bottom = int(GameRules.ARENA_SIZE.y)


func _physics_process(delta: float) -> void:
	if dead or game == null or game.game_over:
		return

	if _is_local():
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = input * move_speed
		move_and_slide()

	if velocity.x != 0.0:
		$Sprite.flip_h = velocity.x < 0.0

	if multiplayer.is_server():
		_fire_cd -= delta
		if _fire_cd <= 0.0:
			_try_fire()


## Server only.
func take_damage(amount: float) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		dead = true
		game.on_player_died()


## Called by the server on every peer so stats stay consistent everywhere
## (speed matters on the owning client, damage/fire rate on the server).
@rpc("any_peer", "call_local", "reliable")
func apply_upgrade(kind: String) -> void:
	match kind:
		"damage":
			damage *= 1.25
		"fire_rate":
			fire_rate *= 1.2
		"speed":
			move_speed *= 1.12
		"hull":
			max_hp += 20.0
			hp = minf(hp + 25.0, max_hp)


static func upgrade_label(kind: String) -> String:
	match kind:
		"damage":
			return "sharper harpoons"
		"fire_rate":
			return "faster winch"
		"speed":
			return "streamlined fins"
		"hull":
			return "reinforced suit"
	return kind


func _try_fire() -> void:
	var target := _nearest_enemy()
	if target == null:
		return
	_fire_cd = 1.0 / fire_rate
	var dir := (target.global_position - global_position).normalized()
	game.fire_projectile(global_position, dir, damage)


func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d := FIRE_RANGE * FIRE_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Node2D
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func _set_dead(value: bool) -> void:
	dead = value
	if not is_node_ready():
		return
	visible = not value
	$Collision.set_deferred("disabled", value)
