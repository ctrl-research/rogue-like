extends Area2D
## Straight-flying bolt (harpoon or arc lance). Flight is deterministic from
## spawn data, so every peer simulates it locally — no position sync needed.
## The server alone detects hits and frees the node; despawn replicates via
## the spawner.

var dir := Vector2.RIGHT
var speed := 260.0
var damage := 10.0
var life := 1.4
var pierce := 1
var bounces := 0  # chain harpoon: retargets after a kill instead of dying
var tint := Color.WHITE
var sprite_scale := Vector2.ONE

var _hit: Array[Node2D] = []


func _ready() -> void:
	rotation = dir.angle()
	$Sprite.modulate = tint
	$Sprite.scale = sprite_scale
	Sfx.play_at("shoot", global_position, -12.0)
	set_deferred("monitoring", multiplayer.is_server())
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += dir * speed * delta
	life -= delta
	if life <= 0.0:
		if multiplayer.is_server():
			queue_free()
		else:
			# Never free spawner-tracked nodes on clients; just hide until the
			# server's despawn arrives.
			visible = false


func _on_body_entered(body: Node2D) -> void:
	if not body is Enemy:
		return
	body.take_damage(damage)
	_hit.append(body)
	if bounces > 0:
		var next := _next_chain_target()
		if next != null:
			bounces -= 1
			dir = (next.global_position - global_position).normalized()
			rotation = dir.angle()
			life = maxf(life, 0.6)
			return
	pierce -= 1
	if pierce <= 0:
		queue_free()


func _next_chain_target() -> Node2D:
	var best: Node2D = null
	var best_d := 130.0 * 130.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Node2D
		if _hit.has(enemy) or enemy.is_queued_for_deletion():
			continue
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best
