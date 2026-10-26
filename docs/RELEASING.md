# Releasing Sofa

Stable releases are free GitHub releases; experimental builds use prereleases. They do not require App Store review. For a smooth download they must be Developer ID signed, accepted by Apple’s notarization service and stapled before packaging.

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
   SOFA_ARCHIVE_PATH=build/Sofa-build13.xcarchive SOFA_UPLOAD_PATH=build/notarization-build13 SOFA_TEAM_ID=TEAMID SOFA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash scripts/notarize-xcode.sh
   ```

Keep a separate archive path for every submitted build. The upload script refuses to overwrite an existing archive; inspect its status instead of resubmitting an uncertain upload.

5. After Apple finishes processing, export its accepted archive:

   ```sh
   xcodebuild -exportNotarizedApp -archivePath build/Sofa-build13.xcarchive -exportPath build/notarized-build13
   ```

6. Run `bash scripts/package.sh build/notarized-build13/Sofa.app` for the ZIP and `SOFA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash scripts/package-dmg.sh build/notarized-build13/Sofa.app` for the signed DMG containing the notarized app. This refuses to package an app without a valid staple and successful Gatekeeper assessment, then extracts the ZIP or mounts the DMG and repeats those checks on the packaged app. Both produce version/build-specific `notarized` filenames and SHA-256 files and refuse to overwrite an existing artifact. If Xcode exports a differently named folder, pass its app path to the script.
7. Commit reviewed source, tag the release, then upload the DMG, ZIP and their SHA-256 files to a GitHub release (or **prerelease** for a beta) with compatibility limits and actual validation evidence.

An alternative is `xcrun notarytool submit` using a private Keychain profile configured interactively by the account owner. Do not put Apple passwords, signing certificates with private keys, API keys or tokens in command history, issue reports, CI logs or repository secrets without separately agreeing on a CI signing setup.

The workflow in this repository builds and tests source with an ad-hoc signature. It does not possess production signing credentials, publish releases, or claim its build is notarized. Public downloads are produced locally with the procedure above.

## Isolated UI previews

Quit the existing preview, then run `bash scripts/preview.sh welcome` (or `pair`, `success`, `remote`, `network`, `trust`, `discovery`). Open `build/Sofa Preview.app` in Finder. It uses a separate bundle/preferences identity and disables the TV bridge. Navigation actions report their labels in the preview footer so target wiring can be checked without controlling a TV. These are simulated states, not proof of successful device commands. Never distribute this preview bundle as the real app.

## Explicit early previews

When an early release before notarization is intentionally authorized, use `bash scripts/package-preview.sh build/Sofa.app`. This separate path verifies Developer ID signing, packages installation guidance, and verifies the extracted app. Its filename includes the version, build, architecture and `preview`. Publish only as a GitHub prerelease with the pending notarization status visible beside download instructions. It does not establish Gatekeeper acceptance; `scripts/package.sh` keeps its stricter notarization requirements.

When Apple accepts the submitted archive, export, staple and verify it with the normal packaging path, upload the newly named notarized artifact and checksum, and update release/site copy. Do not silently replace a preview ZIP while retaining its old checksum.

## Website

Static source is in `website/`. `bash scripts/build-site.sh` stages it with the approved screenshots in `build/site/`. The Publish website workflow deploys that folder to GitHub Pages. Keep version, download URL, compatibility and notarization status aligned with the release notes.


## Automatic updates (build 15 onward)

Sofa embeds pinned Sparkle 2.10.0. Settings → Updates controls daily checks and automatic downloads, both initially enabled. Downloads install on quit; manual checks offer installation and relaunch. Scheduled prompts become a gentle reminder inside Sofa. There is no Dock icon or notification permission. Preview bundles never start Sparkle.

`Resources/Updater.plist` contains the public Ed25519 key and HTTPS feed URL. The private key is in the release Mac's login Keychain under account `com.rain.sofa.sparkle`. Never export it into source, CI, or logs. Keep the release Mac's Keychain safely backed up. Forks must generate their own key, update their feed and bundle identity, and adjust the release-script repository/team settings.

1. Resolve dependencies with `swift package resolve`. Sparkle's official tools are in `.build/artifacts/sparkle/Sparkle/bin/`.
2. Follow the signed build, Apple notarization and packaging steps above. Keep `CFBundleVersion` strictly increasing. The ZIP must contain the exact notarized `Sofa.app`.
3. Publish the GitHub release and upload the ZIP/DMG and checksums **before** changing the feed. The ZIP powers automatic updates; the website continues to offer the DMG for first installation.
4. Save reviewed release notes as a local Markdown file, then run:

   ```sh
   python3 scripts/update-feed.py dist/Sofa-0.6.0-beta.1-build15-arm64-notarized.zip --notes build/release-notes-build15.md
   ```

   This verifies the actual archived app's identity, public key, Developer ID team, notarization staple and Gatekeeper acceptance. It requires the GitHub asset's size and SHA-256 to match, generates the appcast with Sparkle, and verifies both feed and archive signatures. Draft releases, previews, duplicate/older build numbers and mismatched downloads are rejected. Optional `SPARKLE_TOOLS` may point at the official distribution's `bin` folder. No unsigned fallback is permitted.
5. Review and commit `website/appcast.xml`, then deploy through the existing GitHub Pages workflow. Do not edit the signed XML manually. `scripts/build-site.sh` copies it byte for byte.
6. Verify the live feed with `sign_update --account com.rain.sofa.sparkle --verify downloaded-appcast.xml`; exercise Check for Updates in a real installed app. For an actual upgrade test, use an isolated older build and record download, signature validation, replacement, relaunch and saved-pairing behavior separately.

An empty signed feed is valid while the first updater-enabled release awaits notarization. It offers no update and must not be described as a completed upgrade test. Users on older builds need one manual DMG installation to receive the updater. A release is not automatically published merely by committing source.


### Local updater regression test

`SOFA_SIGNING_IDENTITY='Developer ID Application: …' python3 scripts/prepare-update-lab.py` creates two separately signed copies under `build/update-lab`. They use `com.rain.sofa.updater-lab`, a loopback feed, and no saved TV address. Serve `build/update-lab/packages` on port 8771, then open `build/update-lab/installed/Sofa Update Test.app` and use Settings → Updates. Verify the installed test bundle advances from build 1 to build 2 and relaunches. Preserve the test directory as evidence; the script refuses to overwrite it.

For rejection testing, retain an untouched archive outside the served folder, flip one byte of the served ZIP without changing its length or signed feed, then attempt the update. It must report an invalid signature and leave build 1 installed. Restore the untouched ZIP and retry. For automatic installation, enable both update toggles, quit, prepare a new signed test build/feed, reset only the lab domain's `SULastCheckTime`, and relaunch: the download should complete without a window; quitting should install it. These lab packages are signed but not notarized and must never be published. The release script rejects their bundle identity.
