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

	# Lamp: the bought upgrade exists, rides the meta handshake into a dive, and
	# depth eats reach on a curve that bottoms out instead of reaching zero.
	_check(Station.UPGRADES.has("lamp"), "lamp array is purchasable")
	Station.levels["lamp"] = 3
	_check(int(Station.meta_dict()["lamp"]) == 3, "meta carries the lamp level")
	_check(is_equal_approx(GameRules.lamp_radius(0, 0, 1), GameRules.LAMP_BASE_RADIUS),
			"depth 1 with nothing bought is stock reach")
	_check(GameRules.lamp_radius(0, 0, 5) < GameRules.lamp_radius(0, 0, 2),
			"depth takes reach away")
	_check(GameRules.lamp_radius(3, 0, 5) > GameRules.lamp_radius(0, 0, 5),
			"the bought array gives reach back")
	_check(GameRules.lamp_radius(0, 3, 5) > GameRules.lamp_radius(0, 0, 5),
			"the picked-up lamp gives reach back")
	# The tug-of-war in one line: reach lost to descending is exactly reach
	# bought back, in the same unit, so this stays true by construction.
	var two_depths := 2.0 * GameRules.LAMP_DEPTH_LOSS
	_check(is_equal_approx(
			GameRules.lamp_radius(0, 0, 1) - GameRules.lamp_radius(0, 0, 3), two_depths),
			"each descent costs a fixed number of pixels")
	_check(GameRules.lamp_radius(0, 0, 99) == GameRules.LAMP_MIN_RADIUS,
			"reach floors instead of vanishing")

	# Appearance: the cosmetic profile is sanitized on every path in, rides the
	# meta handshake, and survives save/load. Sanitizing matters more here than
	# for anything else in Station because a profile is the only field that
	# arrives from another peer — see Appearance.sanitize.
	_check(Appearance.sanitize_name("  jon  ny ") == "JON NY", "names trim, collapse, upcase")
	_check(Appearance.sanitize_name("a\nb\tc") == "ABC", "control characters stripped")
	_check(Appearance.sanitize_name("x".repeat(99)).length() == Appearance.NAME_MAX,
			"names are capped")
	_check(Appearance.sanitize_name("") == "", "an empty name stays empty")
	# Snapping is total: every input lands on a legible swatch. A picker would
	# let a player choose near-black, which in a game played inside a small lamp
	# radius means choosing to be invisible.
	_check(Appearance.snap("#000000", Appearance.SUIT_SWATCHES, Appearance.DEFAULT_SUIT)
			in Appearance.SUIT_SWATCHES, "black snaps into the palette")
	_check(Appearance.snap("garbage", Appearance.SUIT_SWATCHES, Appearance.DEFAULT_SUIT)
			in Appearance.SUIT_SWATCHES, "unparseable snaps into the palette")
	_check(Appearance.snap(12345, Appearance.SUIT_SWATCHES, Appearance.DEFAULT_SUIT)
			== Appearance.DEFAULT_SUIT, "a non-string falls back")
	_check(Appearance.snap("#d94f3d", Appearance.SUIT_SWATCHES, Appearance.DEFAULT_SUIT)
			== "#d94f3d", "an exact swatch is preserved")
	var junk := Appearance.sanitize({"name": "\n\n", "suit": null, "screen": []})
	_check(str(junk.suit) in Appearance.SUIT_SWATCHES
			and str(junk.screen) in Appearance.SCREEN_SWATCHES,
			"a hostile profile still yields a drawable diver")

	Station.set_profile({"name": "nemo", "suit": "#3fa9d9", "screen": "#ffe89f"})
	_check(str(Station.profile.name) == "NEMO", "profile name stored sanitized")
	var meta_profile: Dictionary = Station.meta_dict()["profile"]
	_check(str(meta_profile.suit) == "#3fa9d9", "meta carries the profile")
	# Mutating what meta handed out must not reach back into Station: the same
	# dict is about to be handed to every peer.
	meta_profile["suit"] = "#000000"
	_check(str(Station.profile.suit) == "#3fa9d9", "meta_dict hands out a copy")
	Station.profile = Appearance.default_profile()
	Station.load_data()
	_check(str(Station.profile.name) == "NEMO" and str(Station.profile.screen) == "#ffe89f",
			"profile survives save/load")
	# Seats are what the sub roster stores; the key exists so roster change
	# detection never depends on Dictionary equality semantics.
	var seat_a := Appearance.make_seat("lancer", {"name": "a", "suit": "#3fa9d9"})
	_check(Appearance.seat_key(seat_a) == Appearance.seat_key(seat_a.duplicate(true)),
			"equal seats key equal")
	_check(Appearance.seat_key(seat_a)
			!= Appearance.seat_key(Appearance.make_seat("lancer", {"name": "b"})),
			"a changed name changes the key")
	_check(str(Appearance.sanitize_seat({"diver": "not_a_diver"}).diver) == Divers.DEFAULT,
			"an unknown diver class falls back")
	_check(str(Appearance.sanitize_seat("not even a dict").diver) == Divers.DEFAULT,
			"a non-dict seat is survivable")

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
	# Ambient steps down by a constant amount per descent, floors rather than
	# reaching black, and brightness lifts the whole thing.
	# Back to 1.0 first: the round-trip above left it at 1.4, and ambient_for_depth
	# folds brightness in, so the shape checks below would be measuring the
	# player's setting rather than the curve.
	Settings.set_brightness(1.0)
	var shallow := Settings.ambient_for_depth(1)
	_check(is_equal_approx(shallow.r, Settings.AMBIENT_SURFACE.r), "depth 1 is the surface shade")
	var one_step := shallow.r - Settings.ambient_for_depth(2).r
	var two_steps := shallow.r - Settings.ambient_for_depth(3).r
	_check(is_equal_approx(two_steps, one_step * 2.0), "each descent costs the same")
	_check(is_equal_approx(Settings.ambient_for_depth(99).r, Settings.AMBIENT_FLOOR.r),
			"ambient floors instead of reaching black")
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
