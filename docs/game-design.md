# Abyssal Salvage — Game Design (working title)

A 2D pixel-art, multiplayer (2–4 player co-op) horde-survival roguelike.
Think **Vampire Survivors meets Deep Rock Galactic, at the bottom of an ocean
trench**: a small dive crew drops onto sunken wrecks, auto-firing weapons carve
through swarms of abyssal creatures, and the team completes salvage objectives
before the oxygen runs out — then extracts, or pushes deeper for greater loot.

## Fantasy & theme

You are contract salvage divers working a procedurally generated ocean trench.
Each run is a **dive**: the crew descends to a wreck site, fights escalating
hordes of deep-sea horrors drawn by the noise, recovers salvage, and calls the
dive bell to extract. Depth is the difficulty axis — deeper wrecks mean richer
salvage and nastier fauna. Between dives, salvage funds upgrades to the crew's
dive station (meta-progression).

The theme earns its mechanics:

- **Oxygen** is the run timer (the roguelike "hunger clock").
- **Darkness / light radius** creates tension and makes positioning matter.
- **Depth** is a natural difficulty ladder and biome axis.
- **The dive bell** is the extraction decision point: leave with what you have,
  or descend to the next wreck with dwindling oxygen.

## Core loop (one dive)

1. Drop into a wreck site (arena-style map, bounded).
2. Hordes spawn in waves that scale with time; weapons auto-fire — players
   focus on **movement, positioning, and objectives**.
3. Kills drop **biomass (XP)**; team levels grant upgrades (new weapons,
   stat boosts) — builds diverge over a run.
4. Complete the site objective (e.g., recover N salvage crates) to unlock the
   dive bell.
5. Decide together: **extract** (bank the loot) or **descend** (next site,
   deeper, harder, better rewards, same oxygen tank).
6. Wipe or oxygen-out = lose unbanked salvage. Extract = fund station upgrades.

## The long game — sub, days, descent (planned direction)

The dive station grows into a **submarine**: the crew's homebase, hovering
over the trench. The loop above stays the heartbeat; this gives it a life
around it.

- **The sub is home.** Between dives the crew is aboard the sub — a small
  walkable 2D interior with the salvage stash, upgrade console, diver
  locker, and dive hatch. The interior *is* the multiplayer lobby: the crew
  physically gathers aboard before diving. Current menus stand in only
  until its milestone ships.
- **Each dive is a day.** A day counter ticks per dive and frames the
  campaign ("Day 14 — depth record 11"). Days are the hook for future
  events, story beats, and pacing.
- **Every stage rolls a mini quest.** Completing it summons the bell and
  unlocks the descent. Quest pool: crate recovery (the classic), hunt the
  beast (track a named elite via sonar pings), survive the swarm (timed
  onslaught), repair & defend (hold a wreck position through waves),
  escort the payload (tow a heavy artifact — carrier slowed and targeted).
  Deeper stages roll harder quest variants.
- **Boss lairs every 5th depth.** Depths 5, 10, 15… are dedicated boss
  stages — no quest, just the lair's guardian between the crew and the
  descent, with a big guaranteed haul. The Trench Maw stays the crate-quest
  miniboss; lairs get their own monsters.
- **Buyable checkpoints.** Clearing a boss lair lets the crew buy a
  start-depth unlock (winch + pressure-hull refit) with banked salvage, so
  future dives may begin below that lair. Runs are still descend-or-die —
  the checkpoint is bought progress, not free progress — and hoarding
  resources on the sub finally has a purpose beyond stat upgrades.

## Multiplayer design

- 2–4 player **co-op PvE**, drop-in lobby before the dive.
- Enemies scale with player count (spawn rate + HP multiplier).
- Shared team XP/level, individual upgrade choices — keeps everyone
  progressing together while builds stay personal.
- Downed players bleed out unless a teammate revives them (channel, standing
  still, surrounded by a horde — the classic co-op moment).
- Friendly-fire off; body-blocking off between divers.

## Combat & builds

- Weapons **auto-fire** at the nearest/priority target (Vampire Survivors
  model). Skill expression = movement, kiting, objective routing.
- Weapon families (harpoon launcher, arc lance, depth-charge dropper, drone
  swarm, sonar pulse…) each with a level track; combining maxed weapons with
  matching gear evolves them (VS-style evolutions).
- Passive gear: fins (move speed), pressure suit (armor), rebreather (oxygen
  efficiency), lamp (light radius), magnet (pickup radius).

## Roguelike elements

- Procedural wreck layouts, enemy wave composition, and upgrade offers.
- Permadeath per dive; only banked salvage persists.
- Meta-progression: dive-station upgrades (new starting weapons, characters
  with distinct starting kits, oxygen tank capacity, unlock deeper trenches).

## Enemy design (initial roster)

| Enemy | Role | Behavior |
|---|---|---|
| Barbfish | Swarmer | Fast, weak, chases nearest diver |
| Angler brute | Tank | Slow, high HP, heavy contact damage |
| Lurker | Ambusher | Sits camouflaged, lunges when close |
| Jelly bloom | Hazard | Slow drift, area denial, splits on death |
| Trench maw (boss) | Wave climax | Periodic mini-boss guarding prime salvage |

Milestone 0 ships Barbfish + Angler brute only.

