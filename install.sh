#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/AI Token Meter.app"
DEST="/Applications/AI Token Meter.app"
OLD_DEST="/Applications/Codex Token Meter.app"
OLD_FULL_DEST="/Applications/Codex+Claude Token Meter.app"

"$ROOT/build.sh" >/dev/null

osascript -e 'tell application "AI Token Meter" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Token Meter" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Codex Token Meter" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Codex + Claude Token Meter" to quit' >/dev/null 2>&1 || true
sleep 0.5
pkill -x CodexTokenMeter >/dev/null 2>&1 || true
sleep 0.2

rm -rf "$DEST"
rm -rf "$OLD_DEST"
rm -rf "$OLD_FULL_DEST"
cp -R "$APP" "$DEST"
codesign --force --deep --sign "AudioWhisperDev" "$DEST"
open "$DEST"

echo "$DEST"
