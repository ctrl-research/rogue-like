extends Area2D
## Objective pickup. Collect them all to summon the dive bell.

var game  # the Game node


func _ready() -> void:
	tree_exiting.connect(_on_exiting)
	set_deferred("monitoring", multiplayer.is_server())
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _on_exiting() -> void:
	if not is_inside_tree():
		return
	for p in get_tree().get_nodes_in_group("players"):
		if global_position.distance_to(p.global_position) < 48.0:
			Sfx.play_at("crate", global_position, -6.0)
			Fx.poof(self, global_position, Color(0.95, 0.85, 0.4))
			return


func _on_body_entered(body: Node2D) -> void:
	if body is Player and not body.dead and not body.downed:
		game.on_crate_collected()
		queue_free()
