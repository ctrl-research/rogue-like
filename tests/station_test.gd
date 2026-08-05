extends Node
## Unit tests for the persistent autoloads — Station's bank/spend math, level
## caps and save/load round-trip, plus the Settings brightness calibration —
## all against test-only save paths.
## Prints STATION_TEST_OK / STATION_TEST_FAIL and exits with a matching code.

var _failures: PackedStringArray = []


func _ready() -> void:
	Station._save_path = "user://station_test.json"
	Station.bank = 0
	Station.levels = {}

	_check(not Station.can_buy("o2"), "cannot buy with empty bank")
	Station.bank_salvage(100)
	_check(Station.bank == 100, "bank_salvage adds")
	_check(Station.cost("o2") == 25, "level-1 cost is base cost")
	_check(Station.buy("o2"), "buy succeeds with funds")
	_check(Station.level("o2") == 1 and Station.bank == 75, "buy deducts and levels")
	_check(Station.cost("o2") == 40, "cost scales 1.6x per level")
	_check(int(Station.meta_dict()["o2"]) == 1, "meta_dict reflects levels")

	Station.bank = 0
	Station.levels = {}
	Station.load_data()
	_check(Station.level("o2") == 1 and Station.bank == 75, "save/load round-trip")

	Station.levels["o2"] = int(Station.UPGRADES["o2"]["max"])
	Station.bank = 9999
	_check(not Station.can_buy("o2"), "cannot buy past max level")

	# Divers: unlock, select, persist, and reject locked selections.
	Station.bank = 0
	Station.unlocked_divers = [Divers.DEFAULT]
	Station.diver = Divers.DEFAULT
	_check(not Station.can_buy_diver("lancer"), "cannot buy diver broke")
	_check(not Station.select_diver("lancer"), "cannot select locked diver")
	Station.bank_salvage(150)
	_check(Station.buy_diver("lancer"), "buy diver with funds")
	_check(Station.diver == "lancer" and Station.bank == 0, "buy selects and deducts")
	_check(not Station.can_buy_diver("lancer"), "cannot re-buy owned diver")
	_check(Station.select_diver(Divers.DEFAULT), "reselect default")
	_check(str(Station.meta_dict()["diver"]) == Divers.DEFAULT, "meta carries diver")
	Station.bank = 0
	Station.unlocked_divers = [Divers.DEFAULT]
	Station.load_data()
	_check(Station.diver_unlocked("lancer"), "diver unlock survives save/load")

	# Winch refits: gated on cleared lairs, cost scales per tier, persists.
	Station.bank = 500
	Station.cleared_lair = 0
	Station.winch = 0
	Station.dive_depth = 1
	_check(not Station.can_buy_winch(), "no refit before clearing a lair")
	Station.record_lair_cleared(5)
	_check(Station.can_buy_winch(), "refit purchasable after lair clear")
	_check(Station.winch_cost(1) == 200, "tier-1 refit cost")
	_check(Station.buy_winch(), "buy refit")
	_check(Station.winch == 1 and Station.bank == 300, "refit deducts and tiers")
	var depths := Station.start_depths()
	_check(depths.size() == 2 and depths[0] == 1 and depths[1] == 6, "start depths surface + 6")
	_check(not Station.can_buy_winch(), "tier 2 needs the depth-10 lair")
	_check(not Station.select_dive_depth(11), "cannot select locked depth")
	_check(Station.select_dive_depth(6), "select unlocked depth")
	Station.dive_depth = 1
	Station.winch = 0
	Station.load_data()
	_check(Station.winch == 1 and Station.dive_depth == 6, "winch survives save/load")

	# Days: each dive turns the calendar, and it persists.
	var day_before := Station.day
	Station.advance_day()
	_check(Station.day == day_before + 1, "advance_day increments")
	Station.day = 1
	Station.load_data()
	_check(Station.day == day_before + 1, "day survives save/load")

	# Brightness: clamped to its range, persisted, and folded into the ambient.
	Settings._save_path = "user://settings_test.json"
	Settings.brightness = 1.0
	Settings.set_brightness(99.0)
	_check(Settings.brightness == Settings.BRIGHTNESS_MAX, "brightness clamps high")
	Settings.set_brightness(-5.0)
	_check(Settings.brightness == Settings.BRIGHTNESS_MIN, "brightness clamps low")
	Settings.set_brightness(1.4)
	Settings.brightness = 1.0
	Settings.load_data()
	_check(is_equal_approx(Settings.brightness, 1.4), "brightness survives save/load")
	# Deeper water is darker at any setting, and brightness lifts both.
	var shallow := Settings.ambient_for_depth(1)
	var deep := Settings.ambient_for_depth(9)
	_check(deep.r < shallow.r, "ambient darkens with depth")
	Settings.set_brightness(2.0)
	_check(Settings.ambient_for_depth(1).r > shallow.r, "brightness lifts the ambient")
	Settings.set_brightness(1.0)

	if _failures.is_empty():
		print("STATION_TEST_OK")
		get_tree().quit(0)
	else:
		print("STATION_TEST_FAIL: %s" % ", ".join(_failures))
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)
