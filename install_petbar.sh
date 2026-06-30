#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Codex Bar.app"
DEST="/Applications/Codex Bar.app"
OLD_DEST="/Applications/Codex Pet Bar.app"

"$ROOT/build_petbar.sh" >/dev/null

osascript -e 'tell application "Codex Bar" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Codex Pet Bar" to quit' >/dev/null 2>&1 || true
sleep 0.2
pkill -x CodexBar >/dev/null 2>&1 || true
pkill -x CodexPetBar >/dev/null 2>&1 || true
sleep 0.2

rm -rf "$DEST"
rm -rf "$OLD_DEST"
cp -R "$APP" "$DEST"
open "$DEST"

echo "$DEST"
