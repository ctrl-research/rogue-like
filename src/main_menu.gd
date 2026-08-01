extends Control
## Title screen + minimal lobby. Web builds disable online co-op (ENet is
## desktop-only; browser co-op lands with WebRTC in M2).

var _menu_box: VBoxContainer
var _lobby_box: VBoxContainer
var _status: Label
var _divers: Label
var _start_btn: Button
var _address: LineEdit


func _ready() -> void:
	Net.status_changed.connect(func(text: String) -> void: _status.text = text)
	Net.player_count_changed.connect(_refresh_lobby)
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(260, 0)
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

	var host := Button.new()
	host.text = "HOST CO-OP"
	host.pressed.connect(_on_host)
	_menu_box.add_child(host)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	_menu_box.add_child(join_row)
	_address = LineEdit.new()
	_address.placeholder_text = "host address (127.0.0.1)"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address)
	var join := Button.new()
	join.text = "JOIN"
	join.pressed.connect(_on_join)
	join_row.add_child(join)

	if OS.has_feature("web"):
		host.disabled = true
		join.disabled = true
		_address.editable = false
		var note := Label.new()
		note.text = "co-op is desktop-only for now — browser co-op coming soon"
		note.add_theme_font_size_override("font_size", 8)
		note.modulate = Color(0.5, 0.62, 0.72)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_menu_box.add_child(note)

	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 6)
	_lobby_box.visible = false
	box.add_child(_lobby_box)

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

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 9)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.7, 0.8, 0.86)
	_status.custom_minimum_size = Vector2(260, 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _on_host() -> void:
	if Net.host_game() == OK:
		_show_lobby(true)


func _on_join() -> void:
	if Net.join_game(_address.text) == OK:
		_show_lobby(false)


func _show_lobby(is_host: bool) -> void:
	_menu_box.visible = false
	_lobby_box.visible = true
	_start_btn.visible = is_host
	_refresh_lobby()


func _refresh_lobby() -> void:
	_divers.text = "divers ready: %d / %d" % [Net.player_count(), Net.MAX_PLAYERS]
