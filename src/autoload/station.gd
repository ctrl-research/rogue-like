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
	# The answer to depth eating the lamp (GameRules.lamp_radius). Priced above
	# the rest because it buys the ability to keep descending at all.
	"lamp": {"title": "LAMP ARRAY", "desc": "+16 lamp reach", "base_cost": 35, "max": 5},
}

const O2_PER_LEVEL := 15.0
const HULL_PER_LEVEL := 15.0
const HARPOON_PER_LEVEL := 0.08
const FINS_PER_LEVEL := 0.04
# Lamp reach is measured in pixels and lives in GameRules with the depth loss it
# pulls against, so the two can be read side by side (GameRules.lamp_radius).

const WINCH_COST_BASE := 200  # refit tier N costs base * N

var bank := 0
var levels := {}  # id -> int
var unlocked_divers: Array = [Divers.DEFAULT]
var diver := Divers.DEFAULT
var day := 1  # each dive is a day; advances when a run ends (win or loss)
var cleared_lair := 0  # deepest boss lair this diver has cleared
var winch := 0  # bought refit tiers; tier N lets dives start at depth 5N+1
var dive_depth := 1  # chosen start depth for the next dive (host's applies)
## Cosmetic identity — chosen name and the two diver colours (see Appearance).
## Unlike everything above it buys nothing and affects no stat; it is kept here
## only because this is already the thing that persists and already travels in
## the meta handshake, so appearance needs no channel of its own.
var profile := Appearance.default_profile()

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


func advance_day() -> void:
	day += 1
	save_data()
	changed.emit()


# --- Winch-refit checkpoints (bought progress, not free progress) ----------


func record_lair_cleared(d: int) -> void:
	if d > cleared_lair:
		cleared_lair = d
		save_data()
		changed.emit()


func winch_cost(tier: int) -> int:
	return WINCH_COST_BASE * tier


## The next refit is purchasable only once its lair has actually been beaten.
func can_buy_winch() -> bool:
	var next := winch + 1
	return cleared_lair >= next * GameRules.BOSS_DEPTH_INTERVAL \
			and bank >= winch_cost(next)


func buy_winch() -> bool:
	if not can_buy_winch():
		return false
	winch += 1
	bank -= winch_cost(winch)
	save_data()
	changed.emit()
	return true


## Depths a dive may start from: the surface, plus one past each refit lair.
func start_depths() -> Array[int]:
	var out: Array[int] = [1]
	for tier in range(1, winch + 1):
		out.append(tier * GameRules.BOSS_DEPTH_INTERVAL + 1)
	return out


func select_dive_depth(d: int) -> bool:
	if not start_depths().has(d):
		return false
	dive_depth = d
	save_data()
	changed.emit()
	return true


func bank_salvage(amount: int) -> void:
	if amount <= 0:
		return
	bank += amount
	save_data()
	changed.emit()


## Clamp a meta dict that arrived from another peer.
##
## _rpc_notify_ready is @rpc("any_peer"), so on a public dedicated server this dict
## is attacker-controlled. It drives max_hp, move speed, weapon damage and the
## crew's SHARED oxygen tank, so an unclamped `hull: 99999` is an invulnerable
## diver and an unclamped `o2` never runs the tank down — for everyone, since
## _start_run pools o2 across the whole crew. Levels are therefore capped at what
## the shop can actually sell.
##
## Progression stays client-owned; this bounds a claim rather than verifying it.
## Verifying would need server-side accounts, which is a different game.
func sanitize_meta(raw: Variant) -> Dictionary:
	var d: Dictionary = raw if raw is Dictionary else {}
	var out := {}
	for id in UPGRADES:
		out[id] = _claimed_level(d.get(id), int(UPGRADES[id].max))
	var diver_id := str(d.get("diver", Divers.DEFAULT))
	out["diver"] = diver_id if Divers.valid(diver_id) else Divers.DEFAULT
	out["profile"] = Appearance.sanitize(d.get("profile", {}))
	return out


## Type-checked on purpose: int() on a Dictionary or an Array is a runtime error,
## so `{"hull": {}}` from a hostile client would crash the server mid-handshake
## rather than merely cheating. Anything that is not a number reads as level 0.
static func _claimed_level(value: Variant, cap: int) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, cap)
	return 0


## The dict sent to the game server at dive start (see _rpc_notify_ready).
func meta_dict() -> Dictionary:
	return {
		"o2": level("o2"),
		"hull": level("hull"),
		"harpoon": level("harpoon"),
		"fins": level("fins"),
		"lamp": level("lamp"),
		"diver": diver,
		# Appearance rides along rather than getting its own RPC: this dict
		# already reaches every peer via _rpc_notify_ready -> _metas -> spawn
		# data, which is exactly the fan-out a cosmetic profile needs.
		"profile": profile.duplicate(),
	}


## Set and persist the cosmetic profile. Sanitized on the way in so a bad value
## can never reach the save file, let alone the wire.
func set_profile(raw: Dictionary) -> void:
	profile = Appearance.sanitize(raw)
	save_data()
	changed.emit()


func load_data() -> void:
	bank = 0
	levels = {}
	unlocked_divers = [Divers.DEFAULT]
	diver = Divers.DEFAULT
	day = 1
	cleared_lair = 0
	winch = 0
	dive_depth = 1
	profile = Appearance.default_profile()
	if not FileAccess.file_exists(_save_path):
		return
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	bank = maxi(0, int(parsed.get("bank", 0)))
	day = maxi(1, int(parsed.get("day", 1)))
	cleared_lair = maxi(0, int(parsed.get("cleared_lair", 0)))
	winch = maxi(0, int(parsed.get("winch", 0)))
	dive_depth = int(parsed.get("dive_depth", 1))
	if not start_depths().has(dive_depth):
		dive_depth = 1
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
	# Sanitized on load as well as on set: the save file is plain JSON in
	# user:// and nothing stops a player from editing it by hand.
	profile = Appearance.sanitize(parsed.get("profile", {}))


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
		"day": day,
		"cleared_lair": cleared_lair,
		"winch": winch,
		"dive_depth": dive_depth,
		# Hex strings, not Colors — JSON.stringify has no representation for a
		# Color and would silently write something unparseable back.
		"profile": profile,
	}))
