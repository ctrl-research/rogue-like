# Signaling broker

Tiny WebSocket broker that sets up WebRTC connections between players (the
offer/answer/ICE handshake), then steps aside — all game traffic flows
peer-to-peer and never touches this server. Vendored from the `fps` project;
the protocol matches Godot's official `webrtc_signaling` demo.

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
