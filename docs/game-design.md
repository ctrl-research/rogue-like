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
  Ambient light is crushed nearly to black, so what you haven't lit you can't
  really see — fauna included. Vision is **additive across the crew**: 2D
  lighting composites per pixel and every diver's lamp exists on every peer, so
  the crew sees the union of their lamps with no netcode at all, and any new
  light source joins in for free. Anything a quest sends you to find carries a
  marker light, or the objective becomes a search of an unlit room; gems don't,
  because collecting one means your own lamp is already on it.
  The lamp is a **hard-edged banded disc**, not a soft gradient — a radial fade
  reads as an airbrush laid over 16px art, and the project renders 2D with
  nearest filtering so a crisp circle stays crisp at any scale. Note that a hard
  disc emits far more total light than a quadratic falloff of the same energy,
  so lamp energy came *down* when the edge hardened.
  Because "near-black" depends entirely on the display, brightness is a
  **player setting calibrated by eye**: the menu shows patches drawn in the
  game's own unlit-ambient shade and asks the player to set the slider until the
  marked one is barely visible. Neighbouring patches are shown too, since
  judging a single dark patch in isolation is nearly impossible.
  Ambient steps down by a **fixed amount per descent** rather than a fraction of
  a span, and floors instead of reaching black — the same reasoning as lamp
  reach: constant units are something you can weigh against each other.
- **Depth** is a natural difficulty ladder and biome axis. It also **eats the
  light**, as a tug-of-war measured in one unit: lamp reach is a radius in
  pixels, upgrades add to it (+16 per bought Lamp Array level, +24 per in-run
  Arc Lamp) and every descent takes 9 away, floored at 64 so it never goes
  black. Same unit on both sides on purpose — percentages make the two forces
  incomparable, while in pixels the trade reads straight off: one Lamp Array
  level buys back most of two descents. Early depths don't need the upgrades
  and the deep floors can't be worked without them.
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
  physically gathers aboard before diving.
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
  matching gear evolves them (VS-style evolutions). **Every** weapon has an
  evolution, and passives are shared between them on purpose — a passive is a
  build archetype, so committing to magnet opens both the harpoon and drone
  evolutions rather than gating exactly one card.
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

### 2.5D dimensioning

Characters stay flat 2D sprites; the world around them is drawn to read as
solid volume you look down into. Gameplay stays exactly top-down 2D — the
depth is entirely in the rendering, so physics, netcode and the destructible
terrain are untouched by it.

- **Rock is a mass, not tiles.** The top face is seamless (an outline on every
  cell turns a rock field into graph paper). Definition comes from dressing
  layers that rim only the edges actually exposed to open water, plus a darker
  **wall front** in the cell below each southern lip — the value drop across
  that edge is what sells the turn.
- **Growth overhangs the lips**, straddling the edge so the silhouette stops
  following the tile grid. Bioluminescent buds on the longest fronds.
- Dressing is derived from each cell and its neighbours, so it needs no
  replication and cannot desync; peers redress locally after digging.
- The seabed is tileable value noise, not a modulo pattern — a linear function
  under a modulo lays down a regular diagonal lattice, and the tile is large
  (128px) because the arena repeats one tile across 1600px.
- **Contact shadows** sit under divers, fauna and loot, attached at the spawn
  sites so every kind gets one. They're squashed flat and dropped clear of the
  sprite's feet: a taller ellipse hides its own dense middle behind the sprite.
  They read strongest inside lamp light and vanish in the dark, which is both
  correct and free.
- **The water column** carries the parallax. Looking straight down there is
  nothing *behind* the seabed to parallax against, so the volume the eye can
  read is the water above it: two layers of drifting marine snow on a canvas
  layer over the world, scrolling FASTER than it, because things nearer the
  camera sweep further across the view as it pans. A layer moving slower would
  read as beneath the floor, which is nowhere.
- **Depth haze**: ambient light drops and pulls toward the trench's blue-green
  as the crew descends, and a vignette closes in around the edges of vision.
  Depth was already the difficulty axis; now it's the visibility axis too.
  Kept deliberately conservative — the crew still has to see rock to mine it.

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
- **M7b — this PR** — quest pack 2: repair & defend (hold position by a
  wrecked relay while it repairs under elevated spawn pressure — more
  divers on the spot repair faster) and escort the payload (touch to tow;
  the carrier swims at 60% speed and reads as easy prey to fauna, deliver
  to the bell zone at the arena center).
- **M8 — this PR** — boss lairs every 5th depth guarded by the Trench
  Warden (telegraphed rock-smashing charges, summons lurkers, HUD boss
  bar, big bounty), and buyable start-depth checkpoints: clearing a lair
  unlocks the next winch refit at the station (tier N costs 200×N, dives
  may then start at depth 5N+1 — bought progress, not free progress).
