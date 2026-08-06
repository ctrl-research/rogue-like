extends CharacterBody2D
## A crew member walking the sub between dives. Purely social — no combat,
## no oxygen. The owner drives movement and broadcasts its position over the
## Net lobby channel (see net.gd "Sub channel"); other peers smooth toward
## the last position they heard.

const SPEED := 110.0
const SEND_INTERVAL := 1.0 / 15.0  # position broadcasts per second
const SMOOTHING := 12.0

var peer_id := 1
## {diver, profile} — see Appearance.make_seat. Set by sub.gd before add_child.
var seat := Appearance.make_seat(Divers.DEFAULT, Appearance.default_profile())

var _target := Vector2.ZERO  # remote divers: latest broadcast position
var _send_cd := 0.0


func _ready() -> void:
	_target = position
	refresh_look()


## Name tag and suit colours. The sub is where you see the crew standing still
## long enough to read them, so this doubles as the lobby's character preview —
## the whole point of showing chosen names and colours here rather than only
## once the dive starts.
func refresh_look() -> void:
	var title: String = Divers.DIVERS.get(str(seat.get("diver", "")), {}).get("title", "DIVER")
	var prof: Dictionary = seat.get("profile", {}) if seat.get("profile") is Dictionary else {}
	var chosen := Appearance.sanitize_name(str(prof.get("name", "")))
	# A chosen name wins over the class title — two divers of the same class need
	# telling apart by something. Falling back to the title rather than to a
	# positional "P2" keeps an unnamed crew reading the way it did before.
	$Name.text = "%s%s" % [chosen if not chosen.is_empty() else title,
			" (YOU)" if is_local() else ""]
	$Name.modulate = Color(0.62, 0.9, 1.0) if is_local() else Color(0.7, 0.8, 0.86)
	Appearance.apply($Sprite, seat.get("profile", {}))


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
