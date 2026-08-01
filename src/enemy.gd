class_name Enemy
extends CharacterBody2D
## Abyssal fauna. Simulated on the server only; clients receive position via
## the MultiplayerSynchronizer and derive sprite flip from movement.

var game  # the Game node; untyped to avoid a class_name dependency cycle
var speed := 42.0
var hp := 20.0
var contact_damage := 8.0
var xp_value := 1

var _last_x := 0.0


func setup(kind: String, hp_scale: float) -> void:
	match kind:
		"brute":
			$Sprite.texture = preload("res://assets/sprites/brute.png")
			speed = 26.0
			hp = 70.0
			contact_damage = 18.0
			xp_value = 3
		_:  # barbfish
			$Sprite.texture = preload("res://assets/sprites/barbfish.png")
			speed = 42.0
			hp = 20.0
			contact_damage = 8.0
			xp_value = 1
	hp *= hp_scale


func _ready() -> void:
	add_to_group("enemies")
	_last_x = global_position.x
	if multiplayer.is_server():
		$DamageTimer.timeout.connect(_on_damage_tick)


func _physics_process(_delta: float) -> void:
	if multiplayer.is_server():
		if game == null or game.game_over:
			velocity = Vector2.ZERO
			return
		var target := _nearest_player()
		if target != null:
			velocity = (target.global_position - global_position).normalized() * speed
			move_and_slide()

	var dx := global_position.x - _last_x
	if absf(dx) > 0.01:
		$Sprite.flip_h = dx < 0.0
	_last_x = global_position.x


## Server only.
func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		game.on_enemy_killed(self)


func _on_damage_tick() -> void:
	if game == null or game.game_over:
		return
	for body in $DamageArea.get_overlapping_bodies():
		if body is Player and not body.dead:
			body.take_damage(contact_damage)


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in game.players.get_children():
		var player := p as Player
		if player.dead:
			continue
		var d := global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = player
	return best
