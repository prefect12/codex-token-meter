#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Task Bar.app"
DEST="/Applications/Task Bar.app"
OLD_DEST="/Applications/Codex Bar.app"
OLDER_DEST="/Applications/Codex Pet Bar.app"

"$ROOT/build_petbar.sh" >/dev/null

osascript -e 'tell application "Task Bar" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Codex Bar" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Codex Pet Bar" to quit' >/dev/null 2>&1 || true
sleep 0.2
pkill -x TaskBar >/dev/null 2>&1 || true
pkill -x CodexBar >/dev/null 2>&1 || true
pkill -x CodexPetBar >/dev/null 2>&1 || true
sleep 0.2

rm -rf "$DEST"
rm -rf "$OLD_DEST"
rm -rf "$OLDER_DEST"
cp -R "$APP" "$DEST"
codesign --force --deep --sign "AudioWhisperDev" "$DEST"
open "$DEST"

echo "$DEST"
