extends Area2D
## Cosmetic only — pickup logic lives in the player's magnet area. Despawns
## replicate from the server; proximity to a diver at despawn distinguishes
## "hoovered up" (chirp) from a site-clear (silent).


func _ready() -> void:
	tree_exiting.connect(_on_exiting)


func _on_exiting() -> void:
	if not is_inside_tree():
		return
	for p in get_tree().get_nodes_in_group("players"):
		if global_position.distance_to(p.global_position) < 48.0:
			Sfx.play_at("pickup", global_position, -10.0)
			return
