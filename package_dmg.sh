#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Codex Token Meter.app"
DIST="$ROOT/dist"
STAGE="$ROOT/build/dmg-stage"
DMG="$DIST/Codex-Token-Meter-0.1.8.dmg"

"$ROOT/build.sh" >/dev/null

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

codesign --force --deep --sign - "$STAGE/Codex Token Meter.app"
rm -f "$DMG"
hdiutil create -volname "Codex Token Meter" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"

echo "$DMG"
