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
}

const PASSIVES := {
	"fins": {"title": "STREAMLINED FINS", "desc": "+10% move speed"},
	"suit": {"title": "REINFORCED SUIT", "desc": "+20 max hull, patch 25"},
	"rebreather": {"title": "REBREATHER", "desc": "+25s team oxygen"},
	"magnet": {"title": "SALVAGE MAGNET", "desc": "+40% pickup radius"},
	"lamp": {"title": "ARC LAMP", "desc": "Wider lamp radius"},
}

const REBREATHER_OXYGEN := 25.0


static func is_weapon(id: String) -> bool:
	return WEAPONS.has(id)


static func title(id: String) -> String:
	if WEAPONS.has(id):
		return WEAPONS[id].title
	return PASSIVES[id].title


static func desc(id: String) -> String:
	if WEAPONS.has(id):
		return WEAPONS[id].desc
	return PASSIVES[id].desc


static func weapon_damage(id: String, level: int) -> float:
	return WEAPONS[id].damage * (1.0 + 0.3 * (level - 1))


static func weapon_cd(id: String, level: int) -> float:
	return WEAPONS[id].cd * pow(0.93, level - 1)
