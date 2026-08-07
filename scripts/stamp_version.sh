#!/usr/bin/env bash
#
# Stamp a release version into the build workspace. Used by the Release workflow
# before every export so the artifact reports its real version.
#
# Deliberately NOT committed back to the repo. Every merge to main is a release,
# so a hand-maintained version field would need bumping in a commit that is itself
# a release — and pushing that back to a protected branch from CI is exactly the
# kind of loop that breaks. The committed values stay at "-dev"; CI overwrites them
# in the workspace only.
#
# Usage: scripts/stamp_version.sh 0.1.42
set -euo pipefail

version="${1:?usage: stamp_version.sh <version>}"

# project.godot: shown on the title screen, so a player can report what they run.
sed -i.bak "s|^config/version=.*|config/version=\"${version}\"|" project.godot
rm -f project.godot.bak

# package.json: the hub logs this at startup, so a deployed container can be
# identified without shelling into it.
node -e '
const fs = require("fs");
const p = "signaling/package.json";
const j = JSON.parse(fs.readFileSync(p, "utf8"));
j.version = process.argv[1];
fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
' "$version"

echo "stamped $version"
grep '^config/version=' project.godot
node -p "'signaling/package.json -> ' + require('./signaling/package.json').version"
