#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Codex Token Meter.app"
BIN="$APP/Contents/MacOS/CodexTokenMeter"
MODULE_CACHE="$BUILD_DIR/ModuleCache"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$MODULE_CACHE"

if [[ "${REGENERATE_ASSETS:-0}" == "1" ]]; then
  swift "$ROOT/Tools/make_logo.swift" "$ROOT"
fi

swiftc \
  -O \
  -module-cache-path "$MODULE_CACHE" \
  -framework Cocoa \
  -framework UserNotifications \
  "$ROOT"/Sources/CodexTokenMeter/*.swift \
  -o "$BIN"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/LogoHeader.png" "$APP/Contents/Resources/LogoHeader.png"
cp "$ROOT/Resources/StatusIconTemplate.png" "$APP/Contents/Resources/StatusIconTemplate.png"

echo "$APP"
