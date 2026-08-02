extends Node
## Dive-station meta-progression (autoload "Station"). Persistent across runs
## and local to this player: banked salvage buys permanent upgrade tracks that
## apply at the start of every dive. In co-op each player banks the full team
## haul (no split disputes) and brings their own upgrades.

signal changed

const SAVE_PATH := "user://station.json"

## Upgrade tracks: per-level effect is applied in-game (see meta handshake in
## game.gd / player.gd). Cost of level N (1-based): base * 1.6^(N-1), rounded.
const UPGRADES := {
	"o2": {"title": "O2 RESERVE", "desc": "+15s team oxygen", "base_cost": 25, "max": 5},
	"hull": {"title": "HULL PLATING", "desc": "+15 max hull", "base_cost": 25, "max": 5},
	"harpoon": {"title": "HARPOON MK", "desc": "+8% harpoon damage", "base_cost": 30, "max": 5},
	"fins": {"title": "DIVE FINS", "desc": "+4% move speed", "base_cost": 30, "max": 5},
}

const O2_PER_LEVEL := 15.0
const HULL_PER_LEVEL := 15.0
const HARPOON_PER_LEVEL := 0.08
const FINS_PER_LEVEL := 0.04

var bank := 0
var levels := {}  # id -> int
var unlocked_divers: Array = [Divers.DEFAULT]
var diver := Divers.DEFAULT

var _save_path := SAVE_PATH


func _ready() -> void:
	load_data()


func level(id: String) -> int:
	return int(levels.get(id, 0))


func cost(id: String) -> int:
	return int(ceil(UPGRADES[id].base_cost * pow(1.6, level(id))))


func can_buy(id: String) -> bool:
	return level(id) < int(UPGRADES[id].max) and bank >= cost(id)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	bank -= cost(id)
	levels[id] = level(id) + 1
	save_data()
	changed.emit()
	return true


func diver_unlocked(id: String) -> bool:
	return unlocked_divers.has(id)


func can_buy_diver(id: String) -> bool:
	return Divers.valid(id) and not diver_unlocked(id) and bank >= int(Divers.DIVERS[id].cost)


func buy_diver(id: String) -> bool:
	if not can_buy_diver(id):
		return false
	bank -= int(Divers.DIVERS[id].cost)
	unlocked_divers.append(id)
	select_diver(id)
	return true


func select_diver(id: String) -> bool:
	if not Divers.valid(id) or not diver_unlocked(id):
		return false
	diver = id
	save_data()
	changed.emit()
	return true


func bank_salvage(amount: int) -> void:
	if amount <= 0:
		return
	bank += amount
	save_data()
	changed.emit()


## The dict sent to the game server at dive start (see _rpc_notify_ready).
func meta_dict() -> Dictionary:
	return {
		"o2": level("o2"),
		"hull": level("hull"),
		"harpoon": level("harpoon"),
		"fins": level("fins"),
		"diver": diver,
	}


func load_data() -> void:
	bank = 0
	levels = {}
	unlocked_divers = [Divers.DEFAULT]
	diver = Divers.DEFAULT
	if not FileAccess.file_exists(_save_path):
		return
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	bank = maxi(0, int(parsed.get("bank", 0)))
	var raw: Variant = parsed.get("levels", {})
	if raw is Dictionary:
		for id in UPGRADES:
			levels[id] = clampi(int(raw.get(id, 0)), 0, int(UPGRADES[id].max))
	var raw_divers: Variant = parsed.get("divers", [])
	if raw_divers is Array:
		for id in raw_divers:
			if Divers.valid(str(id)) and not unlocked_divers.has(str(id)):
				unlocked_divers.append(str(id))
	var saved_diver := str(parsed.get("diver", Divers.DEFAULT))
	if Divers.valid(saved_diver) and diver_unlocked(saved_diver):
		diver = saved_diver


func save_data() -> void:
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Station: could not write %s" % _save_path)
		return
	file.store_string(JSON.stringify({
		"bank": bank,
		"levels": levels,
		"divers": unlocked_divers,
		"diver": diver,
	}))
