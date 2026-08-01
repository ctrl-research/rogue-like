extends CanvasLayer
## In-run HUD. Reads mirrored state off the Game node every frame; all
## controls are built in code so the scene file stays trivial.

var _game  # the Game node; untyped for dynamic access to its mirrored state
var _local: Player  # this peer's diver, once spawned
var _current_offer: Array = []
var _hp_bar: ProgressBar
var _o2_label: Label
var _time_label: Label
var _salvage_label: Label
var _xp_bar: ProgressBar
var _level_label: Label
var _toast: Label
var _extract_label: Label
var _gear_label: Label
var _offer_box: VBoxContainer
var _offer_row: HBoxContainer
var _downed_dim: ColorRect
var _downed_label: Label
var _over_root: Control
var _over_title: Label
var _over_sub: Label


func _ready() -> void:
	_game = get_parent()
	_build()


func _process(_delta: float) -> void:
	if _local == null or not is_instance_valid(_local):
		_local = _local_player()
		if _local != null:
			_local.upgrade_offered.connect(_on_offer)

	if _local != null:
		_hp_bar.max_value = _local.max_hp
		_hp_bar.value = _local.hp
		_gear_label.text = _gear_summary()

	var local_downed: bool = _local != null and _local.downed and not _game.game_over
	_downed_dim.visible = local_downed
	_downed_label.visible = local_downed

	var o2: float = _game.oxygen
	_o2_label.text = "O2 %d:%02d" % [int(o2) / 60, int(o2) % 60]
	_o2_label.modulate = Color(1.0, 0.35, 0.3) if o2 < 30.0 else Color(0.62, 0.9, 1.0)
	_time_label.text = "T %d:%02d" % [int(_game.elapsed) / 60, int(_game.elapsed) % 60]
	_salvage_label.text = "SALVAGE %d/%d" % [GameRules.CRATE_COUNT - _game.crates_left, GameRules.CRATE_COUNT]
	_xp_bar.max_value = _game.xp_needed
	_xp_bar.value = _game.team_xp
	_level_label.text = "LV %d" % _game.team_level

	if _game.extraction_progress > 0.0 and not _game.game_over:
		_extract_label.visible = true
		_extract_label.text = "EXTRACTING... %.1fs" % maxf(0.0, GameRules.EXTRACTION_TIME - _game.extraction_progress)
	else:
		_extract_label.visible = false

	if _game.game_over and not _over_root.visible:
		_over_root.visible = true
		_over_title.text = "DIVE COMPLETE" if _game.victory else "LOST TO THE DEEP"
		_over_title.modulate = Color(0.55, 1.0, 0.75) if _game.victory else Color(1.0, 0.4, 0.35)
		_over_sub.text = "The crew extracted with the salvage." if _game.victory else "The trench keeps what it takes."


func _unhandled_input(event: InputEvent) -> void:
	if _current_offer.is_empty() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var idx := -1
	match key.physical_keycode:
		KEY_1:
			idx = 0
		KEY_2:
			idx = 1
		KEY_3:
			idx = 2
	if idx >= 0 and idx < _current_offer.size():
		_pick(_current_offer[idx])


