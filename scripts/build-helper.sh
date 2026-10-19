#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null || { echo 'Install uv from https://docs.astral.sh/uv/ first.'; exit 1; }
uv run --python 3.12 --with-requirements Resources/requirements.lock --with pyinstaller==6.22.3 pyinstaller --noconfirm --clean --onedir --windowed --name SofaBridge --distpath build/helper --workpath build/pyinstaller --specpath build --add-data "$PWD/Resources/certs:certs" --collect-all androidtvremote2 Resources/controller.py
# Track inputs: never silently reuse a helper built before an adapter/dependency edit.
shasum -a 256 Resources/*.py Resources/requirements.lock scripts/build-helper.sh > build/helper-inputs.sha256
