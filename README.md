# Abyssal Salvage (working title)

A 2D pixel-art, multiplayer (1–4 player co-op) horde-survival roguelike built
with **Godot 4.6.3**. A dive crew drops into an ocean trench, fights off
swarms of abyssal creatures Vampire-Survivors-style, recovers salvage, and
extracts via the dive bell before the oxygen runs out.

**Play the latest main build in your browser:**
<https://ctrl-research.github.io/rogue-like/>

See [docs/game-design.md](docs/game-design.md) for the full design and
milestone plan.

## Controls

- **WASD / arrow keys** — move. Your harpoon gun fires itself at the nearest
  threat; your job is positioning.
- Collect **biomass gems** for team levels, grab all **salvage crates**, then
  hold the **dive bell** to extract.

## Running locally

Install Godot **4.6.3** (see `.tool-versions`), then:

```sh
godot --path .            # run the game
godot --path . --editor   # open the editor
```

## Multiplayer

- **Solo** works everywhere, including the browser build.
- **Online co-op (2–4, WebRTC room codes)** — works in the browser and on
  desktop. The host clicks HOST ONLINE and shares the 5-letter room code (on
  web, a `#room=CODE` invite link that auto-joins). Game traffic is
  peer-to-peer; a tiny signaling broker (`signaling/`) only sets up the
  connection. Production hub: `wss://lobby.j6n.dev` (the
  `network/signaling/url` project setting; override locally with the
  `SIGNALING_URL` env var, e.g. `ws://localhost:9080` with `node
  signaling/server.js` running). Desktop builds additionally need the
  webrtc-native extension: `scripts/fetch_webrtc.sh`.
- **Direct connect (desktop)** — HOST LAN / JOIN LAN, ENet on UDP 7777, no
  signalling hub and no relay involved. Works on a LAN as-is; over the internet
  the host forwards UDP 7777 and shares their public address. **Only the host
  needs to be reachable**, which is why this works for a player on mobile data or
  CGNAT when peer-to-peer does not — see below.

### Why the browser build needs a relay and desktop does not

Measured, not assumed:

| Peers | Result |
| --- | --- |
| Two browsers behind one NAT | fails — needs router hairpinning, and Chrome hides host candidates behind mDNS |
| Browser on home broadband to browser on mobile data | fails — mobile is CGNAT, so the address STUN reports is not reachable |
| Two desktop clients on one LAN | works — real local IPs, no traversal at all |
| Desktop direct connect, host port-forwarded | works — outbound always works from behind CGNAT |

Peer-to-peer needs **both** sides traversable; direct connect needs only one.
A TURN relay exists to be that one reachable endpoint, which is why the browser
build needs one (a browser cannot listen for connections) and a forwarded desktop
host does not. See `signaling/README.md` for the relay setup.

## CI / deployment

`.github/workflows/build.yml` exports the web build on every PR (validating
that scripts compile and the export succeeds) and deploys `main` to GitHub
Pages. The web export has thread support disabled, so it runs on Pages
without cross-origin-isolation headers.

Every PR also runs two gameplay tests headlessly:

- `tests/headless_sim.tscn` — a solo self-playing bot (kites, collects gems,
  auto-picks upgrades).
- `scripts/e2e_webrtc.sh` — a real two-instance WebRTC session through the
  actual signaling broker, verifying spawn + replication on both sides.

`desktop.yml` exports macOS (universal) and Windows (x86_64) builds, uploads them
as workflow artifacts, and attaches them to a GitHub release on a `v*` tag. It is
a separate workflow so desktop exports cannot slow down or destabilise the checks
that gate merges. Unlike `build.yml`, it treats the webrtc-native extension as
**required** and fails if it is missing — a desktop build without it silently
loses online play, and it also asserts the framework actually made it into the
macOS bundle.

`signaling-image.yml` publishes the broker container to GHCR on merges that
touch `signaling/`.

## Releases

**Every merge to main is a release.** Desktop binaries, a self-contained web
bundle, and a versioned signalling image, all built from the same commit by
`release.yml`.

The version is **derived, not committed**: `MAJOR.MINOR` comes from `./VERSION`
and the patch is the commit count on main, so `0.1.114` is the 114th commit of the
`0.1` line. Nothing is bumped by hand — a release commit that itself needs a
version-bump commit is a loop, and pushing to a protected branch from CI to close
it is worse. `scripts/stamp_version.sh` writes the real version into
`project.godot` and `signaling/package.json` **in the build workspace only**; the
committed values stay at `-dev`, which is what you see running from source.

Tags are created by the release itself (`gh release create --target`), which is a
tag write rather than a branch write, so branch protection is untouched.

To bump `MINOR`, edit `./VERSION` in a normal PR. Releases are marked
**prerelease** until there is a reason not to.

| Artifact | Where |
| --- | --- |
| macOS `.zip` + Windows `.exe` | GitHub release |
| Self-contained web bundle `.zip` | GitHub release |
| `ghcr.io/<repo>/signaling:<version>` and `:latest` | GHCR |

Pin the versioned image tag in a deployment rather than chasing `:latest`, so a
client and hub of known-compatible versions stay together.

`workflow_dispatch` on Release is a dry run: everything builds and gets verified,
nothing publishes. Same if a rerun lands on a commit that was already released.

**Desktop builds do not run on pull requests** — they take a few minutes and
produce ~165MB, which is wasted per-PR when the artifact is only wanted for a
release. The trade-off is that a broken export preset surfaces on the next merge
rather than on the PR; `build.yml` still checks on every PR that scripts compile
and that an export succeeds.

## Desktop builds

Grab them from the workflow artifacts (or a release, on tagged builds). **Both are
unsigned**, so the OS warns on first launch:

- **macOS** — unzip, then right-click the app and choose *Open*, or
  `xattr -dr com.apple.quarantine AbyssalSalvage.app`. Double-clicking normally
  will be refused.
- **Windows** — SmartScreen warns; *More info* then *Run anyway*. The `.pck` is
  embedded, so it is a single `.exe`.

Signing would remove the warnings but needs an Apple Developer account and a
Windows code-signing certificate; neither is worth it for a hobby build.

## Placeholder art

Sprites in `assets/sprites/` are generated by `tools/gen_pixel_art.py`
(stdlib-only Python). Edit the ASCII grids in that script and rerun it to
tweak art.
