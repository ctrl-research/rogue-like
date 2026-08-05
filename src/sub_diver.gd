extends CharacterBody2D
## A crew member walking the sub between dives. Purely social — no combat,
## no oxygen. Movement is client-authoritative like the in-run diver; every
## peer builds the same roster locally (see sub.gd), so only position syncs.

const SPEED := 110.0

var peer_id := 1
var diver_id := Divers.DEFAULT


func _ready() -> void:
	$Sync.set_multiplayer_authority(peer_id)
	refresh_label()


func refresh_label() -> void:
	var title: String = Divers.DIVERS.get(diver_id, {}).get("title", "DIVER")
	$Name.text = "%s%s" % [title, " (YOU)" if is_local() else ""]
	$Name.modulate = Color(0.62, 0.9, 1.0) if is_local() else Color(0.7, 0.8, 0.86)


func _physics_process(_delta: float) -> void:
	if not is_local():
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * SPEED
	move_and_slide()
	if velocity.x != 0.0:
		$Sprite.flip_h = velocity.x < 0.0


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()
