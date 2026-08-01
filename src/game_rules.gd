class_name GameRules
## Tuning constants shared across scenes. All balance lives here so a balance
## pass touches one file.

const ARENA_SIZE := Vector2(1600, 1600)
const ENEMY_CAP := 80
const CRATE_COUNT := 6
const OXYGEN_TIME := 300.0  # seconds; at zero, suffocation damage starts
const SUFFOCATION_DPS := 6.0
const EXTRACTION_TIME := 3.0  # seconds all active divers must hold the bell

const XP_PER_GEM := 1

const MAX_WEAPONS := 3
const WEAPON_MAX_LEVEL := 5
const PASSIVE_MAX_LEVEL := 5

const REVIVE_TIME := 3.0  # seconds a rescuer must hold position
const REVIVE_RANGE := 32.0
const BLEED_FRACTION := 0.4  # of max hp; the downed bleed-out pool
const BLEED_TIME := 45.0  # seconds until a downed diver bleeds out


static func xp_needed(level: int) -> int:
	return 4 + level * 3
