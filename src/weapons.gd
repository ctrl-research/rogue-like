class_name Weapons
## Data tables for weapons and passive gear. Balance and copy live here;
## behavior lives in player.gd (firing) and the projectile/charge scripts.

const WEAPONS := {
	"harpoon": {
		"title": "HARPOON GUN",
		"desc": "Bolt at the nearest threat",
		"cd": 0.9,
		"damage": 12.0,
		"range": 230.0,
	},
	"lance": {
		"title": "ARC LANCE",
		"desc": "Piercing spear through the swarm",
		"cd": 2.3,
		"damage": 24.0,
		"range": 320.0,
	},
	"charge": {
		"title": "DEPTH CHARGE",
		"desc": "Lobbed blast, area damage",
		"cd": 3.2,
		"damage": 32.0,
		"range": 220.0,
		"radius": 52.0,
	},
	"drone": {
		"title": "DRONE SWARM",
		"desc": "Orbiting drones shred nearby fauna",
		"cd": 0.5,
		"damage": 6.0,
		"range": 0.0,
	},
	"sonar": {
		"title": "SONAR PULSE",
		"desc": "Radial shockwave, pushes the swarm back",
		"cd": 4.0,
		"damage": 15.0,
		"range": 0.0,
	},
	"cutter": {
		"title": "PLASMA CUTTER",
		"desc": "Close arc slashes, heavy damage",
		"cd": 1.0,
		"damage": 18.0,
		"range": 46.0,
	},
	"drill": {
		"title": "SEISMIC DRILL",
		"desc": "Grinds everything just ahead",
		"cd": 0.35,
		"damage": 5.0,
		"range": 44.0,
	},
}

## Maxing a weapon while owning its paired passive unlocks an evolution
## (offered as a special card; the weapon jumps to EVOLVED_LEVEL).
const EVOLVED_LEVEL := 6
## Every weapon can evolve, and passives are deliberately shared between them:
## a passive is a build archetype, so committing to magnet opens the harpoon
## AND the drone evolution rather than gating exactly one card.
const EVOLUTIONS := {
	"harpoon": {"requires": "magnet", "title": "CHAIN HARPOON", "desc": "Bolts arc between prey"},
	"lance": {"requires": "lamp", "title": "SOLAR LANCE", "desc": "A spear of burning light"},
	"charge": {"requires": "suit", "title": "PRESSURE BOMB", "desc": "Implodes and stuns the deep"},
	"drone": {"requires": "magnet", "title": "WRECKING SWARM", "desc": "More drones, wider bite"},
	"sonar": {"requires": "lamp", "title": "PRESSURE BLOOM", "desc": "A wave that stuns and hurls"},
	"cutter": {"requires": "suit", "title": "MAELSTROM CUTTER", "desc": "Slashes all around you"},
	"drill": {"requires": "fins", "title": "TECTONIC DRILL", "desc": "Chews wider rock and bone"},
}

const EVOLVED_DRONES := 7  # WRECKING SWARM: two past the level cap
const EVOLVED_DRONE_RANGE := 26.0  # vs DRONE_HIT_RANGE

const PASSIVES := {
	"fins": {"title": "STREAMLINED FINS", "desc": "+10% move speed"},
	"suit": {"title": "REINFORCED SUIT", "desc": "+20 max hull, patch 25"},
	"rebreather": {"title": "REBREATHER", "desc": "+25s team oxygen"},
	"magnet": {"title": "SALVAGE MAGNET", "desc": "+40% pickup radius"},
	"lamp": {"title": "ARC LAMP", "desc": "Wider lamp radius"},
}

const REBREATHER_OXYGEN := 25.0


static func is_weapon(id: String) -> bool:
	return WEAPONS.has(id) or id.begins_with("evolve_")


static func title(id: String) -> String:
	if id.begins_with("evolve_"):
		return EVOLUTIONS[id.trim_prefix("evolve_")].title
	if WEAPONS.has(id):
		return WEAPONS[id].title
	return PASSIVES[id].title


static func desc(id: String) -> String:
	if id.begins_with("evolve_"):
		return EVOLUTIONS[id.trim_prefix("evolve_")].desc
	if WEAPONS.has(id):
		return WEAPONS[id].desc
	return PASSIVES[id].desc


## Display name for an owned weapon at a level (evolved weapons rename).
static func display_title(id: String, level: int) -> String:
	if level >= EVOLVED_LEVEL and EVOLUTIONS.has(id):
		return EVOLUTIONS[id].title
	return WEAPONS[id].title


static func weapon_damage(id: String, level: int) -> float:
	return WEAPONS[id].damage * (1.0 + 0.3 * (level - 1))


static func weapon_cd(id: String, level: int) -> float:
	return WEAPONS[id].cd * pow(0.93, mini(level, 5) - 1)


static func sonar_radius(level: int) -> float:
	return 85.0 + 12.0 * (mini(level, 5) - 1)
