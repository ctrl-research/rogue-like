# Signaling hub

Tiny WebSocket broker that sets up WebRTC connections between players (the
offer/answer/ICE handshake), then steps aside — all game traffic flows
peer-to-peer and never touches this server. Vendored from the `fps` project;
the protocol matches Godot's official `webrtc_signaling` demo, extended with
a per-game namespace (`game` field on join) so one hub can serve multiple
games without room codes colliding. Production endpoint: `wss://lobby.j6n.dev`
(game id for this project: `abyssal`).

Protocol, limits, and abuse guards are documented at the top of `server.js`.
Everything is env-tunable (`PORT`, `MAX_PEERS`, `ALLOWED_ORIGINS`, ...).

## Run locally (for development and the e2e test)

```sh
node server.js        # listens on ws://localhost:9080
```

No install needed — `ws` is the only dependency and is vendored via the
lockfile; run `npm ci` once if `node_modules` is missing.

## Deploy

CI publishes a container image to GHCR on every merge that touches
`signaling/` (see `.github/workflows/signaling-image.yml`):

```
ghcr.io/ctrl-research/rogue-like/signaling:latest
```

Run it behind a TLS-terminating reverse proxy (Caddy, or any platform that
gives you HTTPS ingress — Fly.io, Cloud Run, a VPS) so browsers can reach it
over `wss://`. The Pages site is HTTPS, so plain `ws://` will be blocked as
mixed content. Set `ALLOWED_ORIGINS=https://ctrl-research.github.io` in
production, then point the game at the broker via the
`network/signaling/url` project setting.

Health check: plain HTTP `GET /health` returns `200 ok`.

## A TURN relay is required

The hub only brokers the handshake. Whether the peers can then reach each other is
a separate question, and the answer is measured, not assumed:

| Peers | Result |
| --- | --- |
| Two browsers behind one NAT | **fails** — needs router hairpinning, and Chrome hides host candidates behind mDNS |
| Home broadband to mobile data | **fails** — mobile is CGNAT, so the address STUN reports is not reachable |
| Two desktop clients on one LAN | works (real local IPs, no traversal at all) |

Both browser cases fail, so a relay is required rather than a nice-to-have. The
diagnostic in the client log is the line that says candidates were exchanged and
gathering completed but no pair connected.

Deploy [coturn](https://github.com/coturn/coturn) beside the hub. The hub then
hands each joining client a relay in its `id` message, so **nothing about the
relay ships in the game build**:

```
TURN_URLS=turn:turn.example:3478,turns:turn.example:5349
TURN_SECRET=<the same string as coturn's static-auth-secret>
TURN_TTL_SEC=28800         # optional, default 8h
STUN_URLS=stun:...         # optional, defaults to Google's
```

and in coturn:

```
use-auth-secret
static-auth-secret=<the same string as TURN_SECRET>
realm=turn.example
```

**Credentials are minted per join and expire**, because a relay credential cannot
be a secret in a browser game: everything in an exported web build is readable by
whoever opens it. The hub issues a username of `<expiry>:<random tag>` with the
password being its HMAC under `TURN_SECRET`, which coturn validates using the same
secret and no user database — the TURN REST API scheme
(`draft-uberti-behave-turn-rest-00`). `TURN_SECRET` never leaves the hub.
`signaling/ice_test.js` (which needs no `npm install`) pins the HMAC to a fixed vector, because getting it wrong
fails invisibly: the relay refuses every allocation and the game looks exactly as
it did with no relay at all.

The random tag gives each peer a distinct TURN username, so coturn's `user-quota`
applies per peer rather than to everyone who joined in the same TTL window.

Leave `TURN_SECRET` unset and the hub advertises no relay; clients fall back to
their own `network/signaling/ice_servers` project setting. When the hub does send a
list it wins, which is the point — relay configuration then lives in one place
instead of in every shipped build.

### Lock coturn down before exposing it

coturn relays to **any** destination by default, including private address space.
Reachable from the internet and sitting inside a private network, that makes it a
proxy into everything around it — the Kubernetes API, dashboards, databases. This
is the setting people miss, and it turns "someone is using my bandwidth" into
"someone is scanning my cluster":

```
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255   # link-local / cloud metadata
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
no-multicast-peers
no-cli
user-quota=12
total-quota=1200
```

Relayed traffic is also doubled and continuous for as long as a dive lasts, unlike
the handshake — so size the bandwidth for concurrent lobbies, not for connection
attempts. Managed TURN (Cloudflare Calls, Twilio, Metered) avoids both the
internal-pivot risk and exposing a home IP, at a per-GB cost.

### Checking a deployed relay is actually used

Look for `relay` in the candidate types the client logs each join, and for the
`hub offered N ice server(s), M relay` line it prints on connect. If `relay` never
appears in the candidates, the game never reached coturn — wrong port, blocked
UDP, or a credential mismatch — which is a different failure from having no route,
and needs a different fix.
