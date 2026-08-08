class_name GameRules
## Tuning constants shared across scenes. All balance lives here so a balance
## pass touches one file.

const ARENA_SIZE := Vector2(1600, 1600)
const ENEMY_CAP := 80
const CRATE_COUNT := 6
## The bell's safe zone. Comfortably wider than the bell's own 26px body, so the ring
## reads as an area you stand in rather than a hitbox you touch.
##
## Inside it a diver cannot be hurt, cannot attack, and cannot leave until the crew
## moves on — a deliberate pause after a horde rather than a place to camp, which is
## why it only exists once the bell is down and the run is already decided.
const BELL_SAFE_RADIUS := 58.0
## How fast a monster caught inside when the bell lands is shoved out. Pushed rather
## than killed: something invulnerable AND harmless sitting in the middle of the
## breathing room is worse than a brief shove.
const BELL_PUSH_SPEED := 120.0


## Pull a position back onto the safe zone's edge.
##
## Extracted here rather than left inline in player.gd so it can be tested without
## standing up a scene — it is the only real geometry in the safe zone, and getting it
## wrong either lets a diver walk out or pins them at the centre.
static func clamp_into_safety(pos: Vector2, centre: Vector2) -> Vector2:
	var out := pos - centre
	if out.length() <= BELL_SAFE_RADIUS:
		return pos  # already inside; leave it alone
	if out.length() < 0.001:
		# Exactly on the centre has no direction to push along. Any edge point is as
		# good as another, so pick one rather than dividing by ~zero.
		return centre + Vector2.RIGHT * BELL_SAFE_RADIUS
	return centre + out.normalized() * BELL_SAFE_RADIUS
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
## Deepest tier a dive may be requested to start at. The requesting diver's winch
## is client-owned and cannot be verified by the server (progression is local by
## design — see game.gd's _rpc_game_over), so this bounds what a bad or hostile
## value can do instead of trusting it.
const MAX_START_TIER := 20


## Is this a depth a dive could legitimately start from? Valid starts are the
## surface, or one past a boss lair. Checking the SHAPE rather than only a range
## rejects an arbitrary "start me at depth 47" outright.
static func valid_start_depth(d: int) -> bool:
	if d == 1:
		return true
	if d < 1:
		return false
	var past_lair := d - 1
	return past_lair % BOSS_DEPTH_INTERVAL == 0 \
			and past_lair / BOSS_DEPTH_INTERVAL <= MAX_START_TIER


const BOSS_REWARD_BASE := 40  # lair guardian bounty, times depth
# Ordinary waves stop this far below ENEMY_CAP inside a lair, so the guardian
# and the adds it calls always have room to exist. Without the reserve the
# trash saturates the cap and the boss fight becomes a crowd.
const BOSS_WAVE_HEADROOM := 24

# Lamp reach, in pixels, as a tug-of-war. Everything here is the same unit on
# purpose: percentages made the two forces incomparable, because "+10% radius"
# and "-6% per depth" only relate to each other through a base you have to go
# and look up. In pixels you can read the trade straight off — one Lamp Array
# level buys back most of two descents.
const LAMP_BASE_RADIUS := 136.0
const LAMP_ARRAY_RADIUS := 16.0  # per bought Lamp Array level (5 max: +80)
const ARC_LAMP_RADIUS := 24.0  # per in-run Arc Lamp level (5 max: +120)
const LAMP_DEPTH_LOSS := 9.0  # swallowed per descent
const LAMP_MIN_RADIUS := 64.0  # four cells: tight, still playable


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


## How far a lamp reaches, in pixels: what you've bought and picked up, minus
## what the trench has swallowed on the way down. Early on the stock lamp is
## plenty and by the deep floors it isn't, which is the whole point — but it is
## floored, because light going to nothing stops being tension and becomes a
## black screen with a dead crew in it.
static func lamp_radius(bought_levels: int, picked_levels: int, depth: int) -> float:
	var reach := LAMP_BASE_RADIUS \
			+ LAMP_ARRAY_RADIUS * bought_levels \
			+ ARC_LAMP_RADIUS * picked_levels \
			- LAMP_DEPTH_LOSS * maxi(0, depth - 1)
	return maxf(LAMP_MIN_RADIUS, reach)


static func depth_hp_scale(depth: int) -> float:
	return pow(1.3, depth - 1)


static func depth_interval_scale(depth: int) -> float:
	return pow(0.85, depth - 1)


static func depth_brute_bonus(depth: int) -> float:
	return 0.08 * (depth - 1)
