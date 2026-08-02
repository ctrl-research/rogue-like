class_name Divers
## Unlockable diver roster — one class per combat archetype. Each diver is a
## starting kit (weapons + passives) bought once with banked salvage at the
## station. The chosen diver travels in the station meta handshake, so every
## peer initializes identical kits with no extra netcode.

const DEFAULT := "salvager"

const DIVERS := {
	"salvager": {
		"title": "SALVAGER",
		"desc": "ranged — harpoon gun, the classic kit",
		"cost": 0,
		"weapons": {"harpoon": 1},
		"passives": {},
	},
	"lancer": {
		"title": "LANCER",
		"desc": "ranged pierce — arc lance + fins",
		"cost": 150,
		"weapons": {"lance": 1},
		"passives": {"fins": 1},
	},
	"brawler": {
		"title": "BRAWLER",
		"desc": "melee — plasma cutter + reinforced suit",
		"cost": 200,
		"weapons": {"cutter": 1},
		"passives": {"suit": 1},
	},
	"driller": {
		"title": "DRILLER",
		"desc": "melee grinder — seismic drill + magnet",
		"cost": 200,
		"weapons": {"drill": 1},
		"passives": {"magnet": 1},
	},
	"bomber": {
		"title": "BOMBER",
		"desc": "AoE burst — starts with Mk2 depth charges",
		"cost": 250,
		"weapons": {"charge": 2},
		"passives": {},
	},
	"echo": {
		"title": "ECHO",
		"desc": "AoE pulse — sonar + arc lamp",
		"cost": 250,
		"weapons": {"sonar": 1},
		"passives": {"lamp": 1},
	},
	"tinker": {
		"title": "TINKER",
		"desc": "summoner — starts with a twin drone swarm",
		"cost": 300,
		"weapons": {"drone": 2},
		"passives": {},
	},
}


static func valid(id: String) -> bool:
	return DIVERS.has(id)


static func kit_weapons(id: String) -> Dictionary:
	return (DIVERS[id if DIVERS.has(id) else DEFAULT].weapons as Dictionary).duplicate()


static func kit_passives(id: String) -> Dictionary:
	return (DIVERS[id if DIVERS.has(id) else DEFAULT].passives as Dictionary).duplicate()
