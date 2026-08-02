extends Node2D
## Cosmetic melee impact (cutter slash / drill grind). Deterministic from
## spawn data — every peer animates locally; the server frees it and the
## despawn replicates. Damage is applied server-side by the firing player.

var tint := Color.WHITE
var visual_scale := 1.0


func _ready() -> void:
	$Sprite.modulate = tint
	scale = Vector2.ONE * visual_scale
	Sfx.play_at("shoot", global_position, -14.0, 0.2)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * visual_scale * 1.5, 0.16)
	tween.tween_property($Sprite, "modulate:a", 0.0, 0.18)
	if multiplayer.is_server():
		get_tree().create_timer(0.25).timeout.connect(queue_free)
