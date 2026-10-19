#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv run --python 3.12 --with-requirements Resources/requirements.lock python -m unittest discover -s tests -v
mkdir -p build/checks
swiftc Sources/HisenseRemote/TVPowerState.swift tests/PowerStateChecks.swift -o build/checks/power
build/checks/power
swiftc Sources/HisenseRemote/VolumeInteraction.swift tests/VolumeInteractionChecks.swift -o build/checks/volume
build/checks/volume
swiftc Sources/HisenseRemote/TVCatalog.swift tests/CatalogChecks.swift -o build/checks/catalog
build/checks/catalog
swiftc Sources/HisenseRemote/ConnectionInput.swift Sources/HisenseRemote/TVConnectionPlatform.swift tests/ConnectionInputChecks.swift -o build/checks/connection
build/checks/connection
swiftc -swift-version 5 Sources/HisenseRemote/{RemoteModel,TVDiscovery,TVConnectionPlatform,TVPlaybackControl,ConnectionInput,TVPowerState,VolumeInteraction,TVCatalog,TVPlatform}.swift tests/AdapterModelChecks.swift -o build/checks/model
build/checks/model
swiftc Sources/HisenseRemote/ClickpadGeometry.swift tests/ClickpadGeometryChecks.swift -o build/checks/clickpad
build/checks/clickpad
swiftc Sources/HisenseRemote/ConnectionInput.swift Sources/HisenseRemote/TVConnectionPlatform.swift Sources/HisenseRemote/TVPlaybackControl.swift tests/PlaybackControlChecks.swift -o build/checks/playback
build/checks/playback
swift build -c release
