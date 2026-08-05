extends CanvasLayer
## In-run HUD. Reads mirrored state off the Game node every frame; all
## controls are built in code so the scene file stays trivial.

const ARROW_TEXTURE := preload("res://assets/sprites/arrow.png")

# Off-screen markers: arrows pinned inside the screen edge.
const MARKER_MARGIN := 20.0  # inset from the viewport edge, in pixels
const MARKER_POOL := 8  # reused nodes; caps how many arrows can show at once
const MAX_OBJECTIVE_MARKERS := 3  # six crates of arrows would be noise
const OBJECTIVE_TINT := Color(0.95, 0.85, 0.4)
const THREAT_TINT := Color(1.0, 0.45, 0.4)
const BELL_TINT := Color(0.55, 1.0, 0.75)
const DOWNED_TINT := Color(1.0, 0.35, 0.55)

var _game  # the Game node; untyped for dynamic access to its mirrored state
var _local: Player  # this peer's diver, once spawned
var _current_offer: Array = []
var _hp_bar: ProgressBar
var _o2_label: Label
var _time_label: Label
var _objective_label: Label
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
var _boss_bar: ProgressBar
var _boss_label: Label
var _markers: Array[Node2D] = []


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
	_objective_label.text = _objective_text()
	_depth_label.text = "DEPTH %d   HAUL %d" % [_game.depth, _game.salvage_earned]
	_xp_bar.max_value = _game.xp_needed
	_xp_bar.value = _game.team_xp
	_level_label.text = "LV %d" % _game.team_level

	var boss := _find_boss() if _game.quest_kind == "boss" else null
	_boss_bar.visible = boss != null and not _game.game_over
	_boss_label.visible = _boss_bar.visible
	if boss != null:
		_boss_bar.max_value = boss.max_hp
		_boss_bar.value = boss.hp

	_update_markers()

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


## The quest line in the top-right corner, per this depth's objective. Where
## the thing actually IS comes from the edge arrows (see _update_markers).
func _objective_text() -> String:
	if _game.quest_done:
		return "GET TO THE BELL"
	match _game.quest_kind:
		"swarm":
			var left := int(ceilf(_game.quest_progress))
			return "SURVIVE %d:%02d" % [left / 60, left % 60]
		"hunt":
			return "HUNT THE BEAST"
		"repair":
			return "REPAIR %d%%" % int(100.0 * _game.quest_progress / GameRules.REPAIR_TIME)
		"escort":
			if _local != null and _local.towing:
				return "TOW TO THE BELL ZONE"
			return "GRAB THE PAYLOAD"
		"boss":
			return "SLAY THE WARDEN"
		_:
			return "SALVAGE %d/%d" % [GameRules.CRATE_COUNT - _game.crates_left, GameRules.CRATE_COUNT]


# --- Off-screen markers -------------------------------------------------------


## Arrows pinned to the screen edge, pointing at what matters off-camera: the
## objective, and any crewmate bleeding out. A target that's already on screen
## needs no arrow — you can see it.
func _update_markers() -> void:
	var targets := [] if _game.game_over or _local == null else _marker_targets()
	var to_screen := get_viewport().get_canvas_transform()
	var center := get_viewport_rect().size / 2.0
	var half := center - Vector2.ONE * MARKER_MARGIN
	for i in _markers.size():
		var marker := _markers[i]
		if i >= targets.size():
			marker.visible = false
			continue
		var target: Dictionary = targets[i]
		var pos: Vector2 = target.pos
		var offset := to_screen * pos - center
		if absf(offset.x) < half.x and absf(offset.y) < half.y:
			marker.visible = false  # on camera already
			continue
		# Slide out along the bearing until we meet the screen edge.
		var reach := INF
		if absf(offset.x) > 0.001:
			reach = minf(reach, half.x / absf(offset.x))
		if absf(offset.y) > 0.001:
			reach = minf(reach, half.y / absf(offset.y))
		marker.visible = true
		marker.position = center + offset * reach
		marker.modulate = target.color
		(marker.get_node("Arrow") as Sprite2D).rotation = offset.angle()
		var range_m := int(_local.global_position.distance_to(pos) / Terrain.CELL)
		(marker.get_node("Range") as Label).text = "%dm" % range_m


