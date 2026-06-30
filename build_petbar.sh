#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Codex Bar.app"
OLD_APP="$BUILD_DIR/Codex Pet Bar.app"
BIN="$APP/Contents/MacOS/CodexBar"
SWIFT_SOURCES=()

while IFS= read -r source; do
  SWIFT_SOURCES+=("$source")
done < <(find "$ROOT/Sources/CodexPetBar" -name '*.swift' -print | sort)

rm -rf "$APP" "$OLD_APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
  -O \
  -framework Cocoa \
  "${SWIFT_SOURCES[@]}" \
  -o "$BIN"

cp "$ROOT/Info-CodexPetBar.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/CodexBarAppIcon.icns" ]]; then
  cp "$ROOT/Resources/CodexBarAppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
elif [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "$APP"
