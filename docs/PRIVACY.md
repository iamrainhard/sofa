# Privacy

Sofa has no account, telemetry, analytics, advertising SDK or cloud backend.

- **TV connection:** your chosen private IPv4 address, commands and pairing messages are sent to that TV. Discovery broadcasts an SSDP query on the local network and reads compatible replies.
- **Pairing:** credentials are stored in macOS Keychain. The TV address, nickname, random client identifier, certificate fingerprint and UI preferences are stored locally in UserDefaults.
- **App artwork:** the TV’s catalog supplies public image URLs. Sofa only accepts HTTPS images from `img.vidaahub.com`, including redirects. That service receives your public IP address and requested image URL. Images are cached under your user Library/Caches folder. No pairing credentials are sent there.
- **Updates and help:** links open GitHub in your default browser. Sofa does not silently download or install updates.
- **Login startup:** disabled by default; enabled only when you choose it in Settings.

Use Settings → TV → Forget this TV to remove that Mac’s saved pairing, fingerprint, address and nickname. It does not erase the TV’s own paired-device list. Quit and delete Sofa to uninstall; local caches and preferences may remain until you remove them. Nothing is uploaded automatically when an error occurs.