func _on_offer(options: Array) -> void:
	_current_offer = options
	for child in _offer_row.get_children():
		child.queue_free()
	for i in options.size():
		var id: String = options[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(126, 58)
		btn.add_theme_font_size_override("font_size", 8)
		btn.text = "[%d] %s\n%s\n%s" % [i + 1, Weapons.title(id), _rank_text(id), Weapons.desc(id)]
		btn.pressed.connect(func() -> void: _pick(id))
		_offer_row.add_child(btn)
	_offer_box.visible = true


func _pick(id: String) -> void:
	_offer_box.visible = false
	_current_offer = []
	if _local != null:
		_local.request_pick(id)


func _rank_text(id: String) -> String:
	if _local == null:
		return ""
	var lvl: int = _local.weapons.get(id, 0) if Weapons.is_weapon(id) else _local.passives.get(id, 0)
	if lvl == 0:
		return "NEW"
	return "Lv %d > %d" % [lvl, lvl + 1]


func _gear_summary() -> String:
	var parts := PackedStringArray()
	for id in _local.weapons:
		parts.append("%s %d" % [Weapons.title(id).split(" ")[0], _local.weapons[id]])
	for id in _local.passives:
		parts.append("%s %d" % [Weapons.title(id).split(" ")[0].to_lower(), _local.passives[id]])
	return "  ".join(parts)


func show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


func _local_player() -> Player:
	for p in _game.players.get_children():
		if p is Player and p.peer_id == multiplayer.get_unique_id():
			return p
	return null


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var hull := _label("HULL", 8)
	hull.position = Vector2(8, 4)
	root.add_child(hull)
	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(8, 16)
	_hp_bar.size = Vector2(110, 10)
	_hp_bar.show_percentage = false
	_hp_bar.modulate = Color(1.0, 0.55, 0.45)
	root.add_child(_hp_bar)

	_o2_label = _label("O2 5:00", 14)
	_o2_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_o2_label.position = Vector2(-36, 4)
	root.add_child(_o2_label)
	_time_label = _label("T 0:00", 8)
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.position = Vector2(-16, 26)
	root.add_child(_time_label)

	_salvage_label = _label("SALVAGE 0/6", 10)
	_salvage_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_salvage_label.position = Vector2(-104, 8)
	_salvage_label.modulate = Color(0.95, 0.85, 0.4)
	root.add_child(_salvage_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_xp_bar.offset_left = 8
	_xp_bar.offset_right = -48
	_xp_bar.offset_top = -16
	_xp_bar.offset_bottom = -8
	_xp_bar.show_percentage = false
	_xp_bar.modulate = Color(0.3, 0.9, 0.75)
	root.add_child(_xp_bar)
	_level_label = _label("LV 1", 10)
	_level_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_level_label.position = Vector2(-40, -20)
	root.add_child(_level_label)

	_toast = _label("", 10)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-220, 44)
	_toast.size = Vector2(440, 20)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	_extract_label = _label("EXTRACTING...", 14)
	_extract_label.set_anchors_preset(Control.PRESET_CENTER)
	_extract_label.position = Vector2(-70, 40)
	_extract_label.modulate = Color(0.55, 1.0, 0.75)
	_extract_label.visible = false
	root.add_child(_extract_label)

	_gear_label = _label("", 8)
	_gear_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_gear_label.position = Vector2(8, -28)
	_gear_label.modulate = Color(0.7, 0.82, 0.88)
	root.add_child(_gear_label)

	_downed_dim = ColorRect.new()
	_downed_dim.color = Color(0.45, 0.05, 0.05, 0.22)
	_downed_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_downed_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_dim.visible = false
	root.add_child(_downed_dim)
	_downed_label = _label("DOWNED — a teammate can revive you", 12)
	_downed_label.set_anchors_preset(Control.PRESET_CENTER)
	_downed_label.position = Vector2(-130, -40)
	_downed_label.modulate = Color(1.0, 0.5, 0.45)
	_downed_label.visible = false
	root.add_child(_downed_label)

	_offer_box = VBoxContainer.new()
	_offer_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_offer_box.offset_top = -104
	_offer_box.offset_bottom = -26
	_offer_box.add_theme_constant_override("separation", 4)
	_offer_box.visible = false
	add_child(_offer_box)
	var offer_title := _label("CHOOSE UPGRADE", 9)
	offer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	offer_title.modulate = Color(0.95, 0.85, 0.4)
	_offer_box.add_child(offer_title)
	_offer_row = HBoxContainer.new()
	_offer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_offer_row.add_theme_constant_override("separation", 8)
	_offer_box.add_child(_offer_row)

	_over_root = Control.new()
	_over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_root.visible = false
	add_child(_over_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.06, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	_over_title = _label("", 24)
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_title)
	_over_sub = _label("", 10)
	_over_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_sub)
	var btn := Button.new()
	btn.text = "RETURN TO STATION"
	btn.pressed.connect(func() -> void: Net.leave())
	box.add_child(btn)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l
