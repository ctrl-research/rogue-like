class_name StationUi
## Shared row builders for the station's shop UI, used by the sub interior's
## consoles (and anywhere else the crew spends banked salvage). Each builder
## appends rows to `parent`; callers rebuild on Station.changed.

## Colour picker popup scale. The internal resolution is 640x360 and a stock
## ColorPicker is built for a desktop inspector, so it is scaled down rather than
## merely trimmed — a minimum size cannot make a Control smaller than it is.
##
## This is the one number to turn if the popup is still the wrong size: 0.4 puts
## it at roughly a quarter of the screen height, which is what it is for. Below
## about 0.35 the hex field stops being readable, and the gradient becomes too
## coarse to land on a specific colour.
const PICKER_SCALE := 0.4
const PICKER_PAD := 6  # popup panel's own border, in post-scale pixels
const PICKER_MIN_W := 96
const PICKER_MIN_H := 72
const POPUP_GAP := 2  # pixels between the popup and the button it belongs to


## Appearance editor: preview, name, and a colour picker per recolourable region.
## Built here rather than in the title screen so the sub's diver locker can host
## the same editor — a player who skipped it at boot changes it at the locker,
## which is where their suit hangs anyway.
##
## Writes are deliberately not on every change. A ColorPicker emits continuously
## while the cursor is dragged, and Station.set_profile writes the save file, so
## committing per change would mean file I/O every frame of a drag. The preview
## follows the drag; the commit waits for the popup to close.
static func build_appearance(parent: VBoxContainer, preview_px: int) -> void:
	# A Dictionary, not separate locals: GDScript lambdas capture locals by value,
	# so the callbacks below need shared mutable state they all point at.
	var draft := Station.profile.duplicate()

	var preview := TextureRect.new()
	preview.texture = load(Appearance.SPRITE_PATH)
	preview.custom_minimum_size = Vector2(preview_px, preview_px)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var preview_row := CenterContainer.new()
	preview_row.add_child(preview)
	parent.add_child(preview_row)

	var shown := Label.new()
	shown.add_theme_font_size_override("font_size", 8)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shown.modulate = Color(0.5, 0.62, 0.72)
	parent.add_child(shown)

	# The preview runs the real shader with the real uniforms, so this is not an
	# approximation of the result — it is the result.
	var repaint := func() -> void:
		var clean := Appearance.sanitize(draft)
		preview.material = Appearance.make_material(str(clean.suit), str(clean.screen))
		shown.text = "SHOWN AS: %s" % (str(clean.name) if not str(clean.name).is_empty()
				else "your diver class")

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	parent.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "NAME"
	name_label.add_theme_font_size_override("font_size", 8)
	name_row.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "optional"
	name_edit.max_length = Appearance.NAME_MAX
	name_edit.text = str(draft.get("name", ""))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 8)
	# Echo the stored (trimmed, upper-cased) form in the label rather than
	# rewriting the field mid-typing, which would fight the caret.
	name_edit.text_changed.connect(func(_t: String) -> void:
		draft["name"] = name_edit.text
		repaint.call())
	name_edit.text_submitted.connect(func(_t: String) -> void: Station.set_profile(draft))
	name_edit.focus_exited.connect(func() -> void: Station.set_profile(draft))
	name_row.add_child(name_edit)

	_add_color_row(parent, draft, repaint, "SUIT", "suit", Appearance.SUIT_PRESETS)
	_add_color_row(parent, draft, repaint, "SCREEN", "screen", Appearance.SCREEN_PRESETS)
	repaint.call()


