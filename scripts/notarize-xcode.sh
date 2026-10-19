#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SOFA_TEAM_ID:?Set your Apple Developer team ID}"
: "${SOFA_SIGNING_IDENTITY:?Set your Developer ID Application identity}"
[[ -d build/Sofa.app ]] || { echo 'Build and sign the app first.'; exit 1; }
ARCHIVE="${SOFA_ARCHIVE_PATH:-build/Sofa.xcarchive}"
UPLOAD="${SOFA_UPLOAD_PATH:-build/notarization-upload}"
export SOFA_ARCHIVE_PATH="$ARCHIVE"
python3 - <<'PY'
import os,plistlib,subprocess,datetime,shutil
from pathlib import Path
archive=Path(os.environ['SOFA_ARCHIVE_PATH'])
if archive.exists(): raise SystemExit('Archive already exists; inspect its submission instead of overwriting it. Use a new SOFA_ARCHIVE_PATH for a new build.')
(archive/'Products/Applications').mkdir(parents=True)
subprocess.run(['ditto','build/Sofa.app',str(archive/'Products/Applications/Sofa.app')],check=True)
app=plistlib.loads(Path('build/Sofa.app/Contents/Info.plist').read_bytes())
props={k:app[k] for k in ['CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion']}
props.update(ApplicationPath='Applications/Sofa.app',SigningIdentity=os.environ['SOFA_SIGNING_IDENTITY'],Team=os.environ['SOFA_TEAM_ID'])
(archive/'Info.plist').write_bytes(plistlib.dumps(dict(ArchiveVersion=2,CreationDate=datetime.datetime.now(),Name='Sofa',SchemeName='Sofa',ApplicationProperties=props)))
Path('build/ExportOptions.plist').write_bytes(plistlib.dumps(dict(method='developer-id',destination='upload',signingStyle='manual',signingCertificate=os.environ['SOFA_SIGNING_IDENTITY'],teamID=os.environ['SOFA_TEAM_ID'],manageAppVersionAndBuildNumber=False)))
PY
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$UPLOAD" -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
echo 'Uploaded to Apple. Upload success is not notarization acceptance.'
echo "After Apple accepts it, run: xcodebuild -exportNotarizedApp -archivePath '$ARCHIVE' -exportPath build/notarized"
