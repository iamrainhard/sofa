#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -v
mkdir -p build/checks
swiftc Sources/HisenseRemote/TVPowerState.swift tests/PowerStateChecks.swift -o build/checks/power
build/checks/power
swiftc Sources/HisenseRemote/VolumeInteraction.swift tests/VolumeInteractionChecks.swift -o build/checks/volume
build/checks/volume
swiftc Sources/HisenseRemote/TVCatalog.swift tests/CatalogChecks.swift -o build/checks/catalog
build/checks/catalog
swift build -c release
