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

- **M0 (this PR)** — playable prototype: menu (solo/host/join), one arena,
  2 enemy types, harpoon auto-fire, XP + random level-up boosts, salvage-crate
  objective, dive-bell extraction, oxygen timer, HUD, win/lose. CI → Pages.
- **M1** — level-up choice UI (pick 1 of 3), 2 more weapons + passives,
  downed/revive, enemy scaling by player count polish.
- **M2** — browser multiplayer (WebRTC signaling), lobby UI, player names.
- **M3** — descend-or-extract chain (multi-site dives), depth scaling,
  banked salvage + station upgrades (meta-progression).
- **M4** — procedural wreck layouts, Lurker/Jelly/boss, sound, real art pass.
