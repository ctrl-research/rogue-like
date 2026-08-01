class_name GameRules
## Tuning constants shared across scenes. All balance lives here so a balance
## pass touches one file.

const ARENA_SIZE := Vector2(1600, 1600)
const ENEMY_CAP := 80
const CRATE_COUNT := 6
const OXYGEN_TIME := 300.0  # seconds; at zero, suffocation damage starts
const SUFFOCATION_DPS := 6.0
const EXTRACTION_TIME := 3.0  # seconds all living divers must hold the bell

const XP_PER_GEM := 1
const UPGRADE_KINDS: Array[String] = ["damage", "fire_rate", "speed", "hull"]


static func xp_needed(level: int) -> int:
	return 4 + level * 3
