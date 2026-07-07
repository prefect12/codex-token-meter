#!/usr/bin/env bash
set -euo pipefail

APP="${1:-$HOME/Applications/Codex API.app}"
INFO="$APP/Contents/Info.plist"

if [[ ! -f "$INFO" ]]; then
  echo "Codex API Info.plist not found: $INFO" >&2
  exit 1
fi

BACKUP="$INFO.backup-$(date +%Y%m%d-%H%M%S)"
cp -p "$INFO" "$BACKUP"

# Codex API should own codex-api: only. Plain codex: belongs to Codex.app.
/usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes:0:CFBundleURLSchemes' "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$INFO"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string codex-api' "$INFO"

plutil -lint "$INFO" >/dev/null
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$APP" >/dev/null 2>&1

swift -e 'import Foundation; import CoreServices; _ = LSSetDefaultHandlerForURLScheme("codex" as NSString, "com.openai.codex" as NSString); _ = LSSetDefaultHandlerForURLScheme("codex-api" as NSString, "com.openai.codex.api.local" as NSString)'

echo "Repaired Codex API split. Backup: $BACKUP"
