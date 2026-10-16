#!/bin/bash
# Naiwa Desktop Pet — unified v4.0, persistent belly toggle: build a local unsigned macOS .app from provided assets.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
ASSETS="$ROOT/../assets"
APP="$ROOT/奶娃桌宠.app"
if [ ! -f "$ASSETS/Stills/pose_1.png" ]; then
  echo "找不到 ../assets：请保留整个仓库目录，不要单独移动 mac 文件夹。"
  exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "没有找到苹果编译工具。请先运行: xcode-select --install"; read -r -p "按回车退出..." _; exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "需要安装 Xcode Command Line Tools: xcode-select --install"; read -r -p "按回车退出..." _; exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Clean stale generated assets from an older build in this same folder.
rm -rf "$APP/Contents/Resources/Stills" "$APP/Contents/Resources/LaughFrames"
echo '编译奶娃 Mac 桌宠中...'
xcrun swiftc -O -framework AppKit -framework AVFoundation -framework QuartzCore \
  "$ROOT/Sources/main.swift" -o "$APP/Contents/MacOS/NaiwaPet"
cp -R "$ASSETS/Stills" "$APP/Contents/Resources/"
cp -R "$ASSETS/LaughFrames" "$APP/Contents/Resources/"
cp "$ASSETS/laugh_original_audio.m4a" "$APP/Contents/Resources/"
# App icon is optional; failure to generate icon must not block building.
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$ROOT/.Naiwa.iconset"
  mkdir -p "$ICONSET"
  for pair in '16 16x16' '32 16x16@2x' '32 32x32' '64 32x32@2x' '128 128x128' '256 128x128@2x' '256 256x256' '512 256x256@2x' '512 512x512' '1024 512x512@2x'; do
    set -- $pair
    sips -s format png -z "$1" "$1" "$ASSETS/AppIcon.png" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1 || true
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true
  rm -rf "$ICONSET"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NaiwaPet</string>
<key>CFBundleIdentifier</key><string>io.local.naiwa.desktoppet</string>
<key>CFBundleName</key><string>奶娃桌宠</string>
<key>CFBundleDisplayName</key><string>奶娃桌宠</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>4.0</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
chmod +x "$APP/Contents/MacOS/NaiwaPet"
echo
printf '🎉 已生成：%s\n' "$APP"
echo '正在启动奶娃跨平台统一版 v4.0（10秒未单击自动回到托腮）...'
# Stop our own previous version (same exact executable name), so macOS won't
# silently bring the old instance to the foreground instead of the new one.
killall NaiwaPet >/dev/null 2>&1 || true
sleep 0.4
if [ "${NAIWA_SKIP_OPEN:-0}" != "1" ]; then open -n "$APP"; fi
echo '用鼠标悬停、单击、双击试试。菜单栏「🐸 奶娃」可调节音量和大小。'
if [ -t 0 ]; then read -r -p "按回车关闭终端..." _; fi
