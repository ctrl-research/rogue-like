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
var _depth_label: Label
var _choice_box: VBoxContainer
var _choice_countdown: Label
var _extract_btn: Button
var _offer_box: VBoxContainer
var _offer_row: HBoxContainer
var _downed_dim: ColorRect
var _downed_label: Label
var _hurt_dim: ColorRect
var _prev_hp := -1.0
var _warn_cd := 0.0
var _over_root: Control
var _over_title: Label
var _over_sub: Label
var _over_station_btn: Button
var _over_lobby_btn: Button
var _over_disband_btn: Button
var _over_leave_btn: Button
var _over_wait: Label


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
		# Hurt vignette pulse on any local hp drop.
		if _prev_hp >= 0.0 and _local.hp < _prev_hp and not _game.game_over:
			_hurt_dim.modulate.a = 1.0
			var tween := _hurt_dim.create_tween()
			tween.tween_property(_hurt_dim, "modulate:a", 0.0, 0.35)
		_prev_hp = _local.hp

	var local_downed: bool = _local != null and _local.downed and not _game.game_over
	_downed_dim.visible = local_downed
	_downed_label.visible = local_downed

	var o2: float = _game.oxygen
	_o2_label.text = "O2 %d:%02d" % [int(o2) / 60, int(o2) % 60]
	_o2_label.modulate = Color(1.0, 0.35, 0.3) if o2 < 30.0 else Color(0.62, 0.9, 1.0)
	if o2 < 30.0 and not _game.game_over:
		_warn_cd -= get_process_delta_time()
		if _warn_cd <= 0.0:
			_warn_cd = 5.0
			Sfx.play("warning", -8.0, 0.0)
	_time_label.text = "T %d:%02d" % [int(_game.elapsed) / 60, int(_game.elapsed) % 60]
	_salvage_label.text = "SALVAGE %d/%d" % [GameRules.CRATE_COUNT - _game.crates_left, GameRules.CRATE_COUNT]
	_depth_label.text = "DEPTH %d   HAUL %d" % [_game.depth, _game.salvage_earned]
	_xp_bar.max_value = _game.xp_needed
	_xp_bar.value = _game.team_xp
	_level_label.text = "LV %d" % _game.team_level

	var deciding: bool = _game.awaiting_choice and not _game.game_over
	_choice_box.visible = deciding and multiplayer.is_server()
	if _choice_box.visible:
		_extract_btn.text = "EXTRACT — BANK %d" % _game.salvage_earned
		_choice_countdown.text = "auto-extract in %ds" % ceili(maxf(0.0, _game.decision_left))

	if deciding and not multiplayer.is_server():
		_extract_label.visible = true
		_extract_label.text = "LEAD DIVER IS DECIDING... %ds" % ceili(maxf(0.0, _game.decision_left))
	elif _game.extraction_progress > 0.0 and not _game.game_over and not deciding:
		_extract_label.visible = true
		_extract_label.text = "EXTRACTING... %.1fs" % maxf(0.0, GameRules.EXTRACTION_TIME - _game.extraction_progress)
	else:
		_extract_label.visible = false

	if _game.game_over and not _over_root.visible:
		Sfx.play("extract" if _game.victory else "defeat", -4.0, 0.0)
		_over_root.visible = true
		_over_title.text = "DIVE COMPLETE" if _game.victory else "LOST TO THE DEEP"
		_over_title.modulate = Color(0.55, 1.0, 0.75) if _game.victory else Color(1.0, 0.4, 0.35)
		if _game.victory:
			_over_sub.text = "Banked %d salvage from depth %d." % [_game.banked_salvage, _game.depth]
		else:
			_over_sub.text = "The trench keeps what it takes — %d salvage lost at depth %d." % [_game.salvage_earned, _game.depth]
		# Role-aware prompts: the host owns the room's fate; the crew stays
		# together unless a member chooses to walk.
		var online := Net.is_online
		_over_station_btn.visible = not online
		_over_lobby_btn.visible = online and multiplayer.is_server()
		_over_disband_btn.visible = online and multiplayer.is_server()
		_over_wait.visible = online and not multiplayer.is_server()
		_over_leave_btn.visible = online and not multiplayer.is_server()


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
	Sfx.play("levelup", -6.0, 0.0)
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
	if id.begins_with("evolve_"):
		return "EVOLVE!"
	var lvl: int = _local.weapons.get(id, 0) if Weapons.is_weapon(id) else _local.passives.get(id, 0)
	if lvl == 0:
		return "NEW"
	return "Lv %d > %d" % [lvl, lvl + 1]


