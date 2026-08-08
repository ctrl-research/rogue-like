extends Node2D
## The submarine — the crew's walkable homebase and multiplayer lobby.
## Between dives everyone is aboard: walk to the CONSOLE (upgrades + winch),
## the LOCKER (diver classes), the STASH (the ledger), or the HATCH (the
## lead diver starts the dive; the crew leaves or disbands here too).
##
## Roster model: no MultiplayerSpawner and no per-diver synchronizers —
## joiners can arrive before their scene loads, and the host leaves the sub
## a few frames before the crew does, so anything addressed to a node inside
## this scene can land on a peer that hasn't built it yet or has already
## moved on. Instead the host owns a pid -> seat roster broadcast over
## the Net lobby channel (see net.gd), each peer reconciles
## deterministically-named local nodes (Divers/D<pid>), and each diver's
## owner broadcasts its own position. Clients announce themselves (with
## retry) until they appear in the roster.

const DIVER_SCENE := preload("res://scenes/sub_diver.tscn")

const HULL_TEXTURE := preload("res://assets/sprites/sub_hull.png")
const HULL_ORIGIN := Vector2(172, 112)  # centres the 296x136 hull on the view
## Walkable deck: the hull's midsection, inside its plating. Roughly a third of
## the old box (issue #32) — small enough that the whole boat fits on screen at
## 2x zoom, so the crew reads at a size where you can tell who is who.
const INTERIOR := Rect2(208, 124, 204, 112)
const STATION_RANGE := 30.0
const WALL_LAYER := 4  # same hull layer the game scene uses

const OPEN_WATER := Color("070f16")  # the sea the boat is sitting in
## How long to wait for the peer connection before saying something useful.
## Signalling completing while the connection never does means ICE found no
## route between the two peers — see the [signaling] log for the candidate types
## it tried. That is a network problem, not something the crew can act on in the
## sub, so the message says what happened rather than guessing at a cause.
const LINK_STALL_SECONDS := 12.0

var _roster := {}  # pid -> seat {diver, profile} (host-authoritative, mirrored)
var _entered_online := false  # session died while aboard -> back to the menu
## Whether the HOST has us in its roster. Deliberately not "are we in _roster":
## we put ourselves in there so we can see our own diver, and conflating the two
## made the announce loop believe it had already been acknowledged and go quiet.
var _acknowledged := false
var _announce_cd := 0.0
var _link_wait := 0.0  # seconds an online client has been waiting for the mesh
var _link_tick := 0.0
var _stations: Array[Dictionary] = []
var _prompt: Label
var _panel: PanelContainer
var _panel_kind := ""
var _day_label: Label
var _crew_label: Label
var _share_url := ""

@onready var divers: Node2D = $Divers


func _ready() -> void:
	# The interior is built as later siblings of Divers — lift the crew
	# above the deck plates or they'd render underneath.
	divers.z_index = 5
	_build_interior()
	_build_ui()
	_entered_online = Net.is_online
	Station.changed.connect(_on_station_changed)
	Net.player_count_changed.connect(_refresh_wall_text)
	Net.session_ended.connect(func() -> void: Net.leave())
	Net.sub_roster_received.connect(_on_roster)
	Net.sub_pos_received.connect(_on_remote_pos)
	if multiplayer.is_server():
		Net.sub_aboard_received.connect(_on_aboard)
		multiplayer.peer_disconnected.connect(_on_peer_left)
		# A dedicated server takes no seat: it has no diver, no Station and no
		# profile. Seating it would put a phantom body on the deck and inflate the
		# crew, which sets enemy counts and HP scaling.
		if not Net.is_dedicated():
			_roster[1] = _my_seat()
		_broadcast_roster()
	else:
		# Draw ourselves immediately rather than waiting to be acknowledged; the
		# host's roster reconciles us into a seat when it lands.
		_keep_self_aboard()
		_spawn_diver(multiplayer.get_unique_id(), _my_seat(), 0)
	_refresh_wall_text()


