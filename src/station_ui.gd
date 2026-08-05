class_name StationUi
## Shared row builders for the station's shop UI, used by the sub interior's
## consoles (and anywhere else the crew spends banked salvage). Each builder
## appends rows to `parent`; callers rebuild on Station.changed.


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
