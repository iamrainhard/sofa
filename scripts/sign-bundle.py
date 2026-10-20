#!/usr/bin/env python3
"""Sign nested code inside out, preserving Sparkle helper entitlements."""
from pathlib import Path
import subprocess, sys
app, identity = Path(sys.argv[1]), sys.argv[2]
magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe'}
flags = ['--force', '--sign', identity, '--preserve-metadata=entitlements']
if identity != '-': flags += ['--options', 'runtime', '--timestamp']
for file in sorted((app/'Contents').rglob('*'), key=lambda p: len(p.parts), reverse=True):
    if file.is_file() and not file.is_symlink():
        with file.open('rb') as stream: header = stream.read(4)
        if header in magic: subprocess.run(['codesign', *flags, str(file)], check=True)
containers = [p for p in (app/'Contents').rglob('*')
              if p.is_dir() and not p.is_symlink() and p.suffix in {'.app', '.xpc', '.framework'}]
for nested in sorted(containers, key=lambda p: len(p.parts), reverse=True):
    subprocess.run(['codesign', *flags, str(nested)], check=True)
subprocess.run(['codesign', *flags, str(app)], check=True)
