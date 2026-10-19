# Releasing Sofa

Public betas are free GitHub prereleases. They do not require App Store review. For a smooth download they must be Developer ID signed, accepted by Apple’s notarization service and stapled before packaging.

## Local release

Use an Apple silicon Mac with an active Apple Developer membership, a Developer ID Application certificate and its private key in Keychain, and the matching account signed into Xcode. Never commit/export the private key into the repository.

1. Update app versions in `build.sh` and CHANGELOG.md.
2. Run `bash scripts/check.sh` and inspect the first-run screens, remote and dashboard. Verify the real TV connection.
3. Build with your signing identity:

   ```sh
   SOFA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' SOFA_REBUILD_HELPER=1 bash build.sh
   ```

4. Upload through Xcode’s existing account session:

   ```sh
   SOFA_TEAM_ID=TEAMID SOFA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash scripts/notarize-xcode.sh
   ```

5. After Apple finishes processing, export its accepted archive:

   ```sh
   xcodebuild -exportNotarizedApp -archivePath build/Sofa.xcarchive -exportPath build/notarized
   ```

6. Run `bash scripts/package.sh`. This refuses to package an app without a valid staple and successful Gatekeeper assessment, then extracts the ZIP and repeats those checks on the actual download. If Xcode exports a differently named folder, pass its app path to the script.
7. Commit reviewed source, tag the release, then upload the ZIP and SHA-256 file to a GitHub **prerelease** with compatibility limits and actual validation evidence.

An alternative is `xcrun notarytool submit` using a private Keychain profile configured interactively by the account owner. Do not put Apple passwords, signing certificates with private keys, API keys or tokens in command history, issue reports, CI logs or repository secrets without separately agreeing on a CI signing setup.

The workflow in this repository builds and tests source with an ad-hoc signature. It does not possess production signing credentials, publish releases, or claim its build is notarized. Public downloads are produced locally with the procedure above.

## Isolated UI previews

Quit the existing preview, then run `bash scripts/preview.sh welcome` (or `pair`, `success`, `remote`, `network`, `trust`, `discovery`). Open `build/Sofa Preview.app` in Finder. It uses a separate bundle/preferences identity and disables the TV bridge. Navigation actions report their labels in the preview footer so target wiring can be checked without controlling a TV. These are simulated states, not proof of successful device commands. Never distribute this preview bundle as the real app.

## Explicit early previews

When an early release before notarization is intentionally authorized, use `bash scripts/package-preview.sh build/Sofa.app`. This separate path verifies Developer ID signing, packages installation guidance, and verifies the extracted app. Its filename includes the version, build, architecture and `preview`. Publish only as a GitHub prerelease with the pending notarization status visible beside download instructions. It does not establish Gatekeeper acceptance; `scripts/package.sh` keeps its stricter notarization requirements.

When Apple accepts the submitted archive, export, staple and verify it with the normal packaging path, upload the newly named notarized artifact and checksum, and update release/site copy. Do not silently replace a preview ZIP while retaining its old checksum.

## Website

Static source is in `website/`. `bash scripts/build-site.sh` stages it with the approved screenshots in `build/site/`. The Publish website workflow deploys that folder to GitHub Pages. Keep version, download URL, compatibility and notarization status aligned with the release notes.
