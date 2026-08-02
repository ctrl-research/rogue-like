#!/usr/bin/env bash
#
# WebRTC end-to-end test against the PRODUCTION signaling hub: same host +
# client flow as e2e_webrtc.sh, but through wss://lobby.j6n.dev instead of a
# local broker. Proves the deployed hub end-to-end: room creation in the
# game's namespace, seal/unseal, and the post-game retry lobby.
#
# Usage: GODOT=/path/to/godot scripts/e2e_webrtc_prod.sh
set -uo pipefail

GODOT="${GODOT:-./godot}"
OUT_DIR="${OUT_DIR:-/tmp/e2e_webrtc_prod}"
mkdir -p "$OUT_DIR"

export SIGNALING_URL="${SIGNALING_URL:-wss://lobby.j6n.dev}"
echo "--- testing against $SIGNALING_URL"

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
  [ -n "${HOST_PID:-}" ] && kill "$HOST_PID" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT

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
echo "--- host created room $CODE on the production hub; starting client"

E2E_ROOM="$CODE" with_timeout 120 "$GODOT" --headless --path . tests/e2e_client.tscn > "$OUT_DIR/client.log" 2>&1
wait "$HOST_PID" 2>/dev/null
HOST_PID=""

echo "--- host log ---";   cat "$OUT_DIR/host.log"
echo "--- client log ---"; cat "$OUT_DIR/client.log"

FAIL=0
grep -q "E2E_HOST_OK" "$OUT_DIR/host.log"             || { echo "MISSING E2E_HOST_OK"; FAIL=1; }
grep -q "E2E_CLIENT_OK" "$OUT_DIR/client.log"         || { echo "MISSING E2E_CLIENT_OK"; FAIL=1; }
grep -q "E2E_HOST_RETRY_OK" "$OUT_DIR/host.log"       || { echo "MISSING E2E_HOST_RETRY_OK"; FAIL=1; }
grep -q "E2E_CLIENT_RETRY_OK" "$OUT_DIR/client.log"   || { echo "MISSING E2E_CLIENT_RETRY_OK"; FAIL=1; }
if grep -nE "SCRIPT ERROR|MultiplayerSynchronizer|replication" "$OUT_DIR/host.log" "$OUT_DIR/client.log"; then
  echo "script/replication errors detected (see above)"; FAIL=1
fi
if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "--- production e2e passed"
