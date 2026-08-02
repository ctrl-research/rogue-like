extends Node2D
## Depth charge: sits on its fuse, then explodes for area damage. The fuse and
## flash animation are deterministic from spawn data so all peers play them
## locally; only the server applies damage and frees the node.

var damage := 32.0
var radius := 52.0
var fuse := 0.9
var stun := 0.0  # pressure bomb evolution: seconds of stun on hit

var _exploded := false


func _process(delta: float) -> void:
	if _exploded:
		return
	fuse -= delta
	$Mine.visible = int(fuse * 8.0) % 2 == 0  # arming blink
	if fuse <= 0.0:
		_explode()


func _explode() -> void:
	_exploded = true
	Sfx.play_at("explosion", global_position, -4.0)
	Fx.shake_near(self, global_position, 280.0, 3.5)
	$Mine.visible = false
	$Flash.visible = true
	$Flash.scale = Vector2(0.4, 0.4)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property($Flash, "scale", Vector2(radius / 32.0, radius / 32.0), 0.25)
	tween.tween_property($Flash, "modulate:a", 0.0, 0.3)

	if multiplayer.is_server():
		for e in get_tree().get_nodes_in_group("enemies"):
			var enemy := e as Enemy
			if global_position.distance_to(enemy.global_position) <= radius:
				if stun > 0.0:
					enemy.stun(stun)
				enemy.take_damage(damage)
		get_tree().create_timer(0.35).timeout.connect(queue_free)
