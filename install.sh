#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Codex Token Meter.app"
DEST="/Applications/Codex Token Meter.app"

"$ROOT/build.sh" >/dev/null

osascript -e 'tell application "Token Meter" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Codex Token Meter" to quit' >/dev/null 2>&1 || true
sleep 0.5
pkill -x CodexTokenMeter >/dev/null 2>&1 || true
sleep 0.2

rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"

echo "$DEST"
