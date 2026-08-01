extends Area2D
## Objective pickup. Collect them all to summon the dive bell.

var game  # the Game node


func _ready() -> void:
	set_deferred("monitoring", multiplayer.is_server())
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player and not body.dead:
		game.on_crate_collected()
		queue_free()
