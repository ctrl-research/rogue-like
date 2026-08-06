extends Control
## Title screen: connect (solo / online room codes / LAN) and board the sub.
## The walkable sub interior (sub.tscn) is the lobby and the station shop —
## this screen only gets the crew connected. On web, opening a shared
## `#room=CODE` URL auto-joins that room.

## Calibration strip: patches at multiples of the trench's unlit ambient. The
## middle one is the target — set brightness so it is only just visible and
## unlit rock will sit right at the edge of perception too. The neighbours give
## the eye something to compare against, which is the whole trick: judging one
## dark patch in isolation is nearly impossible.
const CALIBRATION_STEPS: Array[float] = [0.45, 1.0, 1.7, 2.6]
const CALIBRATION_TARGET := 1  # index of the patch the instruction refers to

var _menu_box: VBoxContainer
var _status: Label
var _summary: Label
var _address: LineEdit
var _code_edit: LineEdit
var _patches: Array[ColorRect] = []
## Customization is a separate panel rather than another section on the title
## screen: at 640x360 the menu column is already full, and appearance is a
## set-once-and-forget thing that shouldn't cost vertical space every launch.
var _customize_root: Control
var _customize_box: VBoxContainer
var _preview: TextureRect
var _name_edit: LineEdit
var _draft := {}  # edited profile, committed to Station on BACK


func _ready() -> void:
	Net.status_changed.connect(func(text: String) -> void: _status.text = text)
	Net.entered_lobby.connect(_on_entered_lobby)
	Net.session_ended.connect(func() -> void: _menu_box.visible = true)
	Station.changed.connect(_refresh_summary)
	Settings.changed.connect(_refresh_patches)
	_build()
	_refresh_summary()
	_refresh_patches()
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

	var customize := Button.new()
	customize.text = "CUSTOMIZE DIVER"
	customize.pressed.connect(_open_customize)
	_menu_box.add_child(customize)

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

	box.add_child(HSeparator.new())
	_build_brightness(box)
	_build_customize()

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 9)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.7, 0.8, 0.86)
	_status.custom_minimum_size = Vector2(280, 24)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


## Brightness, calibrated by eye rather than by number. The trench is meant to
## be near-black outside a lamp, and how near-black that lands depends entirely
## on the display — so the player is shown the actual ambient shade the game
## will use and asked to set it until they can only just make it out.
func _build_brightness(box: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "DISPLAY"
	header.add_theme_font_size_override("font_size", 8)
	header.modulate = Color(0.62, 0.9, 1.0)
	box.add_child(header)

	var hint := Label.new()
	hint.text = "Drag until the middle patch is only just visible."
	hint.add_theme_font_size_override("font_size", 8)
	hint.modulate = Color(0.7, 0.8, 0.86)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 4)
	box.add_child(strip)
	_patches = []
	for i in CALIBRATION_STEPS.size():
		# The target patch is boxed so it's identifiable without needing to be
		# brighter than its neighbours — brightening it would defeat the point.
		var frame := PanelContainer.new()
		# self_modulate, not modulate: modulate would propagate to the patch
		# inside and hide the three unframed ones entirely.
		frame.self_modulate.a = 0.5 if i == CALIBRATION_TARGET else 0.0
		strip.add_child(frame)
		var patch := ColorRect.new()
		patch.custom_minimum_size = Vector2(42, 24)
		frame.add_child(patch)
		_patches.append(patch)

	var slider := HSlider.new()
	slider.min_value = Settings.BRIGHTNESS_MIN
	slider.max_value = Settings.BRIGHTNESS_MAX
	slider.step = 0.05
	slider.value = Settings.brightness
	slider.custom_minimum_size = Vector2(280, 0)
	slider.value_changed.connect(func(v: float) -> void: Settings.set_brightness(v))
	box.add_child(slider)


