#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/notarized/Sofa.app}"
[[ -d "$APP" ]] || { echo 'Supply the exported notarized Sofa.app path.'; exit 1; }
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
mkdir -p dist
ZIP="dist/Sofa-${VERSION}-build${BUILD}-arm64-notarized.zip"
[[ ! -e "$ZIP" ]] || { echo "Refusing to replace existing download: $ZIP"; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# Validate the actual unzipped download, not only the pre-package app.
VERIFY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sofa-package.XXXXXX")
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Sofa.app"
xcrun stapler validate "$VERIFY_DIR/Sofa.app"
spctl --assess --type execute --verbose=2 "$VERIFY_DIR/Sofa.app"
(cd dist && shasum -a 256 "${ZIP##*/}") > "$ZIP.sha256"
echo "$ZIP"
