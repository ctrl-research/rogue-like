#!/usr/bin/env bash
#
# WebRTC end-to-end test: starts the signaling broker, then a headless host
# and client Godot instance that form a real WebRTC room and verify that both
# players spawn and enemies replicate.
#
# Usage: GODOT=/path/to/godot scripts/e2e_webrtc.sh
# Requires: node, the webrtc-native GDExtension (scripts/fetch_webrtc.sh).
set -uo pipefail

GODOT="${GODOT:-./godot}"
OUT_DIR="${OUT_DIR:-/tmp/e2e_webrtc}"
mkdir -p "$OUT_DIR"

# Always test against the local broker, not the production endpoint that the
# project setting points at.
export SIGNALING_URL="ws://localhost:9080"

# GNU timeout is absent on stock macOS; fall back to perl's alarm.
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
with_timeout() {
  local secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$secs" "$@"
  else
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
  fi
}

if [ ! -d addons/webrtc ]; then
  echo "ERROR: addons/webrtc missing — run scripts/fetch_webrtc.sh first." >&2
  exit 1
fi

cleanup() {
  [ -n "${CLIENT_PID:-}" ] && kill "$CLIENT_PID" 2>/dev/null
  [ -n "${HOST_PID:-}" ] && kill "$HOST_PID" 2>/dev/null
  [ -n "${BROKER_PID:-}" ] && kill "$BROKER_PID" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT

if [ ! -d signaling/node_modules ]; then
  echo "--- installing broker dependencies"
  (cd signaling && npm ci --omit=dev)
fi

echo "--- starting signaling broker"
node signaling/server.js > "$OUT_DIR/broker.log" 2>&1 &
BROKER_PID=$!
sleep 1
kill -0 "$BROKER_PID" 2>/dev/null || { echo "broker failed to start"; cat "$OUT_DIR/broker.log"; exit 1; }

echo "--- starting host instance"
with_timeout 150 "$GODOT" --headless --path . tests/e2e_host.tscn > "$OUT_DIR/host.log" 2>&1 &
HOST_PID=$!

CODE=""
for _ in $(seq 1 30); do
  CODE="$(grep -oE 'E2E_ROOM=[A-Z0-9]+' "$OUT_DIR/host.log" 2>/dev/null | head -1 | cut -d= -f2 || true)"
  [ -n "$CODE" ] && break
  sleep 1
done
if [ -z "$CODE" ]; then
  echo "host never created a room:"; cat "$OUT_DIR/host.log"; exit 1
fi
echo "--- host created room $CODE; starting client"

E2E_ROOM="$CODE" with_timeout 120 "$GODOT" --headless --path . tests/e2e_client.tscn > "$OUT_DIR/client.log" 2>&1
CLIENT_PID=""
wait "$HOST_PID" 2>/dev/null
HOST_PID=""

echo "--- host log ---";   cat "$OUT_DIR/host.log"
echo "--- client log ---"; cat "$OUT_DIR/client.log"

FAIL=0
grep -q "E2E_HOST_OK" "$OUT_DIR/host.log"             || { echo "MISSING E2E_HOST_OK"; FAIL=1; }
grep -q "E2E_CLIENT_OK" "$OUT_DIR/client.log"         || { echo "MISSING E2E_CLIENT_OK"; FAIL=1; }
grep -q "E2E_HOST_RETRY_OK" "$OUT_DIR/host.log"       || { echo "MISSING E2E_HOST_RETRY_OK"; FAIL=1; }
grep -q "E2E_KIT_OK" "$OUT_DIR/host.log"              || { echo "MISSING E2E_KIT_OK"; FAIL=1; }
# Terrain must be byte-identical on both peers (built from the same seed).
HC="$(grep -oE 'terrain_cells=[0-9]+' "$OUT_DIR/host.log" | head -1 | cut -d= -f2)"
CC="$(grep -oE 'terrain_cells=[0-9]+' "$OUT_DIR/client.log" | head -1 | cut -d= -f2)"
if [ -z "$HC" ] || [ "$HC" = "0" ] || [ "$HC" != "$CC" ]; then
  echo "TERRAIN FINGERPRINT MISMATCH: host=$HC client=$CC"; FAIL=1
fi
# Same for the ore seams scattered through it.
HO="$(grep -oE 'ore_cells=[0-9]+' "$OUT_DIR/host.log" | head -1 | cut -d= -f2)"
CO="$(grep -oE 'ore_cells=[0-9]+' "$OUT_DIR/client.log" | head -1 | cut -d= -f2)"
if [ -z "$HO" ] || [ "$HO" = "0" ] || [ "$HO" != "$CO" ]; then
  echo "ORE FINGERPRINT MISMATCH: host=$HO client=$CO"; FAIL=1
fi
grep -q "E2E_CLIENT_RETRY_OK" "$OUT_DIR/client.log"   || { echo "MISSING E2E_CLIENT_RETRY_OK"; FAIL=1; }
# Script and replication errors mean sync is silently broken even if the
# smoke markers pass — treat them as failures. "Failed to get cached node" and
# "Ignoring sync data" are how Godot reports traffic aimed at a node the peer
# no longer has (a scene transition leaking sync); they name neither
# "replication" nor "MultiplayerSynchronizer", so match them explicitly.
if grep -nE "SCRIPT ERROR|MultiplayerSynchronizer|replication|Failed to get cached node|Ignoring sync data" \
    "$OUT_DIR/host.log" "$OUT_DIR/client.log"; then
  echo "script/replication errors detected (see above)"; FAIL=1
fi
if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "--- WebRTC e2e passed"
