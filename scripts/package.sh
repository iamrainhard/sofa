#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/notarized/Sofa.app}"
[[ -d "$APP" ]] || { echo 'Supply the exported notarized Sofa.app path.'; exit 1; }
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
ZIP="dist/Sofa-${VERSION}-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" > "$ZIP.sha256"
echo "$ZIP"
