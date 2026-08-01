#!/usr/bin/env bash
#
# Fetch the webrtc-native GDExtension into addons/webrtc/.
#
# This is needed for WebRTC (online) multiplayer in DESKTOP builds and the
# headless e2e test. The web export has WebRTC built in and does NOT need it.
# The game runs fine without it — the online Host/Join buttons are simply
# disabled on desktop — so this is best-effort and never fails the build.
#
# Pin the version with WEBRTC_VERSION (a release tag). Releases:
#   https://github.com/godotengine/webrtc-native/releases
# Note the asset name changed in 1.2.1-stable (godot-extension-webrtc_native.zip,
# previously godot-extension-webrtc.zip).
#
# Usage: WEBRTC_VERSION=1.2.1-stable scripts/fetch_webrtc.sh
set -uo pipefail

WEBRTC_VERSION="${WEBRTC_VERSION:-1.2.1-stable}"
DEST="addons/webrtc"
BASE="https://github.com/godotengine/webrtc-native/releases/download/${WEBRTC_VERSION}"

echo "Fetching webrtc-native ${WEBRTC_VERSION}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ok=0
for asset in godot-extension-webrtc_native.zip godot-extension-webrtc.zip; do
  if curl -fsSL -o "$tmp/webrtc.zip" "${BASE}/${asset}"; then
    echo "  downloaded ${asset}"
    ok=1
    break
  fi
done
if [ "$ok" -ne 1 ]; then
  echo "WARNING: could not download webrtc-native ${WEBRTC_VERSION}." >&2
  echo "         Desktop online (WebRTC) play will be unavailable; web is unaffected." >&2
  echo "         Set WEBRTC_VERSION to a valid release tag from" >&2
  echo "         https://github.com/godotengine/webrtc-native/releases" >&2
  exit 0
fi

unzip -q "$tmp/webrtc.zip" -d "$tmp/extracted"
mkdir -p addons

# Archives have shipped webrtc/, addons/webrtc/, or webrtc_native/ layouts.
src=""
for candidate in "$tmp/extracted/addons/webrtc" "$tmp/extracted/webrtc" \
    "$tmp/extracted/addons/webrtc_native" "$tmp/extracted/webrtc_native"; do
  if [ -d "$candidate" ]; then src="$candidate"; break; fi
done
if [ -z "$src" ]; then
  echo "WARNING: unexpected webrtc-native archive layout; extension not installed." >&2
  echo "         Contents:" >&2
  find "$tmp/extracted" -maxdepth 2 | head -20 >&2
  exit 0
fi

rm -rf "$DEST"
mv "$src" "$DEST"
echo "Installed webrtc-native into ${DEST}/"
