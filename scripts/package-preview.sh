#!/bin/bash
# Explicit early-beta packaging. The normal notarized package.sh stays strict.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Sofa.app}"
codesign --verify --deep --strict "$APP"
codesign --verify -R='anchor apple generic and certificate leaf[subject.OU] = "3FAL2BXWLS" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/sofa-preview-package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/package" "$STAGE/verify" dist
ditto "$APP" "$STAGE/package/Sofa.app"
cat > "$STAGE/package/INSTALL.txt" <<TEXT
Sofa $VERSION (build $BUILD) — early beta
macOS 26 or later. Apple silicon (M-series) Mac.

This download is Developer ID signed by TOP NOTCH COMPANY LIMITED.
Apple notarization is pending. It is NOT a notarized release.
macOS may block the first launch. You can wait for the notarized download.

Installation:
1. Move Sofa.app to Applications, then open it.
2. If macOS blocks this unnotarized beta and you choose to proceed, use
   System Settings > Privacy & Security > Open Anyway for Sofa.
   See Apple's guidance: https://support.apple.com/en-us/102445
   Do not disable Gatekeeper globally or remove quarantine in Terminal.
3. Find Sofa's couch icon in the menu bar.
4. Keep your Mac and TV on the same network. Allow Local Network access.
5. Choose Set up my TV and follow the on-TV pairing instructions.

VIDAA was tested on one Hisense A4K-series TV. Google / Android TV and Samsung
Tizen support are experimental and have not been tested on physical hardware.
Samsung uses on-TV Allow approval; its slider requires compatible feedback.
Compatibility depends on the TV, firmware and app. No Sofa account required.

Downloads and source: https://github.com/iamrainhard/sofa
Help: https://github.com/iamrainhard/sofa/blob/main/docs/TROUBLESHOOTING.md
TEXT
ZIP="dist/Sofa-${VERSION}-build${BUILD}-arm64-preview.zip"
[[ ! -e "$ZIP" ]] || { echo "Refusing to replace existing preview: $ZIP"; exit 1; }
ditto -c -k --sequesterRsrc "$STAGE/package" "$ZIP"
ditto -x -k "$ZIP" "$STAGE/verify"
codesign --verify --deep --strict "$STAGE/verify/Sofa.app"
[[ -f "$STAGE/verify/INSTALL.txt" ]]
cmp "$APP/Contents/MacOS/Sofa" "$STAGE/verify/Sofa.app/Contents/MacOS/Sofa"
(cd dist && shasum -a 256 "${ZIP##*/}") > "$ZIP.sha256"
echo "Verified signed preview (not notarized): $ZIP"
