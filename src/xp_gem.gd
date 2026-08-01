extends Area2D
## Biomass dropped by dead fauna. Static: position comes from spawn data.
## Pickup is resolved on the server; despawn replicates via the spawner.

var game  # the Game node


func _ready() -> void:
	# Deferred: gems spawn from kill callbacks while physics is flushing.
	set_deferred("monitoring", multiplayer.is_server())
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player and not body.dead:
		game.add_xp(GameRules.XP_PER_GEM)
		queue_free()