func _process(delta: float) -> void:
	# A session that dies without a session_ended signal (e.g. a LAN join
	# that never connected) leaves us aboard a ghost sub — bail to the menu.
	if _entered_online and not Net.is_online:
		Net.leave()
		return
	if not multiplayer.is_server() and not _acknowledged:
		# Only announce once the mesh actually has the host. rpc_id to a peer
		# that isn't connected yet just pushes "unknown peer ID: 1" every retry,
		# which reads like the announce is at fault when the truth is that the
		# peer connection never came up — the error points at the wrong thing.
		if multiplayer.get_peers().has(1):
			_announce_cd -= delta
			if _announce_cd <= 0.0:
				_announce_cd = 0.5
				Net.sub_aboard.rpc_id(1, _my_seat())
		else:
			_note_link_wait(delta)
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_E:
		if _panel.visible:
			_close_panel()
		else:
			var station := _nearest_station()
			if not station.is_empty():
				_open_panel(station.id)
	elif key.physical_keycode == KEY_ESCAPE and _panel.visible:
		_close_panel()


# --- Roster ------------------------------------------------------------------


## Host: a crew member announced themselves (or changed class/appearance).
## Sanitized here, at the trust boundary, so nothing downstream has to wonder
## whether a seat came from us or off the wire.
func _on_aboard(pid: int, seat: Dictionary) -> void:
	var clean := Appearance.sanitize_seat(seat)
	if Appearance.seat_key(_roster.get(pid)) != Appearance.seat_key(clean):
		_roster[pid] = clean
		_broadcast_roster()


func _on_remote_pos(pid: int, pos: Vector2) -> void:
	var node: Node = divers.get_node_or_null("D%d" % pid)
	if node != null and not node.is_queued_for_deletion():
		node.remote_position(pos)


func _on_roster(roster: Dictionary) -> void:
	# Acknowledged only if the HOST's roster names us — checked before we add
	# ourselves below, or we would be answering our own announce.
	if roster.has(multiplayer.get_unique_id()):
		_acknowledged = true
	_roster = roster
	# You are always aboard your own sub. Until the host acknowledges the
	# announce, its roster doesn't mention you — and culling against it would
	# delete the diver you're standing in, leaving a client alone in an empty
	# boat with no body of its own. That reads as a broken game rather than as
	# "nobody else is here yet", which is what it actually is.
	_keep_self_aboard()
	for child in divers.get_children():
		var pid := int(str(child.name).trim_prefix("D"))
		if not _roster.has(pid):
			child.queue_free()
	# "slot" is the position on the deck; "seat" is the roster entry. They were
	# both called seat before appearance moved into the roster, which made the
	# spawn call read as though it passed the entry twice.
	var slot := 0
	for pid in _roster:
		slot += 1
		var node_name := "D%d" % pid
		var existing: Node = divers.get_node_or_null(node_name)
		if existing != null and not existing.is_queued_for_deletion():
			if Appearance.seat_key(existing.seat) != Appearance.seat_key(_roster[pid]):
				existing.seat = Appearance.sanitize_seat(_roster[pid])
				existing.refresh_look()
			continue
		_spawn_diver(pid, _roster[pid], slot)
	_refresh_wall_text()


## Count the wait and keep the crew readout honest about it, once a second.
func _note_link_wait(delta: float) -> void:
	_link_wait += delta
	_link_tick -= delta
	if _link_tick <= 0.0:
		_link_tick = 1.0
		_refresh_wall_text()


## Our own seat, as announced to the host and drawn locally.
func _my_seat() -> Dictionary:
	return Appearance.make_seat(Station.diver, Station.profile)


func _keep_self_aboard() -> void:
	if Net.is_dedicated():
		return  # nothing to keep aboard; the server is not a diver
	# Overwrite rather than fill-if-missing: we are the authority on our own
	# appearance, so editing it at the locker shows up on our own diver at once
	# instead of waiting for the host's roster to make the round trip. The host
	# stays authoritative for everyone else, and _acknowledged is read before
	# this runs (see _on_roster) so this cannot fake an acknowledgement.
	_roster[multiplayer.get_unique_id()] = _my_seat()


