extends Node
## Unit test for the Station meta-progression autoload: bank/spend math,
## level caps, and save/load round-trip against a test-only save path.
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

	if _failures.is_empty():
		print("STATION_TEST_OK")
		get_tree().quit(0)
	else:
		print("STATION_TEST_FAIL: %s" % ", ".join(_failures))
		get_tree().quit(1)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)
