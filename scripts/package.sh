#!/bin/zsh
# Builds a shareable release into build/release/:
#   33rpm-<version>.dmg        app + Read Me First (also copied to 33rpm.dmg)
#   33rpm-bridge-<ext version>.zip extension, ready to upload to the Chrome Web Store
set -euo pipefail

ROOT="${0:A:h:h}"
# The app and the extension are versioned separately: the extension only changes when its own code does.
VERSION=$(sed -n 's/.*CFBundleShortVersionString<\/key><string>\(.*\)<\/string>.*/\1/p' "$ROOT/scripts/build_app.sh")
EXT_VERSION=$(python3 -c "import json;print(json.load(open('$ROOT/extension/manifest.json'))['version'])")
OUT="$ROOT/build/release"
STAGE="$OUT/stage"

"$ROOT/scripts/build_app.sh" release

rm -rf "$OUT"
mkdir -p "$STAGE"
cp -R "$ROOT/build/33rpm.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me First.txt" <<'TXT'
33rpm: a record player on your desktop for YouTube Music

1. Drag 33rpm into Applications and open it.
   macOS will say it can't verify the developer (this is a free hobby app, not notarized).
   Go to System Settings > Privacy & Security, scroll down and click "Open Anyway".

2. In Chrome, add the 33rpm Bridge extension from the Chrome Web Store:
   https://chromewebstore.google.com/detail/33rpm-bridge/biiiggaibbnengablmcboeaehlhmffnj
   (33rpm's Setup Guide, in the menu bar, has a button for this.)

3. Click the 33rpm Bridge icon in Chrome's toolbar and paste the pairing token
   (33rpm menu bar icon > Copy Pairing Token), then Save.

4. Play something on music.youtube.com.

Everything stays on your Mac (127.0.0.1). No accounts, no analytics.
TXT

hdiutil create -volname "33rpm" -srcfolder "$STAGE" -ov -format UDZO "$OUT/33rpm-$VERSION.dmg" >/dev/null
# Same file under a fixed name, so releases/latest/download/33rpm.dmg always gets the newest version (the website links to it).
cp "$OUT/33rpm-$VERSION.dmg" "$OUT/33rpm.dmg"
(cd "$ROOT/extension" && zip -qr "$OUT/33rpm-bridge-$EXT_VERSION.zip" . -x ".*")
rm -rf "$STAGE"

echo "Release files:"
ls -lh "$OUT"
