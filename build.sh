#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
if [[ ! -x build/helper/SofaBridge.app/Contents/MacOS/SofaBridge || "${SOFA_REBUILD_HELPER:-0}" == 1 || ! -f build/helper-inputs.sha256 ]] || ! shasum -a 256 --status -c build/helper-inputs.sha256; then
    bash scripts/build-helper.sh
fi
APP="$PWD/build/Sofa.app"
# Only replace generated output; previous source snapshots live outside this folder.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sofa "$APP/Contents/MacOS/Sofa"
mkdir -p "$APP/Contents/Helpers"
ditto build/helper/SofaBridge.app "$APP/Contents/Helpers/SofaBridge.app"
xcrun actool Resources/Sofa.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 --app-icon Sofa --output-partial-info-plist build/icon-info.plist --output-format human-readable-text
cp docs/THIRD_PARTY.txt "$APP/Contents/Resources/THIRD_PARTY.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE"
ditto Resources/RuntimeLicenses "$APP/Contents/Resources/RuntimeLicenses"
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('build/Sofa.app/Contents/Info.plist')
d=dict(CFBundleExecutable='Sofa',CFBundleIdentifier='com.rain.luma-remote',CFBundleName='Sofa',CFBundleDisplayName='Sofa',CFBundleVersion='9',CFBundleShortVersionString='0.4.0-beta.1',CFBundlePackageType='APPL',LSMinimumSystemVersion='26.0',LSUIElement=True,NSHighResolutionCapable=True,NSLocalNetworkUsageDescription='Sofa connects to your TV on your home network for discovery, remote controls and pairing.',NSBonjourServices=['_androidtvremote2._tcp'])
d.update(plistlib.loads(Path('build/icon-info.plist').read_bytes()))
p.write_bytes(plistlib.dumps(d))
h=Path('build/Sofa.app/Contents/Helpers/SofaBridge.app/Contents/Info.plist')
helper=plistlib.loads(h.read_bytes())
helper.update(CFBundleIdentifier='com.rain.sofa.bridge',CFBundleVersion='9',CFBundleShortVersionString='0.4.0',LSUIElement=True,NSLocalNetworkUsageDescription=d['NSLocalNetworkUsageDescription'])
h.write_bytes(plistlib.dumps(helper))
PY
SIGNING_IDENTITY="${SOFA_SIGNING_IDENTITY:--}"
# Sign nested Mach-O code first. No --deep signing: each bundled binary is explicit.
python3 scripts/sign-bundle.py "$APP" "$SIGNING_IDENTITY"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
