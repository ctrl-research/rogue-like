extends Control
## Title screen + lobby. Online co-op (room codes over WebRTC) works on web
## and desktop; LAN (ENet) is desktop-only. On web, opening a shared
## `#room=CODE` URL auto-joins that room.

var _menu_box: VBoxContainer
var _lobby_box: VBoxContainer
var _status: Label
var _divers: Label
var _room_label: Label
var _share_label: Label
var _copy_btn: Button
var _start_btn: Button
var _address: LineEdit
var _code_edit: LineEdit
var _share_url := ""
var _station_box: VBoxContainer
var _bank_label: Label
var _station_rows: VBoxContainer


func _ready() -> void:
	Net.status_changed.connect(func(text: String) -> void: _status.text = text)
	Net.player_count_changed.connect(_refresh_lobby)
	Net.entered_lobby.connect(_on_entered_lobby)
	Net.session_ended.connect(_on_session_ended)
	Station.changed.connect(_refresh_station)
	_build()
	_refresh_station()
	if Net.is_online:
		# Returning from a run with the session still alive: straight back
		# into the crew lobby (shop, regroup, dive again).
		_on_entered_lobby(Net.room_code, multiplayer.is_server())
		_status.text = "Back at the station — spend salvage, then dive again."
	else:
		_try_auto_join_from_url()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(280, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "ABYSSAL SALVAGE"
	title.add_theme_font_size_override("font_size", 26)
	title.modulate = Color(0.62, 0.9, 1.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "deep-sea horde salvage — 1 to 4 divers"
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.5, 0.62, 0.72)
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 6)
	box.add_child(_menu_box)

	var solo := Button.new()
	solo.text = "DIVE SOLO"
	solo.pressed.connect(func() -> void: Net.start_solo())
	_menu_box.add_child(solo)

	var webrtc_ok := Net.webrtc_available()

	var host_online := Button.new()
	host_online.text = "HOST ONLINE"
	host_online.disabled = not webrtc_ok
	host_online.pressed.connect(func() -> void: Net.host_online())
	_menu_box.add_child(host_online)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	_menu_box.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "room code"
	_code_edit.max_length = 5
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.editable = webrtc_ok
	join_row.add_child(_code_edit)
	var join_online := Button.new()
	join_online.text = "JOIN ONLINE"
	join_online.disabled = not webrtc_ok
	join_online.pressed.connect(func() -> void: Net.join_online(_code_edit.text))
	join_row.add_child(join_online)

	if not webrtc_ok:
		var note := Label.new()
		note.text = "online play needs the WebRTC extension\n(run scripts/fetch_webrtc.sh, then restart)"
		note.add_theme_font_size_override("font_size", 8)
		note.modulate = Color(0.5, 0.62, 0.72)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_menu_box.add_child(note)

	if not OS.has_feature("web"):
		_menu_box.add_child(HSeparator.new())
		var host_lan := Button.new()
		host_lan.text = "HOST LAN"
		host_lan.pressed.connect(func() -> void: Net.host_lan())
		_menu_box.add_child(host_lan)
		var lan_row := HBoxContainer.new()
		lan_row.add_theme_constant_override("separation", 6)
		_menu_box.add_child(lan_row)
		_address = LineEdit.new()
		_address.placeholder_text = "host address (127.0.0.1)"
		_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lan_row.add_child(_address)
		var join_lan := Button.new()
		join_lan.text = "JOIN LAN"
		join_lan.pressed.connect(func() -> void: Net.join_lan(_address.text))
		lan_row.add_child(join_lan)

	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 6)
	_lobby_box.visible = false
	box.add_child(_lobby_box)

	_room_label = Label.new()
	_room_label.add_theme_font_size_override("font_size", 18)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.modulate = Color(0.95, 0.85, 0.4)
	_lobby_box.add_child(_room_label)

	_share_label = Label.new()
	_share_label.add_theme_font_size_override("font_size", 8)
	_share_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_share_label.modulate = Color(0.5, 0.62, 0.72)
	_lobby_box.add_child(_share_label)

	_copy_btn = Button.new()
	_copy_btn.text = "COPY INVITE LINK"
	_copy_btn.visible = false
	_copy_btn.pressed.connect(_copy_share_url)
	_lobby_box.add_child(_copy_btn)

	_divers = Label.new()
	_divers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_box.add_child(_divers)

	_start_btn = Button.new()
	_start_btn.text = "START DIVE"
	_start_btn.pressed.connect(func() -> void: Net.start_dive())
	_lobby_box.add_child(_start_btn)

	var leave := Button.new()
	leave.text = "LEAVE"
	leave.pressed.connect(func() -> void: Net.leave())
	_lobby_box.add_child(leave)

	# Station shopping is available on the title screen AND in the crew
	# lobby between dives — that's when the banked salvage burns a hole.
	box.add_child(HSeparator.new())
	var station_toggle := Button.new()
	station_toggle.text = "STATION UPGRADES"
	station_toggle.toggle_mode = true
	station_toggle.toggled.connect(func(on: bool) -> void: _station_box.visible = on)
	box.add_child(station_toggle)

	_station_box = VBoxContainer.new()
	_station_box.add_theme_constant_override("separation", 4)
	_station_box.visible = false
	box.add_child(_station_box)
	_bank_label = Label.new()
	_bank_label.add_theme_font_size_override("font_size", 10)
	_bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bank_label.modulate = Color(0.95, 0.85, 0.4)
	_station_box.add_child(_bank_label)
	_station_rows = VBoxContainer.new()
	_station_rows.add_theme_constant_override("separation", 2)
	_station_box.add_child(_station_rows)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 9)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.7, 0.8, 0.86)
	_status.custom_minimum_size = Vector2(280, 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _refresh_station() -> void:
	if _station_rows == null:
		return
	_bank_label.text = "BANKED SALVAGE: %d  —  DIVING AS %s" % [
		Station.bank, Divers.DIVERS[Station.diver].title]
	for child in _station_rows.get_children():
		child.queue_free()

	var divers_header := Label.new()
	divers_header.text = "DIVERS"
	divers_header.add_theme_font_size_override("font_size", 8)
	divers_header.modulate = Color(0.62, 0.9, 1.0)
	_station_rows.add_child(divers_header)
	for id in Divers.DIVERS:
		var spec: Dictionary = Divers.DIVERS[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := Label.new()
		info.text = "%s — %s" % [spec.title, spec.desc]
		info.add_theme_font_size_override("font_size", 8)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 8)
		if Station.diver == id:
			btn.text = "SELECTED"
			btn.disabled = true
		elif Station.diver_unlocked(id):
			btn.text = "SELECT"
			btn.pressed.connect(func() -> void: Station.select_diver(id))
		else:
			btn.text = "BUY %d" % int(spec.cost)
			btn.disabled = not Station.can_buy_diver(id)
			btn.pressed.connect(func() -> void: Station.buy_diver(id))
		row.add_child(btn)
		_station_rows.add_child(row)

	var upgrades_header := Label.new()
	upgrades_header.text = "UPGRADES"
	upgrades_header.add_theme_font_size_override("font_size", 8)
	upgrades_header.modulate = Color(0.62, 0.9, 1.0)
	_station_rows.add_child(upgrades_header)
	for id in Station.UPGRADES:
		var spec: Dictionary = Station.UPGRADES[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := Label.new()
		info.text = "%s Lv%d/%d — %s" % [spec.title, Station.level(id), spec.max, spec.desc]
		info.add_theme_font_size_override("font_size", 8)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var buy := Button.new()
		buy.add_theme_font_size_override("font_size", 8)
		if Station.level(id) >= int(spec.max):
			buy.text = "MAX"
			buy.disabled = true
		else:
			buy.text = "BUY %d" % Station.cost(id)
			buy.disabled = not Station.can_buy(id)
			buy.pressed.connect(func() -> void: Station.buy(id))
		row.add_child(buy)
		_station_rows.add_child(row)


func _on_entered_lobby(room: String, is_host: bool) -> void:
	_menu_box.visible = false
	_lobby_box.visible = true
	_start_btn.visible = is_host
	if room.is_empty():
		_room_label.text = "LAN LOBBY"
		_share_label.text = "friends join with your IP, port %d" % Net.DEFAULT_PORT
	else:
		_room_label.text = "ROOM  %s" % room
		_share_url = _build_share_url(room)
		if _share_url.is_empty():
			_share_label.text = "friends press JOIN ONLINE and enter the code"
		else:
			_share_label.text = _share_url
			_copy_btn.visible = true
	_refresh_lobby()


func _refresh_lobby() -> void:
	_divers.text = "divers ready: %d / %d" % [Net.player_count(), Net.MAX_PLAYERS]


func _on_session_ended() -> void:
	_lobby_box.visible = false
	_menu_box.visible = true
	_copy_btn.visible = false


func _build_share_url(room: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var base: Variant = JavaScriptBridge.eval("window.location.origin + window.location.pathname", true)
	if base is String and not (base as String).is_empty():
		return "%s#room=%s" % [base, room]
	return ""


func _copy_share_url() -> void:
	if _share_url.is_empty():
		return
	DisplayServer.clipboard_set(_share_url)
	_copy_btn.text = "LINK COPIED!"


## On web, a shared invite URL like .../#room=ABCDE joins that room directly.
func _try_auto_join_from_url() -> void:
	if not OS.has_feature("web"):
		return
	var hash_frag: Variant = JavaScriptBridge.eval("window.location.hash", true)
	if hash_frag is String and (hash_frag as String).begins_with("#room="):
		var code := (hash_frag as String).trim_prefix("#room=").to_upper()
		if code.length() == 5:
			_code_edit.text = code
			Net.join_online(code)
