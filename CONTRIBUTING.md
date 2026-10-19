# Contributing

Small, focused pull requests and compatibility reports are welcome. Explain the behavior changed and how you checked it. Run `bash scripts/check.sh` and build the complete app before proposing a change. Preserve the bundle and Keychain identifiers so existing pairings survive upgrades.

Use native macOS controls, accessibility labels, bounded network operations and TV-confirmed state. Do not log credentials or commit device captures. Keep the bridge free of unnecessary runtime dependencies. TV app artwork is loaded from its catalog, not checked into the source tree.

Report security issues through GitHub’s private vulnerability reporting when available; do not include working credentials in public issues. See SECURITY.md.
