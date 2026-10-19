# Troubleshooting

## No TV found

Wake the TV and confirm it and your Mac are on the same network. Guest Wi-Fi, client isolation, VPNs and routed networks can block discovery. Enter the TV’s address manually from Settings → Network. Sofa currently supports private IPv4 addresses and VIDAA’s MQTT remote service on TCP 36669, plus compatible UPnP volume control on TCP 18400. Google / Android TV support uses Remote Service TCP 6466 (control), TCP 6467 (pairing), and Bonjour discovery. Roku, Fire TV and Xumo are not implemented.

Allow Sofa in System Settings → Privacy & Security → Local Network. Discovery support varies by model; manual pairing is always available.

The setup screen includes **Open Privacy & Security settings**. In that pane, choose **Local Network**, allow Sofa, then return to Sofa and choose **Connect**. Sofa never changes your macOS permissions automatically. A Mac on a phone hotspot generally cannot reach a TV on your home Wi-Fi; return both devices to the same network.

If you previously used a development build and the signed beta cannot connect despite that switch being on, quit Sofa, turn its Local Network switch off, reopen Sofa, then turn that same switch on again. This resolved a stale permission after changing signing identities during beta testing. Leave other apps’ permissions unchanged.

## Pairing fails

Check the TV address. Show a fresh code on the TV. VIDAA codes are numeric; Android TV codes are exactly six characters and may contain A–F. In Sofa Settings, choose Pair again if an old token has stopped working. A changed certificate requires you to verify the TV before trusting it again. Do not accept an unexpected certificate merely to dismiss the prompt.

When upgrading from a development build, macOS may ask whether the newly signed Sofa can access its existing pairing token in your login Keychain. Approve it in the macOS dialog if you installed the expected Sofa build. Enter your Mac password only in that system dialog; never send it in a bug report.

## Google / Android TV setup

Choose **Google / Android TV** if automatic detection fails. Android TV Remote Service must be installed and enabled. First check whether the Google TV mobile remote can pair with that device; generic Android boxes and Fire TV do not necessarily implement this service. Root and developer mode are not needed.

A wrong six-character code can be retried. If the TV dismissed or expired it, choose **Show a new code**. If the TV revoked Sofa's pairing, choose **Pair again**. Certificate changes require explicit trust again. Sofa verifies the approved certificate on Android protocol connections; it does not silently fall back to unverified TLS.

The app shelf contains named shortcuts, not installation detection. A shortcut may fail if its app isn't installed or does not handle that link. Input-menu and channel keys are manufacturer-dependent. Volume buttons send native steps; the displayed percentage is normalized from the TV's reported level/max, when available. The glass slider is available when the TV reports volume. It translates its target into feedback-paced relative keys, so low-resolution volume ranges settle to the nearest native step. Large changes may take longer than on VIDAA. Missing acknowledgements, a ten-second movement budget or a 128-step limit stop the adjustment and switch back to −/+; reconnect to retry the slider. Physical Android TV validation is still pending.

If a TV's on-screen keyboard disappears in favor of a mobile keyboard prompt, turn off **Settings → General → Keyboard and current app updates** and reconnect. This also disables current-app reporting. Playback buttons do not imply that Sofa can read playback state.

## TV is off, controls unavailable

Wake it with the physical remote. Network wake depends on firmware and network standby settings; Sofa does not promise Wake-on-LAN. Unknown means the app has no confirmed power state.

## Volume or app state is slow

The TV may acknowledge commands slowly. Sofa combines volume changes and awaits readback. Refresh TV if the displayed value is stale. App availability and launch behavior are supplied by the TV, including regional restrictions. Cached logos can still display offline; an image failure does not block control.

## Sofa is missing

Look for the TV icon in the menu bar, including hidden icons managed by other utilities. Reopen Sofa from Applications to show its panel. There is no normal Dock window. Settings → General controls optional login startup.

## Reporting a bug

Use GitHub Issues with macOS version, TV model/firmware, steps and expected/actual behavior. Redact IP addresses, serial numbers, device IDs, pairing codes and tokens. Never post Keychain exports or full protocol logs.


## Rewind and fast-forward

Sofa sends one command per press. Automatic mode uses Left/Right in YouTube on VIDAA (verified on the development TV), and native media commands elsewhere. If an app ignores its media buttons, open the remote’s **More TV controls → Rewind / fast-forward → Left / right arrows** while that app is active. Sofa remembers the choice for that TV and app. **Media buttons** explicitly restores native rewind/fast-forward; **Automatic** removes the override.

Arrow seeking requires the video player/timeline to have focus. On an app’s browsing screen it can move selection instead, and some players require OK to resume. Ads, live streams without DVR and externally connected devices may not allow seeking. These options do not establish compatibility with every streaming app; both seeking directions are physically verified only in YouTube on the tested VIDAA TV so far.
