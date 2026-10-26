# Troubleshooting

## No TV found

Wake the TV and confirm it and your Mac are on the same network. Guest Wi-Fi, client isolation, VPNs and routed networks can block discovery. Enter the TV’s address manually from Settings → Network. Sofa currently supports private IPv4 addresses and VIDAA’s MQTT remote service on TCP 36669, plus compatible UPnP volume control on TCP 18400. Google / Android TV support uses Remote Service TCP 6466 (control), TCP 6467 (pairing), and Bonjour discovery. Roku, Fire TV and Xumo are not implemented.

Allow Sofa in System Settings → Privacy & Security → Local Network. Discovery support varies by model; manual pairing is always available.

The setup screen includes **Open Privacy & Security settings**. In that pane, choose **Local Network**, allow Sofa, then return to Sofa and choose **Connect**. Sofa never changes your macOS permissions automatically. A Mac on a phone hotspot generally cannot reach a TV on your home Wi-Fi; return both devices to the same network.

If you previously used a development build and the signed beta cannot connect despite that switch being on, quit Sofa, turn its Local Network switch off, reopen Sofa, then turn that same switch on again. This resolved a stale permission after changing signing identities during beta testing. Leave other apps’ permissions unchanged.

## Address changes and automatic recovery (build 16)

Once a paired TV connects on build 16, Sofa learns its stable discovery identifiers and approved certificate. If DHCP changes its address, Sofa searches again and reconnects using the original Keychain pairing. Existing Keychain items are retained in place; their old IP-shaped account names are storage keys, not the TV's current address. Forget this TV removes the selected identity record and its pairing. App-specific playback preferences follow the same saved pairing.

Discovery sends two bounded SSDP search rounds on active private IPv4 multicast interfaces, including `ssdp:all` so VIDAA's Netflix/MDX announcements are recognized. Native Bonjour searches Android Remote Service, Google Cast, AirPlay and Samsung service advertisements. Cast/AirPlay advertisements alone do not establish remote compatibility: Sofa checks the supported TLS remote endpoint. Optional metadata failures do not hide a working endpoint when it can be verified. Candidates appear as checks finish.

Lost connections retry with backoff (5, 10, 20, 40, then 60 seconds between attempts). Each discovery round lasts up to 11 seconds; connection probes add their own timeout. Wake and network-path changes trigger a new connection attempt. Explicit disconnect, Forget, certificate approval, pairing, and denied Local Network access stop automatic recovery as appropriate. The reconnect-on-launch preference continues to control launch behavior.

Automatic address migration requires a previously learned device identifier plus the approved certificate. Friendly names, models, and certificates alone are not migration identifiers. Duplicate identity matches at different new addresses are not selected automatically. The adapter rechecks the certificate on the actual authenticated connection. A changed certificate requires approval; a TV that revoked its token still requires pairing. If upgrading while the old address is already unreachable and Sofa has never learned the TV identity, select and verify the TV once.

Discovery cannot cross client isolation, a guest network firewall, or missing macOS Local Network permission. Sleeping TVs may not advertise. Unsupported generic Android TVs without Android TV Remote Service remain unsupported. This release uses private IPv4; IPv6-only networks are not supported. Samsung and Android hardware coverage remains experimental.

## Pairing fails

Check the TV address. Show a fresh code on the TV. VIDAA codes are numeric; Android TV codes are exactly six characters and may contain A–F. In Sofa Settings, choose Pair again if an old token has stopped working. A changed certificate requires you to verify the TV before trusting it again. Do not accept an unexpected certificate merely to dismiss the prompt.

When upgrading from a development build, macOS may ask whether the newly signed Sofa can access its existing pairing token in your login Keychain. Approve it in the macOS dialog if you installed the expected Sofa build. Enter your Mac password only in that system dialog; never send it in a bug report.

## Google / Android TV setup

Choose **Google / Android TV** if automatic detection fails. Android TV Remote Service must be installed and enabled. First check whether the Google TV mobile remote can pair with that device; generic Android boxes and Fire TV do not necessarily implement this service. Root and developer mode are not needed.