func _gear_summary() -> String:
	var parts := PackedStringArray()
	for id in _local.weapons:
		var lvl: int = _local.weapons[id]
		var name: String = Weapons.display_title(id, lvl).split(" ")[0]
		parts.append("%s %s" % [name, "EVO" if lvl >= Weapons.EVOLVED_LEVEL else str(lvl)])
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

	_depth_label = _label("DEPTH 1   HAUL 0", 8)
	_depth_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_depth_label.position = Vector2(-104, 22)
	_depth_label.modulate = Color(0.62, 0.9, 1.0)
	root.add_child(_depth_label)

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

	_hurt_dim = ColorRect.new()
	_hurt_dim.color = Color(0.6, 0.06, 0.06, 0.28)
	_hurt_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_dim.modulate.a = 0.0
	root.add_child(_hurt_dim)
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

	_choice_box = VBoxContainer.new()
	_choice_box.set_anchors_preset(Control.PRESET_CENTER)
	_choice_box.position = Vector2(-90, -30)
	_choice_box.custom_minimum_size = Vector2(180, 0)
	_choice_box.add_theme_constant_override("separation", 6)
	_choice_box.visible = false
	add_child(_choice_box)
	var choice_title := _label("BELL SECURED — YOUR CALL", 10)
	choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choice_title.modulate = Color(0.95, 0.85, 0.4)
	_choice_box.add_child(choice_title)
	_extract_btn = Button.new()
	_extract_btn.text = "EXTRACT"
	_extract_btn.add_theme_font_size_override("font_size", 9)
	_extract_btn.pressed.connect(func() -> void: _game.choose_extract())
	_choice_box.add_child(_extract_btn)
	var descend_btn := Button.new()
	descend_btn.text = "DESCEND — DEEPER, RICHER (+O2)"
	descend_btn.add_theme_font_size_override("font_size", 9)
	descend_btn.pressed.connect(func() -> void: _game.choose_descend())
	_choice_box.add_child(descend_btn)
	_choice_countdown = _label("", 8)
	_choice_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_countdown.modulate = Color(0.7, 0.8, 0.86)
	_choice_box.add_child(_choice_countdown)

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
	_over_station_btn = Button.new()
	_over_station_btn.text = "RETURN TO STATION"
	_over_station_btn.pressed.connect(func() -> void: Net.leave())
	box.add_child(_over_station_btn)
	_over_lobby_btn = Button.new()
	_over_lobby_btn.text = "BACK TO LOBBY — DIVE AGAIN"
	_over_lobby_btn.pressed.connect(func() -> void: Net.return_to_lobby())
	box.add_child(_over_lobby_btn)
	_over_disband_btn = Button.new()
	_over_disband_btn.text = "DISBAND CREW"
	_over_disband_btn.pressed.connect(func() -> void: Net.close_room())
	box.add_child(_over_disband_btn)
	_over_wait = _label("the lead diver is deciding the crew's next move...", 8)
	_over_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_wait.modulate = Color(0.7, 0.8, 0.86)
	box.add_child(_over_wait)
	_over_leave_btn = Button.new()
	_over_leave_btn.text = "LEAVE CREW"
	_over_leave_btn.pressed.connect(func() -> void: Net.leave())
	box.add_child(_over_leave_btn)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l
