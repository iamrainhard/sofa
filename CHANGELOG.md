# Changelog

## 1.0.0 — build 16

First stable release of Sofa. Android/Google TV and Samsung Tizen adapters remain experimental. Release packaging is in progress; Apple acceptance and publication are recorded separately.

- Reconnect paired TVs after DHCP changes using a saved device identity and approved certificate; retain existing Keychain credentials and app playback preferences.
- Broaden discovery across VIDAA SSDP/Netflix advertisements and Android, Cast, AirPlay and Samsung Bonjour hints, with remote-service verification, per-interface searches and retries.
- Recover after connection loss, network changes and Mac wake; cancel stale work and stop at permission, certificate or pairing decisions.
- Reject identity/certificate mismatches and ambiguous address migrations. Android and Samsung remain experimental; physical validation is limited to the development Hisense TV.

## 0.6.0-beta.1 — build 15 notarized beta

- Add native Sparkle updates with daily checks, background downloads, installation on quit, and manual Check for Updates.
- Add Settings → Updates and gentle in-panel update reminders; preview bundles never start the updater.
- Verify signed update feeds and archives before extraction. Release tooling requires notarization and verifies the published GitHub asset before advertising it.
- Keep bundle and Keychain identities unchanged to preserve existing TV pairing.
- Apple notarization approved. Local tests verified a signed upgrade and relaunch, rejection of a corrupted archive, and background download followed by installation on quit. All 60 Python tests and Swift checks pass. The installed notarized build reconnected to the development VIDAA TV with its existing pairing.

### Branding from build 14

- Keep the Sofa name and introduce “Your TV, from your Mac.” across onboarding, About and public branding.
- Apply the native Lounge Remote icon with a unified body and inset seat detail, plus an outline-only menu-bar symbol matching the website.
- Refresh the website icon and social preview card. TV control and pairing behavior are unchanged.

## 0.5.0-beta.1 — build 13 notarized beta

- Apple notarization approved; distribute the approved, stapled app in a signed DMG and ZIP, with Gatekeeper and checksum verification.

- Add experimental Samsung Tizen secure WebSocket control, SSDP discovery and manual setup.
- Pair by choosing Allow on the TV; save the token in a separate Keychain namespace and pin the TV certificate before sending it.
- Keep the glass volume slider only with verified compatible UPnP volume feedback; retain −/+ fallback, unknown mute state and refresh recovery.
- Show installed app tiles only when Samsung supplies a catalog; otherwise offer Open Home. Input-menu key replaces unsupported direct input lists.
- Keep remote controls responsive during optional metadata and service discovery.
- Preserve VIDAA and Android wire adapters and existing pairing namespaces. All 53 Python tests and Swift checks pass; build 13 reconnects to the development VIDAA TV.
- Samsung and Android support remain unverified on physical hardware. Samsung network wake and older Orsay models are not supported.

## 0.4.0-beta.1 — build 12 early preview

- Match the menu-bar couch to the website’s exact stroke-only outline, with rounded joins and no filled areas (build 12).

## 0.4.0-beta.1 — build 10 early preview

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
