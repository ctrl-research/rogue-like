extends Node2D
## Cosmetic sonar pulse: a ring that expands to the pulse radius and fades.
## Deterministic from spawn data, so all peers animate locally; the server
## frees it (despawn replicates via the spawner).

const SPRITE_RADIUS := 29.0  # ring.png's drawn radius at scale 1

var radius := 85.0


func _ready() -> void:
	$Ring.scale = Vector2.ONE * 0.15
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property($Ring, "scale", Vector2.ONE * (radius / SPRITE_RADIUS), 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property($Ring, "modulate:a", 0.0, 0.4)
	if multiplayer.is_server():
		get_tree().create_timer(0.5).timeout.connect(queue_free)
