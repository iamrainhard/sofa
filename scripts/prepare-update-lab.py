#!/usr/bin/env python3
"""Create isolated Developer ID signed Sofa copies for a local Sparkle upgrade test.

Only uses build/update-lab and com.rain.sofa.updater-lab preferences. Never publish
these artifacts: they are not production bundles and have no notarization ticket.
"""
from pathlib import Path
import os
import plistlib
import subprocess

root = Path(__file__).resolve().parents[1]
lab = root / 'build/update-lab'
identity = os.environ['SOFA_SIGNING_IDENTITY']
if lab.exists():
    raise SystemExit('Test directory exists; preserve its evidence or move it before making a new lab.')
tools = root / '.build/artifacts/sparkle/Sparkle/bin'
for version, directory in [('1', 'installed'), ('2', 'staging')]:
    app = lab / directory / 'Sofa Update Test.app'
    app.parent.mkdir(parents=True)
    subprocess.run(['ditto', str(root / 'build/Sofa.app'), str(app)], check=True)
    file = app / 'Contents/Info.plist'
    info = plistlib.loads(file.read_bytes())
    info.update(CFBundleIdentifier='com.rain.sofa.updater-lab', CFBundleName='Sofa Update Test',
                CFBundleDisplayName='Sofa Update Test', CFBundleVersion=version,
                CFBundleShortVersionString=f'0.6.0-test.{version}',
                SUFeedURL='http://127.0.0.1:8771/appcast.xml',
                SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
                NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
    file.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
packages = lab / 'packages'
packages.mkdir()
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(lab / 'staging/Sofa Update Test.app'), str(packages / 'Sofa-test-2.zip')], check=True)
subprocess.run([str(tools / 'generate_appcast'), '--account', 'com.rain.sofa.sparkle', '--maximum-deltas', '0',
                '--download-url-prefix', 'http://127.0.0.1:8771/', str(packages)], check=True)
subprocess.run(['defaults', 'write', 'com.rain.sofa.updater-lab', 'autoConnect', '-bool', 'false'], check=True)
print('Serve build/update-lab/packages on 127.0.0.1:8771; open installed/Sofa Update Test.app.')
