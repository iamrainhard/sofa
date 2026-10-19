# Changelog

## 0.4.0-beta.1 — development

- Separate VIDAA and Android TV connection adapters behind a session-scoped JSON bridge. Preserve the existing VIDAA wire implementation and Keychain namespace.
- Experimental, brand-independent Google / Android TV Remote Service v2 support; no ADB or developer mode.
- Bonjour discovery, manual platform selection, service detection, six-character Android pairing and saved reconnect.
- Certificate verification on Android pairing/control connections, isolated credentials and redacted protocol errors.
- Keep Android's glass volume slider when feedback is available, using bounded, feedback-paced relative keys with latest-target replacement and −/+ fallback. Retain VIDAA's direct volume control and real catalogs.
- Platform-aware app shortcuts and input-menu action.
- Use a persistent glass surface for playback, navigation, mute, power, keypad, shelf and setup buttons; animate only the label and press overlay to avoid material flashes.
- Use Left/Right seeking for YouTube on VIDAA, verified to work where its media rewind/forward keys do not. Keep other apps on their existing media keys.
- Remember a seeking mode per TV and app: Automatic, Media buttons, or Left/right arrows, accessible from the remote’s More controls menu.
- Replace the generic TV menu-bar symbol with a crisp template adaptation of Sofa's couch icon, following the menu bar's light/dark appearance.
- Fix keypad spacing: 64-point keys fit their grid columns with 12-point gaps and adequate popover padding.
- Correct each clickpad arrow's hover label and position; keep the centre OK glass stable during presses.
- Native onboarding/remote previews and local TLS/protobuf integration checks. Physical Google / Android TV validation is still required.
- Locked Android helper dependencies, included dependency licenses and automatic helper rebuild on source changes.

## 0.3.0-beta.1

First public beta preparation:

- Redesigned native remote with a circular glass clickpad, compact active-app identity, playback controls, channel keypad and volume/channel rockers.
- Menu-bar onboarding with discovery, manual IP entry, certificate verification and pairing.
- TV naming, reconnect preferences, optional login startup and help links.
- Original layered Sofa app icon with light, dark and monochrome system rendering.
- Self-contained connection helper; end users do not need Python or developer tools.
- App logos loaded from each TV’s catalog and cached locally.
- Preserve existing app/input shelves, native glass slider, volume rolling animation and saved pairing identifiers.
- Clear Local Network guidance and settings shortcut; Keychain access failures no longer silently trigger new pairing.
- Strict IP/code validation, stable connecting state, and extraction/signature/notarization checks on the packaged download.
- Dedicated disconnected and connecting screens keep error guidance readable and the header/footer in place.
