# Troubleshooting

## No TV found

Wake the TV and confirm it and your Mac are on the same network. Guest Wi-Fi, client isolation, VPNs and routed networks can block discovery. Enter the TV’s address manually from Settings → Network. Sofa currently supports private IPv4 addresses and VIDAA’s MQTT remote service on TCP 36669, plus compatible UPnP volume control on TCP 18400. Some Hisense models run a different OS and are unsupported.

Allow Sofa in System Settings → Privacy & Security → Local Network. Discovery support varies by model; manual pairing is always available.

## Pairing fails

Check the TV address. Show a fresh code on the TV and enter its digits. In Sofa Settings, choose Pair again if an old token has stopped working. A changed certificate requires you to verify the TV before trusting it again. Do not accept an unexpected certificate merely to dismiss the prompt.

## TV is off, controls unavailable

Wake it with the physical remote. Network wake depends on firmware and network standby settings; Sofa does not promise Wake-on-LAN. Unknown means the app has no confirmed power state.

## Volume or app state is slow

The TV may acknowledge commands slowly. Sofa combines volume changes and awaits readback. Refresh TV if the displayed value is stale. App availability and launch behavior are supplied by the TV, including regional restrictions. Cached logos can still display offline; an image failure does not block control.

## Sofa is missing

Look for the TV icon in the menu bar, including hidden icons managed by other utilities. Reopen Sofa from Applications to show its panel. There is no normal Dock window. Settings → General controls optional login startup.

## Reporting a bug

Use GitHub Issues with macOS version, TV model/firmware, steps and expected/actual behavior. Redact IP addresses, serial numbers, device IDs, pairing codes and tokens. Never post Keychain exports or full protocol logs.