## Nearest objectives first, with downed crew ahead of everything — the
## bleed-out clock is shorter than any quest.
func _marker_targets() -> Array:
	var out: Array = []
	if _game.quest_done:
		for bell in get_tree().get_nodes_in_group("bell"):
			out.append({"pos": (bell as Node2D).global_position, "color": BELL_TINT})
	else:
		match _game.quest_kind:
			"crates":
				for crate in get_tree().get_nodes_in_group("crates"):
					if not crate.is_queued_for_deletion():
						out.append({"pos": (crate as Node2D).global_position, "color": OBJECTIVE_TINT})
			"hunt":
				_append_target(out, _find_beast(), THREAT_TINT)
			"boss":
				_append_target(out, _find_boss(), THREAT_TINT)
			"repair":
				_append_target(out, _find_in_loot("relay"), OBJECTIVE_TINT)
			"escort":
				if _local.towing:
					out.append({"pos": GameRules.ARENA_SIZE / 2.0, "color": OBJECTIVE_TINT})
				else:
					_append_target(out, _find_in_loot("payload"), OBJECTIVE_TINT)
	var here := _local.global_position
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return here.distance_squared_to(a.pos) < here.distance_squared_to(b.pos))
	if out.size() > MAX_OBJECTIVE_MARKERS:
		out.resize(MAX_OBJECTIVE_MARKERS)
	for p in _game.players.get_children():
		if p is Player and p.downed and not p.dead and p != _local:
			out.push_front({"pos": (p as Player).global_position, "color": DOWNED_TINT})
	return out


func _append_target(out: Array, node: Node2D, color: Color) -> void:
	if node != null:
		out.append({"pos": node.global_position, "color": color})


func _find_beast() -> Enemy:
	for e in _game.enemies.get_children():
		if e is Enemy and e.kind == "beast":
			return e
	return null


func _find_boss() -> Enemy:
	for e in _game.enemies.get_children():
		if e is Enemy and e.kind == "warden":
			return e
	return null


func _find_in_loot(group: String) -> Node2D:
	for n in _game.loot.get_children():
		if n.is_in_group(group) and not n.is_queued_for_deletion():
			return n
	return null


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

	# The marker pool is added before everything else: siblings draw in order,
	# so the readouts and panels that follow sit over the arrows, not under.
	for i in MARKER_POOL:
		var marker := Node2D.new()
		marker.visible = false
		var arrow := Sprite2D.new()
		arrow.name = "Arrow"
		arrow.texture = ARROW_TEXTURE
		marker.add_child(arrow)
		var range_label := _label("", 7)
		range_label.name = "Range"
		range_label.position = Vector2(-16, 6)
		range_label.size = Vector2(32, 10)
		range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.add_child(range_label)
		add_child(marker)
		_markers.append(marker)

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

	_objective_label = _label("SALVAGE 0/6", 10)
	_objective_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_objective_label.position = Vector2(-176, 8)
	_objective_label.size = Vector2(168, 14)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_objective_label.modulate = Color(0.95, 0.85, 0.4)
	root.add_child(_objective_label)

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

	_boss_label = _label("THE TRENCH WARDEN", 8)
	_boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_label.position = Vector2(-52, 66)  # below the toast band
	_boss_label.modulate = Color(1.0, 0.45, 0.4)
	_boss_label.visible = false
	root.add_child(_boss_label)
	_boss_bar = ProgressBar.new()
	_boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_bar.position = Vector2(-110, 78)
	_boss_bar.size = Vector2(220, 8)
	_boss_bar.show_percentage = false
	_boss_bar.modulate = Color(1.0, 0.45, 0.4)
	_boss_bar.visible = false
	root.add_child(_boss_bar)

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
	_over_station_btn.text = "RETURN TO THE SUB"
	_over_station_btn.pressed.connect(func() -> void: Net.return_to_lobby())
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
