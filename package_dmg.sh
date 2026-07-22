#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/AI Token Meter.app"
DIST="$ROOT/dist"
STAGE="$ROOT/build/dmg-stage"
CREATE_DMG="$ROOT/Tools/create-dmg/create-dmg"
BACKGROUND="$ROOT/Resources/DMG/installer-background-light-extra-tall.png"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
DMG="$DIST/AI-Token-Meter-$VERSION.dmg"

"$ROOT/build.sh" >/dev/null

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/"
cat > "$STAGE/首次打开说明.md" <<'EOF'
# AI Token Meter 安装说明

1. 请将 `AI Token Meter.app` 拖到 `Applications` 文件夹。
2. 从“应用程序”打开 AI Token Meter。

## 隐私承诺

- Codex 和 Claude Code 的提示词、代码、会话记录、日志文件及 token 明细只在本机读取和计算，**不会上传给开发者，也不会发送到广告或第三方统计平台**。
- 应用不包含遥测、广告或用户行为追踪 SDK。
- 只有在显示实时额度或服务状态时，应用才会直接访问 OpenAI / Anthropic 官方接口；这些请求不会携带本机日志或会话内容。断网后，本地统计仍可正常使用。

## 如果 macOS 阻止打开

该版本未使用 Apple Developer ID 签名。请只在确认安装包来自可信来源时按下面步骤允许：

1. 先尝试打开一次 AI Token Meter，然后在系统提示中选择“取消”。
2. 打开“系统设置” → “隐私与安全性”。
3. 在页面底部找到 AI Token Meter 的拦截提示，点击“仍要打开”。
4. 在确认对话框中再次点击“打开”。

也可以在 Finder 中按住 Control 键点按 AI Token Meter，选择“打开”，然后在确认对话框中选择“打开”。

请勿关闭 macOS 的安全保护，也不要运行来源不明的终端绕过命令。
EOF

codesign --force --deep --sign "AudioWhisperDev" "$STAGE/AI Token Meter.app"
"$CREATE_DMG" \
  --volname "AI Token Meter" \
  --background "$BACKGROUND" \
  --window-pos 200 120 \
  --window-size 600 560 \
  --icon-size 96 \
  --text-size 13 \
  --icon "AI Token Meter.app" 134 180 \
  --icon "首次打开说明.md" 300 370 \
  --hide-extension "首次打开说明.md" \
  --app-drop-link 466 180 \
  --no-internet-enable \
  --overwrite \
  "$DMG" "$STAGE"
hdiutil verify "$DMG"

echo "$DMG"
