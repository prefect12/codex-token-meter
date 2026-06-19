#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Codex Token Meter.app"
BIN="$APP/Contents/MacOS/CodexTokenMeter"
SWIFT_SOURCES=()

while IFS= read -r source; do
  SWIFT_SOURCES+=("$source")
done < <(find "$ROOT/Sources/CodexTokenMeter" -name '*.swift' -print | sort)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${REGENERATE_ASSETS:-0}" == "1" ]]; then
  swift "$ROOT/Tools/make_logo.swift" "$ROOT"
fi

swiftc \
  -O \
  -framework Cocoa \
  -framework UserNotifications \
  "${SWIFT_SOURCES[@]}" \
  -o "$BIN"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/LogoHeader.png" "$APP/Contents/Resources/LogoHeader.png"
cp "$ROOT/Resources/StatusIconTemplate.png" "$APP/Contents/Resources/StatusIconTemplate.png"

echo "$APP"
