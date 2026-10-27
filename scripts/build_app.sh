#!/bin/zsh
# Builds 33rpm.app into ./build. Usage: scripts/build_app.sh [debug|release] [--run]
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIG="${1:-release}"
APP="$ROOT/build/33rpm.app"

cd "$ROOT/App"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ThirtyThreeRPM"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/33rpm"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
rsync -a "$ROOT/extension/" "$APP/Contents/Resources/33rpm Bridge/"
[[ -d "$ROOT/Scenes" ]] && rsync -a --exclude "_sources" "$ROOT/Scenes/" "$APP/Contents/Resources/Scenes/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>        <string>com.rohanverma.33rpm</string>
    <key>CFBundleName</key>              <string>33rpm</string>
    <key>CFBundleDisplayName</key>       <string>33rpm</string>
    <key>CFBundleExecutable</key>        <string>33rpm</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.2.1</string>
    <key>CFBundleVersion</key>           <string>4</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSUIElement</key>               <true/>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for local use and SMAppService launch-at-login.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${2:-}" == "--run" ]]; then
  pkill -x 33rpm 2>/dev/null || true
  open "$APP"
fi