- **M9 — done (PR #21)** — the submarine: a walkable interior homebase that IS
  the multiplayer lobby. Solo and crews alike board the sub; divers walk
  around with synced positions and name tags, portholes look out on the
  abyss, and the wall reads the day and crew count. Stations aboard:
  upgrade CONSOLE (upgrades + winch), diver LOCKER, salvage STASH, and
  the DIVE HATCH (lead diver starts the dive; invite link, leave/disband
  live there too). The title screen is now just the connect menu.
- **M9.1 — done (PR #24)** — off-screen objective arrows: edge-pinned markers
  with range, pointing at whatever this depth's quest wants (crates, the
  beast, the relay, the payload, the bell zone, the Warden) and at downed
  crewmates ahead of everything. An arrow hides once its target is on
  camera, which retires the HUD's text compass bearings.
- **M10 — done (PR #26)** — 2.5D terrain spike: seamless rock mass with lit rims
  on exposed sides, a darker wall front under every southern lip, and growth
  overhanging the edge. First slice of the faux-height pivot; shadows (PR #29),
  parallax and haze (PR #30) followed.
- **M11 — this PR** — character customization (issue #37): a name and two
  colours (suit, helmet screen) picked from a full gradient picker, persisted
  with the station save, and visible on the crew standing around the sub — which
  is the lobby preview. The title screen splits into two columns (connecting on
  the left, your diver on the right) rather than overlaying one on the other, and
  the same editor is hosted at a WARDROBE station in the sub so anyone who walked
  past it at boot can still change it mid-campaign. The wardrobe is its own
  station next to the LOCKER — class at one, look at the other — because folding
  the editor into the locker panel overflowed it and cut the second colour off. Recolouring is a palette swap keyed on four tones of the
  sprite's own palette rather than a whole-sprite tint, so the suit and the
  visor change independently and the air tank stays fixed as a common
  reference. A hand-drawn replacement sprite inherits all of this by using the
  same four hexes: see `docs/sprite-palette.md`. Emotes (issue #39) build on
  the same per-peer profile and land next.

- **M12 — this PR** — desktop builds for macOS and Windows. Motivated by
  multiplayer rather than by platform reach: the browser build cannot connect two
  peers behind CGNAT without a relay, while a desktop build can dial a
  port-forwarded host directly on UDP 7777, which needs only ONE side reachable
  and no relay at all. Desktop also keeps online room codes, since the WebRTC
  extension ships a macOS universal framework and a Windows x86_64 dll.

- **M14 — this PR** — the bell's breathing room. Once the diving bell is down, a
  radius around it is safe: monsters cannot enter (and any caught inside when it lands
  are shoved out rather than killed, since something invulnerable and harmless parked
  in the middle of the pause is worse than a shove), divers inside cannot be hurt and
  cannot shoot, and having stepped in they stay until the crew moves on. Marked with a
  pulsing dashed ring drawn from the same constant the movement clamp and the damage
  check use, so the ring cannot lie about where safety ends. Deliberately a pause and
  not a turret post: guns down inside, because monsters cannot come in and shooting out
  would be free damage.

## Backlog (post-M6)

### Content

- Terrain follow-ups: rooms/wreck structures (not just noise caves), enemy
  dig variety (burrowers that tunnel toward you).
- More boss varieties beyond the first lair guardian (M8).

### Feel/polish pass

- Hit flashes and knockback on enemies, death poofs, damage numbers.
- Screen shake (depth charge, going down, extraction).
- Sound: ambient pressure drone, sonar pings, weapon/impact SFX, muffled
  underwater mix; music that intensifies with depth.
- Better sprites + animation frames (idle/swim), parallax debris layers,
  bubble particles, boot splash/title art.
- A minimap, if the edge arrows (M9.1) prove not to be enough.

### Infra

- Deploy signaling broker to the team k8s cluster (`wss://`), set
  `ALLOWED_ORIGINS` and `network/signaling/url`.
- **TURN server — now confirmed necessary, not speculative.** Two browser peers
  complete signalling (offer, answer and ICE candidates all cross, gathering
  reaches complete) and then never connect: `conn=1` forever, no pair usable.
  STUN alone only tells a peer its public address; when both peers sit behind
  the same NAT and the browser hides host candidates behind mDNS, there is no
  route left to try unless the router hairpins, and most don't. A relay is the
  fix. Deploy coturn on the homelab and add it to
  `network/signaling/ice_servers` alongside the STUN entry:
  `[{"urls":["stun:..."]},{"urls":["turn:turn.j6n.dev:3478"],"username":"...","credential":"..."}]`
  — the client already reads TURN entries from that setting, so this is
  deployment and configuration rather than a code change. Note the credentials
  are inherently visible to any browser client, so rate-limit the relay or issue
  short-lived credentials.
