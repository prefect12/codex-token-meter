#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Task Bar.app"
DIST="$ROOT/dist"
STAGE="$ROOT/build/taskbar-dmg-stage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info-CodexPetBar.plist")"
DMG="$DIST/Task-Bar-$VERSION.dmg"

"$ROOT/build_petbar.sh" >/dev/null

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

codesign --force --deep --sign "AudioWhisperDev" "$STAGE/Task Bar.app"
rm -f "$DMG"
hdiutil create -volname "Task Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"

echo "$DMG"
