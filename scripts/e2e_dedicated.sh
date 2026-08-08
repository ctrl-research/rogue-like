#!/usr/bin/env bash
#
# Dedicated-server end-to-end test: one headless server with NO diver of its own,
# plus two headless divers that join it, see each other in the sub, and dive.
#
# Covers what the WebRTC e2e cannot — that the server is not a player. See
# tests/e2e_dedicated.gd for which specific mistakes each assertion catches.
#
# Usage: GODOT=/path/to/godot scripts/e2e_dedicated.sh
# Requires no broker, no extension and no network: WebSocket over loopback.
set -uo pipefail

GODOT="${GODOT:-./godot}"
OUT_DIR="${OUT_DIR:-/tmp/e2e_dedicated}"
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.log

# GNU timeout is absent on stock macOS; fall back to perl's alarm.
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
with_timeout() {
  local secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$secs" "$@"; else
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
  fi
}

cleanup() {
  for pid in ${FOLLOWER_PID:-} ${LEAD_PID:-} ${SERVER_PID:-}; do
    kill "$pid" 2>/dev/null
  done
  wait 2>/dev/null
}
trap cleanup EXIT

echo "--- starting dedicated server"
# --dedicated goes after `--` so it lands in OS.get_cmdline_user_args(), which is
# exactly how the container invokes it.
# JOIN_PASSWORD makes the happy path exercise authentication rather than only the
# open-server case. It must match PASSWORD in tests/e2e_dedicated.gd.
JOIN_PASSWORD=correct-horse E2E_ROLE=server with_timeout 150 "$GODOT" --headless --path . \
  tests/e2e_dedicated.tscn -- --dedicated > "$OUT_DIR/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 30); do
  grep -q "listening on ws" "$OUT_DIR/server.log" 2>/dev/null && break
  sleep 1
done
if ! grep -q "listening on ws" "$OUT_DIR/server.log" 2>/dev/null; then
  echo "server never started listening:"; cat "$OUT_DIR/server.log"; exit 1
fi
echo "--- server is listening; starting two divers"

E2E_ROLE=lead with_timeout 120 "$GODOT" --headless --path . tests/e2e_dedicated.tscn \
  > "$OUT_DIR/lead.log" 2>&1 &
LEAD_PID=$!
sleep 2
E2E_ROLE=follower with_timeout 120 "$GODOT" --headless --path . tests/e2e_dedicated.tscn \
  > "$OUT_DIR/follower.log" 2>&1 &
FOLLOWER_PID=$!

# An intruder with the wrong password must be refused. Run it while the crew is
# aboard, so a refusal cannot be confused with the server being unreachable.
echo "--- starting an intruder with the wrong password"
E2E_ROLE=intruder with_timeout 60 "$GODOT" --headless --path . tests/e2e_dedicated.tscn \
  > "$OUT_DIR/intruder.log" 2>&1 || true

wait "$LEAD_PID" 2>/dev/null; LEAD_PID=""
wait "$FOLLOWER_PID" 2>/dev/null; FOLLOWER_PID=""
wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""

for role in server lead follower intruder; do
  echo "--- $role log ---"; cat "$OUT_DIR/$role.log"
done

FAIL=0
need() { grep -q "$1" "$OUT_DIR/$2.log" || { echo "MISSING $1"; FAIL=1; }; }
need "E2E_SERVER_LOBBY_OK"   server
need "E2E_SERVER_OK"         server
need "E2E_LEAD_LOBBY_OK"     lead
need "E2E_LEAD_OK"           lead
need "E2E_FOLLOWER_LOBBY_OK" follower
need "E2E_FOLLOWER_OK"       follower
# The security-critical assertion: a wrong password does not get in.
need "E2E_INTRUDER_REFUSED"  intruder
# The bell decision must be reachable by a DIVER. Gated on is_server() it appeared
# for nobody on a dedicated server and the run auto-extracted itself.
need "E2E_SERVER_CHOICE_OK"   server
need "E2E_LEAD_CHOICE_OK"     lead
need "E2E_FOLLOWER_CHOICE_OK" follower
# And it must never have been seated. Godot drops an unauthenticated peer before it
# counts as connected, so this greps for any sign it got further than the door.
if grep -qE "E2E_INTRUDER_(LOBBY_)?OK" "$OUT_DIR/intruder.log" 2>/dev/null; then
  echo "INTRUDER WAS ADMITTED — authentication is not working"; FAIL=1
fi

if grep -h "E2E_DEDICATED_FAIL" "$OUT_DIR"/*.log; then
  echo "a role reported a failure (see above)"; FAIL=1
fi
# Script and replication errors mean sync is silently broken even when the smoke
# markers pass.
if grep -hnE "SCRIPT ERROR|Parse Error|Failed to get cached node|Ignoring sync data" \
    "$OUT_DIR"/*.log; then
  echo "script or replication errors detected (see above)"; FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then echo "E2E_DEDICATED_FAILED"; exit 1; fi
echo "E2E_DEDICATED_PASSED"
