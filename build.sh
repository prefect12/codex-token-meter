#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/AI Token Meter.app"
BIN="$APP/Contents/MacOS/CodexTokenMeter"
SWIFT_SOURCES=()

while IFS= read -r source; do
  SWIFT_SOURCES+=("$source")
done < <(find "$ROOT/Sources/CodexTokenMeter" -name '*.swift' -print | sort)

rm -rf "$BUILD_DIR/Codex Token Meter.app" "$BUILD_DIR/AI Token Meter.app"
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
/usr/libexec/PlistBuddy -c "Set :CodexBuildGitBranch $(git -C "$ROOT" branch --show-current 2>/dev/null || echo unknown)" "$APP/Contents/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Add :CodexBuildGitBranch string $(git -C "$ROOT" branch --show-current 2>/dev/null || echo unknown)" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CodexBuildGitCommit $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)" "$APP/Contents/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Add :CodexBuildGitCommit string $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CodexBuildGitDescribe $(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)" "$APP/Contents/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Add :CodexBuildGitDescribe string $(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CodexBuildTimestamp $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$APP/Contents/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Add :CodexBuildTimestamp string $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$APP/Contents/Info.plist" >/dev/null
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/LogoHeader.png" "$APP/Contents/Resources/LogoHeader.png"
cp "$ROOT/Resources/StatusIconTemplate.png" "$APP/Contents/Resources/StatusIconTemplate.png"

# TCC associates protected-folder grants with the app's signing requirement.
# An unsigned development bundle receives a fresh ad-hoc CDHash after every
# Swift build, so macOS asks for Documents access again. Use the same local
# development identity as install.sh when it is available. Other contributors
# can still build without it, but get an explicit warning instead of a false
# expectation that the grant will persist.
SIGNING_IDENTITY="${AI_TOKEN_METER_SIGNING_IDENTITY:-AudioWhisperDev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$SIGNING_IDENTITY\""; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
else
  echo "warning: no stable signing identity '$SIGNING_IDENTITY'; macOS may request protected-folder access after each rebuild" >&2
fi

echo "$APP"