## Presentation

- Pixel art, ~16×16 sprites, 640×360 internal resolution scaled up
  (integer-ish scaling via `canvas_items` stretch, nearest-neighbor filtering).
- Deep palette: near-black blues, bioluminescent accents, warm diver lamps.
- `CanvasModulate` darkness + per-diver `PointLight2D` lamp for the abyss look.

## Tech

- **Godot 4.6.3**, GL Compatibility renderer (matches web export).
- Godot high-level multiplayer (`MultiplayerSpawner` / `MultiplayerSynchronizer`),
  server-authoritative enemies/loot, client-authoritative movement (fine for
  co-op PvE).
- **Web build deploys to GitHub Pages from CI** (threads disabled so no
  cross-origin-isolation headers are needed). Solo runs in browser today.
- Desktop builds use ENet (LAN/direct IP). Browser co-op arrives via WebRTC +
  a small signaling service (see `~/projects/fps` `signaling/` for prior art).

## Milestones

- **M0 — done (PR #1)** — playable prototype: menu (solo/host/join), one
  arena, 2 enemy types, harpoon auto-fire, XP + random level-up boosts,
  salvage-crate objective, dive-bell extraction, oxygen timer, HUD,
  win/lose. CI → Pages.
- **M1 — done (PR #2)** — level-up choice UI (pick 1 of 3), arc lance +
  depth charge + passives, downed/bleed-out/revive, self-playing CI bot.
- **M2 — done (PR #3)** — browser multiplayer: WebRTC room codes + invite
  links, signaling broker (vendored + fixed), two-instance e2e test in CI.
  *Remaining infra: deploy the broker to the team k8s cluster behind
  `wss://` and set `network/signaling/url` (game code is ready).*
- **M3 — done (PR #4)** — descend-or-extract chain, depth scaling, salvage
  as currency, persistent station upgrades (O2 reserve / hull plating /
  harpoon mk / dive fins).
- **M4a — done (PR #5)** — content pass: Lurker (camouflaged ambusher), Jelly
  bloom (splits on death), Trench Maw mini-boss guarding the last crates;
  drone swarm + sonar pulse weapons; weapon evolutions (Chain Harpoon,
  Solar Lance, Pressure Bomb) unlocked by maxed weapon + paired passive.

- **M4b — done (PR #10)** — feel/polish: procedural SFX + underwater audio
  bus, hit feedback (enemy hp sync), damage numbers, screen shake, bubbles.
- **M4c — done (PR #11)** — unlockable divers, one per combat archetype, bought
  with banked salvage: Salvager (ranged), Lancer (ranged pierce), Brawler
  (melee, new plasma cutter), Driller (melee grinder, new seismic drill),
  Bomber (AoE burst, Mk2 charges), Echo (AoE pulse), Tinker (summoner).

- **M5 — done (PR #12)** — procedurally generated destructible terrain:
  seeded rock layouts (denser with depth) with guaranteed clearings +
  corridors, server-authoritative destruction (drill digs fast, cutter
  chips, charges crater, fauna chew through walls), projectiles blocked
  by rock.
- **M5.1 — done (PR #13)** — universal mining: any diver pushing into rock
  mines it slowly; mining pauses your weapons ("hands full") unless you
  carry the seismic drill, whose crews work and shoot at once.
- **M6 — done (PR #14)** — ore pockets: seeded gold seams buried in rock
  (richer with depth, deterministic on every peer like the rock itself);
  digging out an ore cell shakes loose a salvage nugget worth depth-scaled
  bonus salvage — any destruction counts (mining, drill, charges, fauna
  chewing).
- **M7 — this PR** — quest system: each depth rolls its mini quest from a
  shuffled bag (depth 1 always teaches crate recovery; deeper depths mix in
  the first two new types: survive the swarm, hunt the beast — a leashed
  alpha lurker tracked by sonar pings and a HUD bearing); completing the
  quest drops the bell; day counter persists at the station ("Day N").
- **M7b — planned** — quest pack 2: repair & defend, escort the payload.
- **M8 — planned** — boss lairs every 5th depth with a dedicated boss, and
  buyable start-depth checkpoints (winch refit) sold at the station after
  a lair is cleared.
- **M9 — planned** — the submarine: walkable interior homebase that doubles
  as the multiplayer lobby (stash, upgrade console, diver locker, hatch).

## Backlog (post-M6)

### Content

- Terrain follow-ups: rooms/wreck structures (not just noise caves), enemy
  dig variety (burrowers that tunnel toward you).
- More evolutions (drone/sonar/cutter/drill have none yet); more boss
  varieties beyond the first lair guardian (M8).

### Feel/polish pass

- Hit flashes and knockback on enemies, death poofs, damage numbers.
- Screen shake (depth charge, going down, extraction).
- Sound: ambient pressure drone, sonar pings, weapon/impact SFX, muffled
  underwater mix; music that intensifies with depth.
- Better sprites + animation frames (idle/swim), parallax debris layers,
  bubble particles, boot splash/title art.
- Minimap or off-screen objective arrows (crates/bell).

### Infra

- Deploy signaling broker to the team k8s cluster (`wss://`), set
  `ALLOWED_ORIGINS` and `network/signaling/url`.
- TURN server if strict-NAT players report connection failures.
