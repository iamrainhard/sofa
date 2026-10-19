#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SOFA_TEAM_ID:?Set your Apple Developer team ID}"
: "${SOFA_SIGNING_IDENTITY:?Set your Developer ID Application identity}"
[[ -d build/Sofa.app ]] || { echo 'Build and sign the app first.'; exit 1; }
python3 - <<'PY'
import os,plistlib,subprocess,datetime,shutil
from pathlib import Path
archive=Path('build/Sofa.xcarchive')
if archive.exists(): shutil.rmtree(archive)
(archive/'Products/Applications').mkdir(parents=True)
subprocess.run(['ditto','build/Sofa.app',str(archive/'Products/Applications/Sofa.app')],check=True)
app=plistlib.loads(Path('build/Sofa.app/Contents/Info.plist').read_bytes())
props={k:app[k] for k in ['CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion']}
props.update(ApplicationPath='Applications/Sofa.app',SigningIdentity=os.environ['SOFA_SIGNING_IDENTITY'],Team=os.environ['SOFA_TEAM_ID'])
(archive/'Info.plist').write_bytes(plistlib.dumps(dict(ArchiveVersion=2,CreationDate=datetime.datetime.now(),Name='Sofa',SchemeName='Sofa',ApplicationProperties=props)))
Path('build/ExportOptions.plist').write_bytes(plistlib.dumps(dict(method='developer-id',destination='upload',signingStyle='manual',signingCertificate=os.environ['SOFA_SIGNING_IDENTITY'],teamID=os.environ['SOFA_TEAM_ID'],manageAppVersionAndBuildNumber=False)))
PY
xcodebuild -exportArchive -archivePath build/Sofa.xcarchive -exportPath build/notarization-upload -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
echo 'Uploaded to Apple. Upload success is not notarization acceptance.'
echo 'After Apple accepts it, run: xcodebuild -exportNotarizedApp -archivePath build/Sofa.xcarchive -exportPath build/notarized'