A wrong six-character code can be retried. If the TV dismissed or expired it, choose **Show a new code**. If the TV revoked Sofa's pairing, choose **Pair again**. Certificate changes require explicit trust again. Sofa verifies the approved certificate on Android protocol connections; it does not silently fall back to unverified TLS.

The app shelf contains named shortcuts, not installation detection. A shortcut may fail if its app isn't installed or does not handle that link. Input-menu and channel keys are manufacturer-dependent. Volume buttons send native steps; the displayed percentage is normalized from the TV's reported level/max, when available. The glass slider is available when the TV reports volume. It translates its target into feedback-paced relative keys, so low-resolution volume ranges settle to the nearest native step. Large changes may take longer than on VIDAA. Missing acknowledgements, a ten-second movement budget or a 128-step limit stop the adjustment and switch back to −/+; reconnect to retry the slider. Physical Android TV validation is still pending.

If a TV's on-screen keyboard disappears in favor of a mobile keyboard prompt, turn off **Settings → General → Keyboard and current app updates** and reconnect. This also disables current-app reporting. Playback buttons do not imply that Sofa can read playback state.

## Samsung Tizen setup (build 13)

Samsung is experimental and has not yet been tested on physical hardware. Support starts with beta build 13. Choose **Samsung Tizen · Experimental**, keep the TV awake, and select **Allow** on its approval prompt. Saved tokens reconnect without entering a code when the firmware permits. If no prompt appears or permission was denied, check **External Device Manager → Device Connection Manager** and remove Sofa from blocked devices, then choose **Try again**. Menu names vary with firmware. **Pair again** resets Sofa's Samsung token only.

The TV must expose secure remote control on TCP 8002. Older Orsay models and TVs with only plaintext TCP 8001 remote control are outside this beta. SSDP discovery uses UDP 1900; optional device information uses HTTP TCP 8001, and the optional volume service uses the same TV's advertised UPnP port. No router port-forwarding is needed.

The slider requires a successful volume reading and advertised GetVolume/SetVolume actions with a compatible 0–100 range. When unavailable, use −/+ and mute; **Refresh TV** checks again. An unknown mute state is labelled **Toggle mute**. App catalogs are firmware-dependent; **Open Home** remains available if none is returned. Sofa does not claim an app has opened without confirmation, and this adapter does not report the active app or wake the TV from standby. Use the physical remote to wake it.

## TV is off, controls unavailable

Wake it with the physical remote. Network wake depends on firmware and network standby settings; Sofa does not promise Wake-on-LAN. Unknown means the app has no confirmed power state.

## Volume or app state is slow

The TV may acknowledge commands slowly. Sofa combines volume changes and awaits readback. Refresh TV if the displayed value is stale. App availability and launch behavior are supplied by the TV, including regional restrictions. Cached logos can still display offline; an image failure does not block control.

## Sofa is missing

Look for the couch icon in the menu bar, including hidden icons managed by other utilities. Reopen Sofa from Applications to show its panel. There is no normal Dock window. Settings → General controls optional login startup.

## Reporting a bug

Use GitHub Issues with macOS version, TV model/firmware, steps and expected/actual behavior. Redact IP addresses, serial numbers, device IDs, pairing codes and tokens. Never post Keychain exports or full protocol logs.


## Rewind and fast-forward

Sofa sends one command per press. Automatic mode uses Left/Right in YouTube on VIDAA (verified on the development TV), and native media commands elsewhere. If an app ignores its media buttons, open the remote’s **More TV controls → Rewind / fast-forward → Left / right arrows** while that app is active. Sofa remembers the choice for that TV and app. **Media buttons** explicitly restores native rewind/fast-forward; **Automatic** removes the override.

Arrow seeking requires the video player/timeline to have focus. On an app’s browsing screen it can move selection instead, and some players require OK to resume. Ads, live streams without DVR and externally connected devices may not allow seeking. These options do not establish compatibility with every streaming app; both seeking directions are physically verified only in YouTube on the tested VIDAA TV so far.
