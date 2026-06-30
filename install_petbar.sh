#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Codex Pet Bar.app"
DEST="/Applications/Codex Pet Bar.app"

"$ROOT/build_petbar.sh" >/dev/null

osascript -e 'tell application "Codex Pet Bar" to quit' >/dev/null 2>&1 || true
sleep 0.2
pkill -x CodexPetBar >/dev/null 2>&1 || true
sleep 0.2

rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"

echo "$DEST"
