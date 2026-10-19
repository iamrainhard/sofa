#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Close an existing preview before changing its app bundle.
python3 - "${1:-welcome}" <<'PY'
import plistlib, subprocess, sys, shutil
from pathlib import Path
state = sys.argv[1]
assert state in ('welcome', 'pair', 'success', 'remote', 'network', 'trust', 'discovery', 'offline', 'connecting', 'android-pair', 'android-home', 'android-remote')
src=Path('build/Sofa.app'); dst=Path('build/Sofa Preview.app')
if dst.exists(): shutil.rmtree(dst)
subprocess.run(['ditto',str(src),str(dst)],check=True)
p=dst/'Contents/Info.plist'; d=plistlib.loads(p.read_bytes()); d['CFBundleIdentifier']='com.rain.sofa-preview';d['CFBundleDisplayName']='Sofa Preview';d['SofaPreviewState']=state;p.write_bytes(plistlib.dumps(d))
subprocess.run(['python3','scripts/sign-bundle.py',str(dst),'-'],check=True)
PY
