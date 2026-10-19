<p align="center"><img src="docs/images/icon.png" width="128" alt="Sofa app icon"></p>
<h1 align="center">Sofa</h1>
<p align="center">Your TV. Within reach.</p>
<p align="center">A free, open-source menu-bar remote for compatible Hisense VIDAA TVs.</p>

Sofa brings your TV’s remote, apps, inputs and volume into a small native macOS panel. Built with SwiftUI, AppKit and Apple’s Liquid Glass components.

**Beta software. macOS 26 or later · Apple silicon.** Tested with one Hisense A4K-series VIDAA TV; compatibility with other models and firmware is not guaranteed. This is independent software, not an official Hisense, VIDAA or Apple product.

## Download

Get the latest beta from [GitHub Releases](https://github.com/iamrainhard/sofa/releases). Release notes identify signing and notarization status; source availability alone does not mean a notarized download is available.

1. Download and unzip the ZIP, then move **Sofa.app** into **Applications**.
2. Open Sofa. Its TV icon appears in your menu bar; it has no persistent Dock window.
3. Keep your Mac and TV on the same home network. Allow Local Network access when macOS asks.
4. Choose **Set up my TV**. Discover a nearby compatible TV or enter the private IPv4 address shown in the TV’s network settings.
5. Verify that address, trust the TV’s certificate, and request a pairing code. Enter the code displayed on your TV.

No Python, Homebrew, Xcode or Sofa account is required to use the packaged app. Login startup is optional and off by default.

## What’s inside

- Native glass menu-bar interface and an original layered app icon.
- Large directional pad with OK, Home, Back and Menu.
- Playback buttons, volume and channel rockers, mute and numeric keypad.
- Horizontal app shelf with logos from your own TV catalog, plus input selection.
- TV-reported active app/input and power status; pending changes are shown honestly.
- Smooth volume interaction with coalesced commands and delayed readback protection.
- Pairing credentials stored in macOS Keychain and TV certificate pinning.
- First-run pairing, TV naming, reconnect-on-launch preference and optional login startup.
- Keyboard arrows and Return for the remote, accessibility labels, Reduce Motion support.

The TV illustration shows app/input identity, not screen mirroring. Sofa controls the current VIDAA OS; it does not replace firmware, install TV apps, bypass subscriptions or provide voice search. Network wake depends on the TV’s standby settings. Bluetooth/audio routing and Chromecast/Google TV control are not included.

## Privacy

Commands and pairing go directly to your TV over the local network. Pairing secrets stay in Keychain. No analytics, advertising or Sofa cloud service. Logos are downloaded from VIDAA’s public image CDN and cached locally. See [Privacy](docs/PRIVACY.md) and [Troubleshooting](docs/TROUBLESHOOTING.md).

## Build from source

Requirements: Apple silicon Mac, macOS 26+, Xcode 26+ (selected with `xcode-select`), and [uv](https://docs.astral.sh/uv/).

```sh
bash scripts/check.sh
bash build.sh
```

Output: `build/Sofa.app`. The default source build is ad-hoc signed for local development; it is not a notarized public download. The bridge uses CPython 3.12 and PyInstaller 6.22.3, bundled by the build. Set `SOFA_REBUILD_HELPER=1` after bridge changes. See [Releasing](docs/RELEASING.md) for Developer ID signing and notarization.

## Beta coverage

Protocol framing, authentication gates, key payloads, certificate change handling, volume state and catalog identity have automated checks. Core Home, arrows/OK, volume and mute were verified with a physical TV during development. Channel controls, every app/input, wake from standby, first installation on another Mac and long-duration sleep/wake need wider beta testing. Please include your model and firmware in an issue, but never pairing codes, tokens, device IDs or private network captures.

## Contribute

See [CONTRIBUTING](CONTRIBUTING.md). Bug reports and compatibility reports are welcome. There are no paid features or subscriptions.

## License and credits

Sofa source and original artwork are MIT licensed. Shared VIDAA protocol research/certificate credits and bundled runtime licenses are in [THIRD_PARTY](docs/THIRD_PARTY.txt) and `Resources/RuntimeLicenses`. Third-party app marks remain their owners’ property and are fetched at runtime, not redistributed as Sofa artwork.
