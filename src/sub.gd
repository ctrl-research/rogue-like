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
## moved on. Instead the host owns a pid -> diver_id roster broadcast over
## the Net lobby channel (see net.gd), each peer reconciles
## deterministically-named local nodes (Divers/D<pid>), and each diver's
## owner broadcasts its own position. Clients announce themselves (with
## retry) until they appear in the roster.

const DIVER_SCENE := preload("res://scenes/sub_diver.tscn")

const INTERIOR := Rect2(48, 72, 544, 224)  # walkable bounds
const STATION_RANGE := 30.0
const WALL_LAYER := 4  # same hull layer the game scene uses

# Interior palette
const HULL := Color("10181e")
const ROOM := Color("182831")
const TRIM := Color("1c2a33")

var _roster := {}  # pid -> diver_id (host-authoritative, mirrored to all)
var _entered_online := false  # session died while aboard -> back to the menu
var _announce_cd := 0.0
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
		_roster[1] = Station.diver
		_broadcast_roster()
	_refresh_wall_text()


func _process(delta: float) -> void:
	# A session that dies without a session_ended signal (e.g. a LAN join
	# that never connected) leaves us aboard a ghost sub — bail to the menu.
	if _entered_online and not Net.is_online:
		Net.leave()
		return
	# Clients: announce until the host has us aboard (retries cover joins
	# that race the scene load or the WebRTC mesh coming up).
	if not multiplayer.is_server() and not _roster.has(multiplayer.get_unique_id()):
		_announce_cd -= delta
		if _announce_cd <= 0.0:
			_announce_cd = 0.5
			Net.sub_aboard.rpc_id(1, Station.diver)
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


## Host: a crew member announced themselves (or changed class at the locker).
func _on_aboard(pid: int, diver_id: String) -> void:
	if _roster.get(pid, "") != diver_id:
		_roster[pid] = diver_id
		_broadcast_roster()


func _on_remote_pos(pid: int, pos: Vector2) -> void:
	var node: Node = divers.get_node_or_null("D%d" % pid)
	if node != null and not node.is_queued_for_deletion():
		node.remote_position(pos)


func _on_roster(roster: Dictionary) -> void:
	_roster = roster
	for child in divers.get_children():
		var pid := int(str(child.name).trim_prefix("D"))
		if not _roster.has(pid):
			child.queue_free()
	var seat := 0
	for pid in _roster:
		seat += 1
		var node_name := "D%d" % pid
		var existing: Node = divers.get_node_or_null(node_name)
		if existing != null and not existing.is_queued_for_deletion():
			if existing.diver_id != _roster[pid]:
				existing.diver_id = _roster[pid]
				existing.refresh_label()
			continue
		var d: CharacterBody2D = DIVER_SCENE.instantiate()
		d.name = node_name
		d.peer_id = pid
		d.diver_id = _roster[pid]
		d.position = Vector2(200 + 60 * seat, 200)
		divers.add_child(d)
	_refresh_wall_text()


func _broadcast_roster() -> void:
	Net.sub_roster.rpc(_roster)


func _on_peer_left(pid: int) -> void:
	if _roster.has(pid):
		_roster.erase(pid)
		_broadcast_roster()


## Diver class changed at the locker: tell the crew so name tags update.
func _on_station_changed() -> void:
	if multiplayer.is_server():
		if _roster.get(1, "") != Station.diver:
			_roster[1] = Station.diver
			_broadcast_roster()
	else:
		Net.sub_aboard.rpc_id(1, Station.diver)
	if _panel.visible:
		_open_panel(_panel_kind)  # rebuild with fresh prices/levels
	_refresh_wall_text()


func _local_diver() -> Node2D:
	return divers.get_node_or_null("D%d" % multiplayer.get_unique_id())


# --- Interaction -------------------------------------------------------------


func _nearest_station() -> Dictionary:
	var me := _local_diver()
	if me == null:
		return {}
	for s in _stations:
		if me.position.distance_to(s.pos) <= STATION_RANGE:
			return s
	return {}


func _update_prompt() -> void:
	var station := _nearest_station()
	if station.is_empty() or _panel.visible:
		_prompt.visible = false
		return
	_prompt.visible = true
	_prompt.text = "[E] %s" % station.label
	_prompt.position = station.pos + Vector2(-40, -34)


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
	if multiplayer.is_server():
		var start := Button.new()
		start.text = "START THE DIVE — DEPTH %d" % Station.dive_depth
		start.add_theme_font_size_override("font_size", 9)
		start.pressed.connect(func() -> void: Net.start_dive())
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
	_rect(Rect2(0, 0, 640, 360), HULL)
	_rect(INTERIOR.grow(8), TRIM)
	_rect(INTERIOR, ROOM)
	# Deck plating seams.
	for x in range(int(INTERIOR.position.x) + 32, int(INTERIOR.end.x), 64):
		_rect(Rect2(x, INTERIOR.position.y, 1, INTERIOR.size.y), Color(TRIM, 0.6))
	# Portholes along the top wall: the abyss looks back.
	var porthole := preload("res://assets/sprites/porthole.png")
	for x in range(140, 520, 90):
		var p := Sprite2D.new()
		p.texture = porthole
		p.position = Vector2(x, INTERIOR.position.y - 2)
		add_child(p)

	_add_station("console", "CONSOLE", preload("res://assets/sprites/console.png"),
			Vector2(150, INTERIOR.position.y + 26))
	_add_station("locker", "LOCKER", preload("res://assets/sprites/locker.png"),
			Vector2(360, INTERIOR.position.y + 26))
	_add_station("stash", "STASH", preload("res://assets/sprites/crate.png"),
			Vector2(470, INTERIOR.position.y + 28))
	_add_station("hatch", "DIVE HATCH", preload("res://assets/sprites/hatch.png"),
			Vector2(INTERIOR.end.x - 44, INTERIOR.position.y + INTERIOR.size.y / 2.0))

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
	_crew_label.text = crew