func _spawn_diver(pid: int, seat: Variant, slot: int) -> void:
	var d: CharacterBody2D = DIVER_SCENE.instantiate()
	d.name = "D%d" % pid
	d.peer_id = pid
	d.seat = Appearance.sanitize_seat(seat)
	# Spaced along the deck's lower half, clear of the stations up top.
	d.position = INTERIOR.position + Vector2(34 + 40 * slot, 76)
	Fx.attach_shadow(d)
	divers.add_child(d)


func _broadcast_roster() -> void:
	Net.sub_roster.rpc(_roster)


func _on_peer_left(pid: int) -> void:
	if _roster.has(pid):
		_roster.erase(pid)
		_broadcast_roster()


## Diver class changed at the locker: tell the crew so name tags update.
func _on_station_changed() -> void:
	if multiplayer.is_server():
		if not Net.is_dedicated() \
				and Appearance.seat_key(_roster.get(1)) != Appearance.seat_key(_my_seat()):
			_roster[1] = _my_seat()
			_broadcast_roster()
	else:
		Net.sub_aboard.rpc_id(1, _my_seat())
	if _panel.visible:
		_open_panel(_panel_kind)  # rebuild with fresh prices/levels
	_refresh_wall_text()


func _local_diver() -> Node2D:
	return divers.get_node_or_null("D%d" % multiplayer.get_unique_id())


# --- Interaction -------------------------------------------------------------


## Genuinely the nearest, not the first in range. It used to return whichever
## station appeared first in _stations, which was invisible while they were far
## enough apart that their ranges never overlapped — adding the wardrobe closed
## those gaps, and standing between two would have opened the wrong panel.
func _nearest_station() -> Dictionary:
	var me := _local_diver()
	if me == null:
		return {}
	var best := {}
	var best_dist := STATION_RANGE * STATION_RANGE
	for s in _stations:
		var dist: float = me.position.distance_squared_to(s.pos)
		if dist <= best_dist:
			best_dist = dist
			best = s
	return best


func _update_prompt() -> void:
	var station := _nearest_station()
	if station.is_empty() or _panel.visible:
		_prompt.visible = false
		return
	_prompt.visible = true
	_prompt.text = "[E] %s" % station.label
	# The prompt lives on a CanvasLayer (screen space) but the station is a world
	# position, so it has to go through the canvas transform. That used to be a
	# no-op at zoom 1 and would have silently drifted once the camera zoomed in.
	var to_screen := get_viewport().get_canvas_transform()
	_prompt.position = to_screen * station.pos + Vector2(-40, -34)


func _open_panel(kind: String) -> void:
	_panel_kind = kind
	for child in _panel.get_children():
		# Remove first: a rebuild can be triggered from one of these buttons'
		# pressed signals, and the stale content must not linger a frame.
		_panel.remove_child(child)
		child.queue_free()
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 10)
	title.modulate = Color(0.95, 0.85, 0.4)
	box.add_child(title)
	match kind:
		"console":
			title.text = "UPGRADE CONSOLE — BANK %d" % Station.bank
			StationUi.header(box, "UPGRADES")
			StationUi.build_upgrades(box)
			StationUi.header(box, "WINCH — DIVE FROM")
			StationUi.build_winch(box)
		"locker":
			title.text = "DIVER LOCKER — BANK %d" % Station.bank
			StationUi.build_divers(box)
		"wardrobe":
			# Its own station rather than a section of the locker: seven diver rows
			# plus an appearance editor overflowed the panel and cut the second
			# colour off entirely. Changes broadcast to the crew through
			# _on_station_changed below.
			title.text = "WARDROBE"
			StationUi.build_appearance(box, 48)
		"stash":
			title.text = "SALVAGE STASH"
			for line in [
				"Day %d aboard." % Station.day,
				"Banked salvage: %d" % Station.bank,
				"Deepest lair cleared: %s" % (str(Station.cleared_lair) if Station.cleared_lair > 0 else "none"),
				"Next dive starts at depth %d." % Station.dive_depth,
			]:
				var l := Label.new()
				l.text = line
				l.add_theme_font_size_override("font_size", 8)
				box.add_child(l)
		"hatch":
			title.text = "DIVE HATCH — CREW %d/%d" % [Net.player_count(), Net.MAX_PLAYERS]
			_build_hatch_panel(box)
	var hint := Label.new()
	hint.text = "[E] close"
	hint.add_theme_font_size_override("font_size", 7)
	hint.modulate = Color(0.5, 0.62, 0.72)
	box.add_child(hint)
	_panel.visible = true


