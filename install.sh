#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Codex Token Meter.app"
DEST="/Applications/Codex Token Meter.app"

"$ROOT/build.sh" >/dev/null
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"

echo "$DEST"
