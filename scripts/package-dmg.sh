#!/bin/bash
# Package the Apple-notarized, stapled app in a signed DMG.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/notarized/Sofa.app}"
IDENTITY="${SOFA_SIGNING_IDENTITY:?Set SOFA_SIGNING_IDENTITY to your Developer ID Application identity}"
codesign --verify --deep --strict "$APP"
codesign --verify -R='anchor apple generic and certificate leaf[subject.OU] = "3FAL2BXWLS" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
DMG="dist/Sofa-${VERSION}-build${BUILD}-arm64-notarized.dmg"
[[ ! -e "$DMG" ]] || { echo "Refusing to replace existing download: $DMG"; exit 1; }
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/sofa-dmg.XXXXXX")
ATTACHED=false
cleanup() {
  if $ATTACHED; then hdiutil detach "$STAGE/mount" || return; fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
mkdir -p "$STAGE/content" "$STAGE/mount" dist
ditto "$APP" "$STAGE/content/Sofa.app"
ln -s /Applications "$STAGE/content/Applications"
cat > "$STAGE/content/Install Sofa.txt" <<TEXT
Sofa $VERSION (build $BUILD) — notarized release
macOS 26 or later. Apple silicon (M-series) Mac.

Drag Sofa to Applications, then eject this disk image.
Open Sofa from Applications. Look for the remote icon in your menu bar.
Keep your Mac and TV on the same network and allow Local Network access.
Choose Set up my TV and follow the pairing instructions.

Developer ID signed by TOP NOTCH COMPANY LIMITED.
This DMG contains the Apple-notarized Sofa app with its ticket stapled.
The app passes Gatekeeper assessment. Open it normally from Applications;
macOS may ask you to confirm opening a downloaded app on first launch.

VIDAA tested on one Hisense A4K-series TV. Google / Android TV and Samsung
Tizen support are experimental and have not been tested on physical hardware.
Samsung requires secure remote control and on-TV Allow approval. Its volume
slider appears only with compatible volume feedback; otherwise use -/+.
Compatibility varies by model and firmware.
No Python, Homebrew, Xcode or Sofa account is needed to run the app.

https://github.com/iamrainhard/sofa
TEXT
# Write Finder layout directly, without driving Finder or disturbing the desktop.
uv run --with ds_store==1.3.1 python scripts/dmg-layout.py "$STAGE/content/.DS_Store"
hdiutil create -volname Sofa -srcfolder "$STAGE/content" -format UDZO "$STAGE/Sofa.dmg"
codesign --force --sign "$IDENTITY" --timestamp "$STAGE/Sofa.dmg"
codesign --verify --strict "$STAGE/Sofa.dmg"
hdiutil verify "$STAGE/Sofa.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$STAGE/mount" "$STAGE/Sofa.dmg"
ATTACHED=true
codesign --verify --deep --strict "$STAGE/mount/Sofa.app"
xcrun stapler validate "$STAGE/mount/Sofa.app"
spctl --assess --type execute --verbose=2 "$STAGE/mount/Sofa.app"
cmp "$APP/Contents/MacOS/Sofa" "$STAGE/mount/Sofa.app/Contents/MacOS/Sofa"
[[ "$(readlink "$STAGE/mount/Applications")" == /Applications ]]
[[ -f "$STAGE/mount/Install Sofa.txt" ]]
hdiutil detach "$STAGE/mount"
ATTACHED=false
mv "$STAGE/Sofa.dmg" "$DMG"
(cd dist && shasum -a 256 "${DMG##*/}") > "$DMG.sha256"
echo "Verified signed DMG containing the notarized, stapled app: $DMG"
