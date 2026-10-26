# Discovery and pairing — build 16

Release status, 2026-10-26. Sofa 1.0.0 build 16 is Developer ID signed and Apple notarization accepted. The signed DMG, updater ZIP and SHA-256 files are published as the stable v1.0.0-build16 GitHub release. Both packaged apps passed staple and Gatekeeper checks. GitHub’s clean-machine build and checks also passed. Website and signed-feed deployment, followed by an installed upgrade test, are in progress. The earlier beta-labelled build 16 archive is retained but will not be published.

## Implemented

- Save a non-secret device registry with platform, stable discovery identifiers, approved certificate and original Keychain account. Credentials stay in their existing Keychain item when the address changes.
- Combine SSDP searches on active IPv4 interfaces with Android Remote, Cast, AirPlay and Samsung Bonjour candidates. Verify a compatible remote service before listing a candidate. Repeat searches and bound concurrent work; discard cancelled rounds.
- Reconnect after connection loss, network changes and Mac wake. Address migration requires both known identity and approved certificate. Stop at permission, trust or pairing decisions.
- Preserve existing protocol adapters, pairing namespaces and per-app playback preferences.

## Verified

- 73 Python tests and Swift checks, including protocol TLS tests, cancellation, hostile discovery metadata, optional metadata failures, pairing persistence, identity/certificate mismatch and ambiguous address rejection. Release build passes.
- Signed build 16 installed over build 15 on the development Mac. The existing Hisense VIDAA A4K pairing was reused without a code. TV returned volume and its 46-app catalog.
- A controlled stale-address test changed only Sofa's saved endpoint and registry last-address field while the app was stopped. On relaunch Sofa discovered the TV at its current address, authenticated automatically and corrected both saved addresses. The record ID, Keychain account, identifiers and approved certificate were unchanged. No TV code or new trust approval was needed. This simulates an IP change; the router's DHCP lease was not changed.
- macOS initially reported Local Network denied despite Sofa's switch being enabled. Refreshing the existing permission off/on and reconnecting restored access. No credential reset or broader permission was required.

## Remaining evidence and limits

- Android/Google TV and Samsung recovery have automated coverage but still need physical pairing, IP-change and network-change tests. A generic Android TV without the compatible Remote Service is not supported by discovery alone.
- Network isolation, blocked multicast, denied Local Network permission, sleeping TVs and missing remote services can prevent discovery. Saved-address retry helps when advertisements are missing; it cannot find an unknown new address without a usable announcement.
- An older installation needs one authenticated reachable connection to learn the device identity. If its old address is already unreachable and no identity was learned, explicit device selection/trust may still be necessary.
- Physical Android/Samsung tests and wider sleep/wake/network-change coverage remain the next compatibility work.