static func _add_color_row(parent: VBoxContainer, draft: Dictionary, repaint: Callable,
		title: String, key: String, presets: Array[String]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 8)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var button := ColorPickerButton.new()
	button.custom_minimum_size = Vector2(56, 16)
	button.edit_alpha = false  # a translucent diver is not a look, it's a bug
	button.color = Color.from_string(str(draft.get(key, "#ffffff")), Color.WHITE)
	row.add_child(button)

	# Configured eagerly rather than on first press. get_picker() instantiates the
	# picker on demand, and a popup takes its size from whatever the picker
	# already is — so trimming it inside the `pressed` handler would leave the
	# FIRST open full-size and only shrink it afterwards.
	var picker := button.get_picker()
	if picker != null:
		# A stock ColorPicker is built for a desktop inspector: an eyedropper
		# strip, colour-mode buttons and a full slider stack. Hiding those helps,
		# but it is not enough on its own — see the scaling below.
		picker.picker_shape = ColorPicker.SHAPE_HSV_RECTANGLE
		picker.sampler_visible = false
		picker.color_modes_visible = false
		picker.sliders_visible = false
		picker.hex_visible = true  # keeps every HTML colour reachable by typing
		picker.can_add_swatches = false  # the presets below are the starting set
		picker.presets_visible = true
		for hex in presets:
			picker.add_preset(Color.from_string(hex, Color.WHITE))

	# Shrink the popup by SCALING it, which is the only thing that works.
	#
	# The previous attempt set custom_minimum_size on the picker and did nothing,
	# because that is a MINIMUM: a Control cannot be pushed below its natural size
	# that way. The natural size here is genuinely tall — an HSV square plus the
	# default theme's 16px font — so on a 360px-tall screen it filled the height
	# and covered the diver preview it exists to preview.
	#
	# Sized in about_to_popup rather than now: the picker's combined minimum size
	# is only meaningful once its children have laid out, and doing it per-open
	# means a theme change can't leave a stale hardcoded size behind.
	var popup := button.get_popup()
	if popup != null:
		popup.about_to_popup.connect(func() -> void:
			popup.content_scale_factor = PICKER_SCALE
			var want := Vector2.ZERO
			if picker != null:
				want = picker.get_combined_minimum_size() * PICKER_SCALE
			popup.size = Vector2i(
					maxi(int(want.x) + PICKER_PAD, PICKER_MIN_W),
					maxi(int(want.y) + PICKER_PAD, PICKER_MIN_H))
			place_popup_over(button, popup))

	button.color_changed.connect(func(c: Color) -> void:
		draft[key] = "#" + c.to_html(false)
		repaint.call())
	# Commit on close, not on change — see build_appearance.
	button.popup_closed.connect(func() -> void: Station.set_profile(draft))


## Centre the popup horizontally on its button and sit it just above, clamped into
## the viewport.
##
## Necessary because ColorPickerButton chooses the popup's position BEFORE
## about_to_popup fires, using whatever size the popup had at that moment — the
## unscaled one. That is how a popup we shrink in about_to_popup ended up parked at
## the top of the screen: the position was picked for a full-height window, which
## only fitted up there, and then it got smaller without moving.
static func place_popup_over(button: Control, popup: Window) -> void:
	# Native (non-embedded) windows position in screen coordinates and are placed
	# by the OS, so the arithmetic below would be in the wrong space. Godot's own
	# placement is fine there; this only misbehaves for embedded popups.
	if not popup.is_embedded():
		return
	var view := button.get_viewport_rect().size
	var anchor := button.get_global_rect()
	var pos := Vector2(
			anchor.get_center().x - popup.size.x / 2.0,
			anchor.position.y - popup.size.y - POPUP_GAP)
	if pos.y < 0.0:
		pos.y = anchor.end.y + POPUP_GAP  # no room above, so drop below instead
	pos.x = clampf(pos.x, 0.0, maxf(view.x - popup.size.x, 0.0))
	pos.y = clampf(pos.y, 0.0, maxf(view.y - popup.size.y, 0.0))
	popup.position = Vector2i(pos)


static func build_divers(parent: VBoxContainer) -> void:
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
		parent.add_child(row)


static func build_upgrades(parent: VBoxContainer) -> void:
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
		parent.add_child(row)


static func build_winch(parent: VBoxContainer) -> void:
	var winch_row := HBoxContainer.new()
	winch_row.add_theme_constant_override("separation", 6)
	for d in Station.start_depths():
		var depth_btn := Button.new()
		depth_btn.add_theme_font_size_override("font_size", 8)
		depth_btn.text = "DEPTH %d" % d
		if Station.dive_depth == d:
			depth_btn.text += " *"
			depth_btn.disabled = true
		depth_btn.pressed.connect(func() -> void: Station.select_dive_depth(d))
		winch_row.add_child(depth_btn)
	var next_tier := Station.winch + 1
	var next_lair := next_tier * GameRules.BOSS_DEPTH_INTERVAL
	var refit := Button.new()
	refit.add_theme_font_size_override("font_size", 8)
	if Station.cleared_lair >= next_lair:
		refit.text = "REFIT: START AT %d — BUY %d" % [next_lair + 1, Station.winch_cost(next_tier)]
		refit.disabled = not Station.can_buy_winch()
		refit.pressed.connect(func() -> void: Station.buy_winch())
	else:
		refit.text = "NEXT REFIT: CLEAR THE DEPTH-%d LAIR" % next_lair
		refit.disabled = true
	winch_row.add_child(refit)
	parent.add_child(winch_row)


static func header(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.modulate = Color(0.62, 0.9, 1.0)
	parent.add_child(label)
