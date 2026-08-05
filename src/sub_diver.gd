extends CharacterBody2D
## A crew member walking the sub between dives. Purely social — no combat,
## no oxygen. The owner drives movement and broadcasts its position over the
## Net lobby channel (see net.gd "Sub channel"); other peers smooth toward
## the last position they heard.

const SPEED := 110.0
const SEND_INTERVAL := 1.0 / 15.0  # position broadcasts per second
const SMOOTHING := 12.0

var peer_id := 1
var diver_id := Divers.DEFAULT

var _target := Vector2.ZERO  # remote divers: latest broadcast position
var _send_cd := 0.0


func _ready() -> void:
	_target = position
	refresh_label()


func refresh_label() -> void:
	var title: String = Divers.DIVERS.get(diver_id, {}).get("title", "DIVER")
	$Name.text = "%s%s" % [title, " (YOU)" if is_local() else ""]
	$Name.modulate = Color(0.62, 0.9, 1.0) if is_local() else Color(0.7, 0.8, 0.86)


func _physics_process(delta: float) -> void:
	if is_local():
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = input * SPEED
		move_and_slide()
		if velocity.x != 0.0:
			$Sprite.flip_h = velocity.x < 0.0
		_send_cd -= delta
		if _send_cd <= 0.0 and not multiplayer.get_peers().is_empty():
			_send_cd = SEND_INTERVAL
			Net.sub_pos.rpc(position)
		return

	var previous := position
	position = position.lerp(_target, minf(SMOOTHING * delta, 1.0))
	if absf(position.x - previous.x) > 0.01:
		$Sprite.flip_h = position.x < previous.x


## Called from sub.gd when this diver's owner broadcasts a new position.
func remote_position(pos: Vector2) -> void:
	_target = pos


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()
