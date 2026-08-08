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
	# Any colour the player likes, preserved exactly — the picker is a full
	# gradient, not a fixed palette.
	_check(Appearance.normalize_color("#3fa9d9", Appearance.DEFAULT_SUIT) == "#3fa9d9",
			"an arbitrary colour is preserved")
	_check(Appearance.normalize_color("3fa9d9", Appearance.DEFAULT_SUIT) == "#3fa9d9",
			"a missing # is tolerated")
	_check(Appearance.normalize_color("garbage", Appearance.DEFAULT_SUIT)
			== Appearance.DEFAULT_SUIT, "unparseable falls back")
	_check(Appearance.normalize_color(12345, Appearance.DEFAULT_SUIT)
			== Appearance.DEFAULT_SUIT, "a non-string falls back")
	_check(Appearance.normalize_color("", Appearance.DEFAULT_SUIT)
			== Appearance.DEFAULT_SUIT, "empty falls back")
	# The one constraint, and it is functional: 2D lights multiply, so a black
	# suit stays black under a lamp and the diver simply is not there. The floor
	# is on the brightest channel, which is what survives a multiply — a
	# luminance floor would have lightened pure blue into a pastel.
	_check(Appearance.lift(Color.BLACK) == Color(Appearance.MIN_CHANNEL,
			Appearance.MIN_CHANNEL, Appearance.MIN_CHANNEL), "black becomes a grey")
	_check(maxf(Appearance.lift(Color(0.02, 0.0, 0.0)).r, 0.0) >= Appearance.MIN_CHANNEL - 0.001,
			"near-black is lifted to the floor")
	# Saturated colours keep their hue and saturation: only brightness moves.
	var dark_red := Appearance.lift(Color(0.05, 0.0, 0.0))
	_check(dark_red.g == 0.0 and dark_red.b == 0.0, "lifting preserves saturation")
	_check(Appearance.lift(Color(0.0, 0.0, 1.0)) == Color(0.0, 0.0, 1.0),
			"pure blue is left alone despite low luminance")
	var kept := Color(0.85, 0.65, 0.13)
	_check(Appearance.lift(kept).is_equal_approx(kept), "a legible colour is untouched")
	var junk := Appearance.sanitize({"name": "\n\n", "suit": null, "screen": []})
	_check(str(junk.suit) == Appearance.DEFAULT_SUIT
			and str(junk.screen) == Appearance.DEFAULT_SCREEN,
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

	# Build the appearance editor for real. Nothing else in CI touches it: the
	# title screen is bypassed by the e2e (it calls Net.host_online directly) and
	# the locker panel only opens on a keypress — so a renamed ColorPicker
	# property or a bad shader path here would reach players untested.
	var probe := VBoxContainer.new()
	# Placed and sized explicitly so the controls inside get meaningful global
	# rects — the placement assertions below are about real geometry.
	probe.position = Vector2(100, 200)
	probe.size = Vector2(120, 70)
	add_child(probe)
	StationUi.build_appearance(probe, 32)
	_check(probe.get_child_count() >= 4, "appearance editor builds its rows")
	var found_picker := _find_picker(probe)
	_check(found_picker != null, "the editor contains a colour picker button")
	if found_picker != null:
		var picker := found_picker.get_picker()
		_check(picker != null, "the picker is instantiated eagerly, not on first press")
		if picker != null:
			_check(not picker.sliders_visible and not picker.sampler_visible,
					"the picker is trimmed down")
			_check(picker.hex_visible, "hex stays reachable so any colour can be typed")
		# The size itself, which is the part that actually regressed once: trimming
		# alone left the popup nearly the full 360px height, because a minimum size
		# cannot shrink a Control. Emit about_to_popup to run the real sizing path.
		var popup := found_picker.get_popup()
		_check(popup != null, "the picker button has a popup")
		if popup != null:
			# Let the containers lay out first: placement is computed from the
			# button's global rect, which is meaningless before a layout pass.
			await get_tree().process_frame
			popup.about_to_popup.emit()
			_check(is_equal_approx(popup.content_scale_factor, StationUi.PICKER_SCALE),
					"the popup is scaled down rather than merely trimmed")
			_check(popup.size.y <= 180,
					"the popup is at most half the screen height, not all of it")
			# Centred on its button rather than parked wherever the pre-scale size
			# happened to fit, which was the top of the screen.
			if popup.is_embedded():
				var button_mid := found_picker.get_global_rect().get_center().x
				var popup_mid := popup.position.x + popup.size.x / 2.0
				_check(absf(button_mid - popup_mid) <= 2.0,
						"the popup is centred on its colour button")
				var view := get_viewport().get_visible_rect().size
				_check(popup.position.y >= 0
						and popup.position.y + popup.size.y <= int(view.y),
						"the popup sits fully on screen")
	probe.queue_free()

	# Lamp disc: built at exactly the reach it will be drawn at, so texture_scale
	# stays 1.0 and one texture pixel is one game pixel. A fractional scale is what
	# made a hard-edged disc read as blurry.
	var disc := LampTexture.for_radius(64)
	_check(disc != null and disc.get_width() == 128 and disc.get_height() == 128,
			"the disc is generated at 1:1 for its reach")
	_check(LampTexture.for_radius(64) == disc, "discs are cached per reach")
	var disc_img := disc.get_image()
	_check(is_equal_approx(disc_img.get_pixel(64, 64).a, 1.0),
			"the middle of the lamp is at full strength")
	# A hard cut, not a fade: the corner is outside the circle entirely.
	_check(is_equal_approx(disc_img.get_pixel(0, 0).a, 0.0),
			"outside the lamp is fully transparent")
	# Still banded, so the light falls off toward the rim in countable steps.
	_check(disc_img.get_pixel(124, 64).a < disc_img.get_pixel(64, 64).a,
			"the rim is dimmer than the middle")
	_check(LampTexture.for_radius(1).get_width() == LampTexture.MIN_RADIUS * 2,
			"a silly reach clamps instead of producing a degenerate image")
	# Symmetry, which the first version of the span maths got wrong: rounding a
	# run's start and its width independently biased one side and made the disc
	# visibly lopsided. Sampled rather than compared pixel by pixel to keep the
	# unit test quick.
	var lopsided := false
	for probe_y in [8, 32, 64, 100, 127]:
		for probe_x in [3, 17, 40, 63]:
			var left := disc_img.get_pixel(probe_x, probe_y).a
			var right := disc_img.get_pixel(127 - probe_x, probe_y).a
			var top := disc_img.get_pixel(probe_x, probe_y).a
			var bottom := disc_img.get_pixel(probe_x, 127 - probe_y).a
			if not is_equal_approx(left, right) or not is_equal_approx(top, bottom):
				lopsided = true
	_check(not lopsided, "the disc is symmetric horizontally and vertically")

	# The wardrobe sprite's .import was hand-written (md5 of the resource path,
	# uid checked against every other in the project), so verify it actually
	# imports — a bad one shows up in game as a station with no sprite.
	var wardrobe: Texture2D = load("res://assets/sprites/wardrobe.png")
	_check(wardrobe != null and wardrobe.get_width() == 16 and wardrobe.get_height() == 16,
			"the wardrobe sprite imports")

	# Meta arriving from another peer. _rpc_notify_ready is any_peer, so on a public
	# dedicated server this dict is attacker-controlled and it drives hp, speed,
	# damage and the crew's shared oxygen tank.
	var o2_max := int(Station.UPGRADES["o2"]["max"])
	var cheated := Station.sanitize_meta({"o2": 999999, "hull": 500, "harpoon": -20})
	_check(int(cheated["o2"]) == o2_max, "an inflated level clamps to the shop's max")
	_check(int(cheated["hull"]) == int(Station.UPGRADES["hull"]["max"]),
			"every upgrade track is clamped, not just o2")
	_check(int(cheated["harpoon"]) == 0, "a negative level floors at zero")
	# The important one is not cheating but crashing: int() on a Dictionary or Array
	# is a runtime error, so an unchecked cast here would let a hostile client take
	# the server down mid-handshake rather than merely give itself free upgrades.
	var hostile := Station.sanitize_meta({"o2": {}, "hull": [], "fins": "lots", "lamp": null})
	_check(int(hostile["o2"]) == 0 and int(hostile["hull"]) == 0
			and int(hostile["fins"]) == 0 and int(hostile["lamp"]) == 0,
			"non-numeric levels read as zero instead of erroring")
	_check(Station.sanitize_meta("not a dict").has("o2"),
			"a non-dict payload still yields a usable meta")
	_check(str(Station.sanitize_meta({"diver": "not_a_diver"})["diver"]) == Divers.DEFAULT,
			"an unknown diver class falls back")
	_check(str(Station.sanitize_meta({"profile": {"suit": "#000000"}})["profile"]["suit"])
			!= "#000000", "the profile is sanitized through the same path")
	# Every declared upgrade must be present, or player.gd silently reads level 0 for
	# a track someone actually bought.
	for id in Station.UPGRADES:
		_check(Station.sanitize_meta({}).has(id), "sanitized meta always carries %s" % id)

	# Connection capacity. WebSocketMultiplayerPeer.create_server takes no client
	# limit, unlike the ENet path, so this is the only thing bounding a flood.
	_check(Net.max_clients() >= 1, "at least one client may connect")
	_check(Net.max_clients() <= Net.MAX_PLAYERS, "never more clients than crew seats")
	# A listen server is itself a diver and so takes one fewer client. is_dedicated()
	# is false under the test runner, which is the listen-server case.
	_check(Net.max_clients() == Net.MAX_PLAYERS - 1,
			"a listen server leaves a seat for its own diver")

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


## Depth-first search for the first ColorPickerButton, so the probe above doesn't
## have to know how build_appearance nests its rows.
func _find_picker(node: Node) -> ColorPickerButton:
	for child in node.get_children():
		if child is ColorPickerButton:
			return child
		var deeper := _find_picker(child)
		if deeper != null:
			return deeper
	return null


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)
