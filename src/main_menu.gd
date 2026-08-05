extends Control
## Title screen: connect (solo / online room codes / LAN) and board the sub.
## The walkable sub interior (sub.tscn) is the lobby and the station shop —
## this screen only gets the crew connected. On web, opening a shared
## `#room=CODE` URL auto-joins that room.

var _menu_box: VBoxContainer
var _status: Label
var _summary: Label
var _address: LineEdit
var _code_edit: LineEdit


func _ready() -> void:
	Net.status_changed.connect(func(text: String) -> void: _status.text = text)
	Net.entered_lobby.connect(_on_entered_lobby)
	Net.session_ended.connect(func() -> void: _menu_box.visible = true)
	Station.changed.connect(_refresh_summary)
	_build()
	_refresh_summary()
	if Net.is_online:
		# Returning here with a live session (edge path): the sub is home.
		get_tree().change_scene_to_file(Net.SUB_SCENE)
	else:
		_try_auto_join_from_url()


## Connected (or hosting): board the sub — it's the lobby from here on.
func _on_entered_lobby(_room: String, _is_host: bool) -> void:
	get_tree().change_scene_to_file(Net.SUB_SCENE)


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

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 8)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.modulate = Color(0.95, 0.85, 0.4)
	box.add_child(_summary)

	box.add_child(HSeparator.new())

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 6)
	box.add_child(_menu_box)

	var solo := Button.new()
	solo.text = "BOARD THE SUB — SOLO"
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

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 9)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.7, 0.8, 0.86)
	_status.custom_minimum_size = Vector2(280, 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _refresh_summary() -> void:
	_summary.text = "DAY %d  —  BANKED SALVAGE: %d  —  DIVING AS %s" % [
		Station.day, Station.bank, Divers.DIVERS[Station.diver].title]


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
