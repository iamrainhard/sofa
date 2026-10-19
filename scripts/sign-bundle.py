#!/usr/bin/env python3
"""Sign the embedded CPython runtime, then the app, without exporting keys."""
from pathlib import Path
import subprocess, sys
app, identity = Path(sys.argv[1]), sys.argv[2]
magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe'}
flags = ['--force', '--sign', identity]
if identity != '-': flags += ['--options', 'runtime', '--timestamp']
for file in sorted((app/'Contents').rglob('*'), key=lambda p: len(p.parts), reverse=True):
    if file.is_file() and not file.is_symlink():
        with file.open('rb') as stream: header = stream.read(4)
        if header in magic: subprocess.run(['codesign', *flags, str(file)], check=True)
for framework in sorted((app/'Contents').rglob('*.framework'), key=lambda p: len(p.parts), reverse=True):
    subprocess.run(['codesign', *flags, str(framework)], check=True)
for nested in sorted((app/'Contents').rglob('*.app'), key=lambda p: len(p.parts), reverse=True):
    subprocess.run(['codesign', *flags, str(nested)], check=True)
subprocess.run(['codesign', *flags, str(app)], check=True)