## The customization screen: a full-rect overlay rather than a section inline in
## the menu column, which is already full at this resolution. Built once and
## toggled, so the draft profile survives opening and closing it.
func _build_customize() -> void:
	_customize_root = CenterContainer.new()
	_customize_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_customize_root.visible = false
	add_child(_customize_root)

	var frame := PanelContainer.new()
	_customize_root.add_child(frame)

	_customize_box = VBoxContainer.new()
	_customize_box.add_theme_constant_override("separation", 6)
	_customize_box.custom_minimum_size = Vector2(300, 0)
	frame.add_child(_customize_box)

	var header := Label.new()
	header.text = "CUSTOMIZE DIVER"
	header.add_theme_font_size_override("font_size", 14)
	header.modulate = Color(0.62, 0.9, 1.0)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_customize_box.add_child(header)

	# The preview runs the same shader the real diver does, so what's shown here
	# is not an approximation of the result — it is the result.
	var preview_row := CenterContainer.new()
	_customize_box.add_child(preview_row)
	_preview = TextureRect.new()
	_preview.texture = load(Appearance.SPRITE_PATH)
	_preview.custom_minimum_size = Vector2(64, 64)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_row.add_child(_preview)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "name (optional)"
	_name_edit.max_length = Appearance.NAME_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.text_changed.connect(func(text: String) -> void:
		_draft["name"] = text
		_refresh_customize())
	_customize_box.add_child(_name_edit)

	var name_note := Label.new()
	name_note.name = "NameNote"
	name_note.add_theme_font_size_override("font_size", 8)
	name_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_note.modulate = Color(0.5, 0.62, 0.72)
	_customize_box.add_child(name_note)

	_add_swatch_section("SUIT", Appearance.SUIT_SWATCHES, "suit")
	_add_swatch_section("HELMET SCREEN", Appearance.SCREEN_SWATCHES, "screen")

	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func() -> void:
		Station.set_profile(_draft)
		_customize_root.visible = false)
	_customize_box.add_child(back)


func _add_swatch_section(title: String, swatches: Array[String], key: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 8)
	label.modulate = Color(0.62, 0.9, 1.0)
	_customize_box.add_child(label)

	var row := HBoxContainer.new()
	row.name = "Row_" + key
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	_customize_box.add_child(row)
	for hex in swatches:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(24, 18)
		swatch.tooltip_text = hex
		# The hex is stored as metadata rather than read back off tooltip_text:
		# tooltips are display, and coupling the lookup to a UI string would
		# break silently the first time the label changes.
		swatch.set_meta("hex", hex)
		swatch.pressed.connect(func() -> void:
			_draft[key] = hex
			_refresh_customize())
		row.add_child(swatch)


func _open_customize() -> void:
	_draft = Station.profile.duplicate()
	_name_edit.text = str(_draft.get("name", ""))
	_refresh_customize()
	_customize_root.visible = true


## Repaint preview, swatch selection and the name echo from the draft. Cheap
## enough at eighteen buttons to just rebuild the styling every change rather
## than track which swatch was previously selected.
func _refresh_customize() -> void:
	var clean := Appearance.sanitize(_draft)
	_preview.material = Appearance.make_material(str(clean.suit), str(clean.screen))

	# Names are stored upper-cased and trimmed. Echo the stored form instead of
	# rewriting the LineEdit mid-typing, which would fight the caret.
	var note := _customize_box.get_node_or_null("NameNote") as Label
	if note != null:
		note.text = "SHOWN AS: %s" % (str(clean.name) if not str(clean.name).is_empty()
				else "your diver class")

	var keys: Array[String] = ["suit", "screen"]
	for key in keys:
		var row := _customize_box.get_node_or_null("Row_" + key) as HBoxContainer
		if row == null:
			continue
		for swatch in row.get_children():
			var button := swatch as Button
			var hex := str(button.get_meta("hex", ""))
			var box := StyleBoxFlat.new()
			box.bg_color = Color.from_string(hex, Color.WHITE)
			if hex.to_lower() == str(clean.get(key, "")).to_lower():
				box.border_width_bottom = 2
				box.border_width_top = 2
				box.border_width_left = 2
				box.border_width_right = 2
				box.border_color = Color.WHITE
			button.add_theme_stylebox_override("normal", box)
			button.add_theme_stylebox_override("hover", box)
			button.add_theme_stylebox_override("pressed", box)
			button.add_theme_stylebox_override("focus", box)


func _refresh_patches() -> void:
	var base := Settings.AMBIENT_SURFACE
	for i in _patches.size():
		# Built channel by channel: `Color * float` scales alpha too, which
		# would leave the darker patches translucent instead of dark.
		var step: float = CALIBRATION_STEPS[i]
		_patches[i].color = Settings.scaled(
				Color(base.r * step, base.g * step, base.b * step))


func _refresh_summary() -> void:
	var who: String = Divers.DIVERS[Station.diver].title
	var chosen := Appearance.sanitize_name(str(Station.profile.get("name", "")))
	if not chosen.is_empty():
		who = "%s the %s" % [chosen, who]
	_summary.text = "DAY %d  —  BANKED SALVAGE: %d  —  DIVING AS %s" % [
		Station.day, Station.bank, who]


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
