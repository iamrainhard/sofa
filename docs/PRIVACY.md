# Privacy

Sofa has no account, telemetry, analytics, advertising SDK or cloud backend.

- **TV connection:** your chosen private IPv4 address, commands and pairing messages are sent to that TV. Discovery uses VIDAA/Samsung SSDP and Android TV Bonjour advertisements on the local network. Manual automatic detection probes only the entered private IP at the supported service ports (36669, 6466 and 8002).
- **Pairing:** VIDAA tokens, Samsung tokens and Android client certificates/private keys are stored separately in macOS Keychain. Android TLS setup briefly uses owner-only temporary files; the private-key file is removed after loading the TLS context, and the temporary directory is removed on normal disconnect. The key remains in process memory while connected. A forced process termination during setup can leave temporary files until macOS cleans its temporary directory. The TV address, nickname, random client identifier, certificate fingerprint and UI preferences are stored locally in UserDefaults.
- **Android TV:** commands use the local Remote Service, without ADB, root, developer mode, or a Google account in Sofa. Remote Service supplies current-app and volume state where supported. Android shortcut tiles do not query an installed-app list.
- **Samsung Tizen (build 13):** remote commands and approval use TLS on TCP 8002. Sofa checks the approved certificate on the same socket before sending a saved token and does not fall back to plaintext remote control. Optional model/power metadata and UPnP volume use unauthenticated local HTTP to the selected TV only; they carry no pairing token. These optional requests reject redirects and cross-device URLs. No SmartThings or Samsung cloud account is used.
- **App artwork:** the TV’s catalog supplies public image URLs. Sofa only accepts HTTPS images from `img.vidaahub.com`, including redirects. That service receives your public IP address and requested image URL. Images are cached under your user Library/Caches folder. No pairing credentials are sent there.
- **Updates and help:** links open GitHub in your default browser. Sofa does not silently download or install updates.
- **Login startup:** disabled by default; enabled only when you choose it in Settings.

Use Settings → TV → Forget this TV to remove that Mac’s saved pairing, fingerprint, address and nickname. It does not erase the TV’s own paired-device list. Quit and delete Sofa to uninstall; local caches and preferences may remain until you remove them. Nothing is uploaded automatically when an error occurs.
