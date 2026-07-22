#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Task Bar.app"
DIST="$ROOT/dist"
STAGE="$ROOT/build/taskbar-dmg-stage"
CREATE_DMG="$ROOT/Tools/create-dmg/create-dmg"
BACKGROUND="$ROOT/Resources/DMG/installer-background-light-extra-tall.png"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info-CodexPetBar.plist")"
DMG="$DIST/Task-Bar-$VERSION.dmg"

"$ROOT/build_petbar.sh" >/dev/null

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/"
cat > "$STAGE/首次打开说明.md" <<'EOF'
# Task Bar 安装说明

1. 请将 `Task Bar.app` 拖到 `Applications` 文件夹。
2. 从“应用程序”打开 Task Bar。

## 隐私承诺

- Task Bar 只在本机读取任务状态和保存应用设置，**不会上传任务标题、提示词、代码、会话记录、日志文件或用量数据**。
- 应用不包含遥测、广告或用户行为追踪 SDK，也不会把数据发送给开发者或第三方统计平台。

## 如果 macOS 阻止打开

该版本未使用 Apple Developer ID 签名。请只在确认安装包来自可信来源时按下面步骤允许：

1. 先尝试打开一次 Task Bar，然后在系统提示中选择“取消”。
2. 打开“系统设置” → “隐私与安全性”。
3. 在页面底部找到 Task Bar 的拦截提示，点击“仍要打开”。
4. 在确认对话框中再次点击“打开”。

也可以在 Finder 中按住 Control 键点按 Task Bar，选择“打开”，然后在确认对话框中选择“打开”。

请勿关闭 macOS 的安全保护，也不要运行来源不明的终端绕过命令。
EOF

codesign --force --deep --sign "AudioWhisperDev" "$STAGE/Task Bar.app"
"$CREATE_DMG" \
  --volname "Task Bar" \
  --background "$BACKGROUND" \
  --window-pos 200 120 \
  --window-size 600 560 \
  --icon-size 96 \
  --text-size 13 \
  --icon "Task Bar.app" 134 180 \
  --icon "首次打开说明.md" 300 370 \
  --hide-extension "首次打开说明.md" \
  --app-drop-link 466 180 \
  --no-internet-enable \
  --overwrite \
  "$DMG" "$STAGE"
hdiutil verify "$DMG"

echo "$DMG"
