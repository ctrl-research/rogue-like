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

const DECISION_TIME := 12.0  # seconds the host has to pick extract/descend
const DESCEND_O2_BONUS := 90.0  # partial tank top-up per descent
const CRATE_SALVAGE_BASE := 5  # salvage per crate, multiplied by depth
const NUGGET_SALVAGE_BASE := 1  # salvage per mined ore nugget, times depth

# Mini quests: every depth rolls one from the pool; completing it summons the
# bell. Depth 1 is always crates (it teaches the loop). Deeper depths draw
# from a shuffled bag so a run never repeats a quest before seeing them all.
const QUEST_KINDS: Array[String] = ["crates", "swarm", "hunt", "repair", "escort"]
const SWARM_TIME := 70.0  # seconds the crew must outlast the swarm
const SWARM_SPAWN_SCALE := 0.5  # spawn-interval multiplier during the swarm
const QUEST_REWARD_BASE := 20  # non-crate quest completion salvage, times depth
const REPAIR_TIME := 40.0  # seconds a diver must hold near the relay
const REPAIR_RADIUS := 90.0  # hold-position range around the relay
const REPAIR_SPAWN_SCALE := 0.75  # spawn pressure while the relay quest runs
const TOW_SPEED_SCALE := 0.6  # the payload carrier swims heavy
const TOW_GRAB_RADIUS := 26.0  # touch range to pick up the payload
const DELIVER_RADIUS := 60.0  # payload-to-bell-zone distance that completes

# Boss lairs: every 5th depth is a dedicated boss stage — no quest roll,
# just the Warden between the crew and the descent. Clearing one unlocks
# the next winch-refit checkpoint at the station.
const BOSS_DEPTH_INTERVAL := 5
const BOSS_REWARD_BASE := 40  # lair guardian bounty, times depth
# Ordinary waves stop this far below ENEMY_CAP inside a lair, so the guardian
# and the adds it calls always have room to exist. Without the reserve the
# trash saturates the cap and the boss fight becomes a crowd.
const BOSS_WAVE_HEADROOM := 24


static func xp_needed(level: int) -> int:
	return 4 + level * 3


static func crate_value(depth: int) -> int:
	return CRATE_SALVAGE_BASE * depth


static func nugget_value(depth: int) -> int:
	return NUGGET_SALVAGE_BASE * depth


static func quest_reward(depth: int) -> int:
	return QUEST_REWARD_BASE * depth


static func boss_reward(depth: int) -> int:
	return BOSS_REWARD_BASE * depth


static func is_boss_depth(depth: int) -> bool:
	return depth % BOSS_DEPTH_INTERVAL == 0


static func depth_hp_scale(depth: int) -> float:
	return pow(1.3, depth - 1)


static func depth_interval_scale(depth: int) -> float:
	return pow(0.85, depth - 1)


static func depth_brute_bonus(depth: int) -> float:
	return 0.08 * (depth - 1)