func _build_hatch_panel(box: VBoxContainer) -> void:
	if Net.is_online and not Net.room_code.is_empty():
		var room := Label.new()
		room.text = "ROOM %s — friends JOIN ONLINE with the code" % Net.room_code
		room.add_theme_font_size_override("font_size", 8)
		box.add_child(room)
		_share_url = _build_share_url(Net.room_code)
		if not _share_url.is_empty():
			var copy := Button.new()
			copy.text = "COPY INVITE LINK"
			copy.add_theme_font_size_override("font_size", 8)
			copy.pressed.connect(func() -> void:
				DisplayServer.clipboard_set(_share_url)
				copy.text = "LINK COPIED!")
			box.add_child(copy)
	# Any diver may start the dive, not just the host: on a dedicated server no
	# player IS the host, so gating this on is_server() would leave the crew unable
	# to ever leave the sub. The label names the depth because it is the starter's
	# own winch that applies.
	if not Net.is_dedicated():
		var start := Button.new()
		start.text = "START THE DIVE — DEPTH %d" % Station.dive_depth
		start.add_theme_font_size_override("font_size", 9)
		start.pressed.connect(func() -> void:
			if multiplayer.is_server():
				Net.requested_depth = Station.dive_depth
				Net.start_dive()
			else:
				Net.request_dive.rpc_id(1, Station.dive_depth))
		box.add_child(start)
	else:
		var wait := Label.new()
		wait.text = "the lead diver starts the dive from here"
		wait.add_theme_font_size_override("font_size", 8)
		wait.modulate = Color(0.7, 0.8, 0.86)
		box.add_child(wait)
	if Net.is_online:
		if multiplayer.is_server():
			var disband := Button.new()
			disband.text = "DISBAND CREW"
			disband.add_theme_font_size_override("font_size", 8)
			disband.pressed.connect(func() -> void: Net.close_room())
			box.add_child(disband)
		else:
			var leave := Button.new()
			leave.text = "LEAVE CREW"
			leave.add_theme_font_size_override("font_size", 8)
			leave.pressed.connect(func() -> void: Net.leave())
			box.add_child(leave)
	else:
		var menu_btn := Button.new()
		menu_btn.text = "RETURN TO MENU"
		menu_btn.add_theme_font_size_override("font_size", 8)
		menu_btn.pressed.connect(func() -> void: Net.leave())
		box.add_child(menu_btn)


func _close_panel() -> void:
	_panel.visible = false
	_panel_kind = ""


