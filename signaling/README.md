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

## Peers behind one NAT need a TURN relay

The hub only brokers the handshake. Whether the peers can then reach each other
is a separate question, and for two browsers behind the SAME NAT the answer is no
— measured, not assumed:

```
peer 2: gathering=2 out=host:1,srflx:1 in=host:1,srflx:1  conn=1 (forever)
```

Signalling completed, candidates crossed both ways, gathering finished, and no
pair connected. Both candidate types were on offer and neither worked:

- **host** — Chrome replaces the local address with a random `<uuid>.local`
  **mDNS** name for privacy. If the other peer can't resolve that name over
  multicast, the pair is unusable. Desktop builds don't hit this: they offer a
  real IP.
- **srflx** — STUN only reveals a peer's *public* address. Two peers behind one
  NAT would have to reach each other through it, which needs the router to
  **hairpin**, and most don't.

Neither is fixable from the game: mDNS obfuscation is a browser privacy feature,
hairpinning belongs to the router. A relay removes the need for a direct path.

Scope this honestly. The failure above is the *same-NAT* case, which is also what
every same-machine two-window test is — so local testing will keep failing no
matter what the code does, and that is not a regression. Peers on **different**
networks need no hairpinning and pair srflx-to-srflx, which succeeds for most peer
pairs, so cross-network play may work with no relay at all. A relay is what covers
the remaining tail: CGNAT, symmetric NAT, and networks that block UDP outright.
Test with someone on another network before deciding how urgently you need one.

Deploy [coturn](https://github.com/coturn/coturn) beside the hub, then add it to
the `network/signaling/ice_servers` project setting alongside the STUN entry:

```json
[{"urls": ["stun:stun.l.google.com:19302"]},
 {"urls": ["turn:turn.j6n.dev:3478"], "username": "…", "credential": "…"}]
```

The client already reads TURN entries from that setting (`SignalingClient.ice_servers`),
so this is deployment and configuration only — no code change.

Two things to keep in mind. **The credentials are public**: any browser client can
read them out of the exported build, so rate-limit the relay or hand out
short-lived credentials rather than treating them as a secret. And **relayed
traffic costs bandwidth** — unlike the handshake, game packets flow through the
relay for peers that need it, so size it accordingly.

To tell whether a deployed relay is actually being used, look for `relay` in the
candidate types the client logs. If `relay` never appears, the game never reached
the TURN server (wrong port, blocked UDP, or bad credentials) — and the log line
naming the types is there precisely so that is answerable.
