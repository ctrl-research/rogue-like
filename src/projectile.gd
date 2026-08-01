extends Area2D
## Harpoon bolt. Flight is deterministic (straight line from spawn data), so
## every peer simulates it locally — no position sync needed. The server alone
## detects hits and frees the node; despawn replicates via the spawner.

var dir := Vector2.RIGHT
var speed := 260.0
var damage := 10.0
var life := 1.4


func _ready() -> void:
	rotation = dir.angle()
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
	if body is Enemy:
		body.take_damage(damage)
		queue_free()