func _build_share_url(room: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var base: Variant = JavaScriptBridge.eval("window.location.origin + window.location.pathname", true)
	if base is String and not (base as String).is_empty():
		return "%s#room=%s" % [base, room]
	return ""


# --- Interior ---------------------------------------------------------------


func _build_interior() -> void:
	# Open water around the boat, then the hull itself as one sprite — a
	# pointed bow, a blunt finned stern and sealed end compartments, which a
	# rectangle of ColorRects could never read as.
	_rect(Rect2(0, 0, 640, 360), OPEN_WATER)
	var shell := Sprite2D.new()
	shell.texture = HULL_TEXTURE
	shell.centered = false
	shell.position = HULL_ORIGIN
	add_child(shell)

	# Portholes down both sides now the crew space is narrow enough to see
	# across: the abyss looks back from either beam.
	var porthole := preload("res://assets/sprites/porthole.png")
	for x in range(int(INTERIOR.position.x) + 24, int(INTERIOR.end.x) - 12, 54):
		for y in [INTERIOR.position.y - 1, INTERIOR.end.y + 1]:
			var p := Sprite2D.new()
			p.texture = porthole
			p.position = Vector2(x, y)
			add_child(p)

	# Four stations along the deck, evenly spaced. They sit closer together than
	# before to make room for the wardrobe, which is why _nearest_station had to
	# start actually returning the nearest one — see the note there.
	var deck_top := INTERIOR.position.y + 22
	_add_station("console", "CONSOLE", preload("res://assets/sprites/console.png"),
			Vector2(INTERIOR.position.x + 36, deck_top))
	_add_station("locker", "LOCKER", preload("res://assets/sprites/locker.png"),
			Vector2(INTERIOR.position.x + 82, deck_top))
	# Wardrobe next to the locker on purpose: pick your class, then your look.
	_add_station("wardrobe", "WARDROBE", preload("res://assets/sprites/wardrobe.png"),
			Vector2(INTERIOR.position.x + 128, deck_top))
	_add_station("stash", "STASH", preload("res://assets/sprites/crate.png"),
			Vector2(INTERIOR.position.x + 174, deck_top + 2))
	_add_station("hatch", "DIVE HATCH", preload("res://assets/sprites/hatch.png"),
			Vector2(INTERIOR.end.x - 26, INTERIOR.position.y + INTERIOR.size.y / 2.0))

	# Hull collision so the crew stays aboard.
	var specs := [
		[Vector2(INTERIOR.position.x + INTERIOR.size.x / 2, INTERIOR.position.y - 8), Vector2(INTERIOR.size.x + 32, 16)],
		[Vector2(INTERIOR.position.x + INTERIOR.size.x / 2, INTERIOR.end.y + 8), Vector2(INTERIOR.size.x + 32, 16)],
		[Vector2(INTERIOR.position.x - 8, INTERIOR.position.y + INTERIOR.size.y / 2), Vector2(16, INTERIOR.size.y + 32)],
		[Vector2(INTERIOR.end.x + 8, INTERIOR.position.y + INTERIOR.size.y / 2), Vector2(16, INTERIOR.size.y + 32)],
	]
	for spec in specs:
		var wall := StaticBody2D.new()
		wall.collision_layer = WALL_LAYER
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = spec[1]
		shape.shape = rect
		wall.add_child(shape)
		wall.position = spec[0]
		add_child(wall)


func _add_station(id: String, label: String, texture: Texture2D, pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = pos
	add_child(sprite)
	_stations.append({"id": id, "label": label, "pos": pos})


func _rect(rect: Rect2, color: Color) -> void:
	var node := ColorRect.new()
	node.position = rect.position
	node.size = rect.size
	node.color = color
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)


# --- UI ----------------------------------------------------------------------


func _build_ui() -> void:
	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 10)
	_day_label.modulate = Color(0.95, 0.85, 0.4)
	_day_label.position = Vector2(56, 40)
	$UI.add_child(_day_label)

	_crew_label = Label.new()
	_crew_label.add_theme_font_size_override("font_size", 8)
	_crew_label.modulate = Color(0.62, 0.9, 1.0)
	_crew_label.position = Vector2(480, 42)
	$UI.add_child(_crew_label)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 8)
	_prompt.modulate = Color(0.95, 0.85, 0.4)
	_prompt.size = Vector2(80, 12)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	$UI.add_child(_prompt)

	_panel = PanelContainer.new()
	_panel.position = Vector2(160, 60)
	_panel.visible = false
	$UI.add_child(_panel)


func _refresh_wall_text() -> void:
	_day_label.text = "DAY %d" % Station.day
	var crew := "CREW %d/%d" % [Net.player_count(), Net.MAX_PLAYERS]
	if Net.is_online and not Net.room_code.is_empty():
		crew += "   ROOM %s" % Net.room_code
	# A crew of 1 in an online room means the mesh hasn't come up. Say so —
	# "1/4" on its own looks like a game that thinks you are alone.
	if Net.is_online and multiplayer.get_peers().is_empty():
		if _link_wait < LINK_STALL_SECONDS:
			crew += "   LINKING... %ds" % int(_link_wait)
		else:
			crew += "   NO ROUTE TO CREW — see console"
	_crew_label.text = crew
