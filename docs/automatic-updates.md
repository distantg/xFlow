# Mosaic automatic updates

Mosaic uses Sparkle 2.9.2, pinned in Package.swift and Package.resolved. The updater is shared across the main window, app menu, and Settings. Sparkle owns permission prompts, preferences, scheduling, signature verification, installation, and relaunch. Checks are every 43,200 seconds; there is no seven-day release delay. Automatic downloads default off and require user opt-in. Sparkle installs downloaded updates on quit and offers an immediate install/relaunch action.

## Signing and packaging

The private Ed25519 key lives in the macOS login Keychain under account `com.distantg.xflow.updates`. Only the public key is committed in `Config/SparklePublicKey.txt`. Do not regenerate/rotate that key for ordinary releases, export it into the repository, or upload it. Arrange a secure independent Keychain/key backup before public distribution; losing the key would prevent signing future updates for existing installations.

On the original signing Mac, resolve the dependency and inspect the existing public key with:

```bash
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.distantg.xflow.updates -p
```

Use the same scratch directory consistently. The packaging scripts default to `.build-xflow`; this integration was tested with `XFLOW_BUILD_DIR="$PWD/.build-xflow-updates"`.

```bash
XFLOW_BUILD_DIR="$PWD/.build-xflow-updates" XFLOW_ARCH=arm64 ./scripts/package_app.sh
XFLOW_BUILD_DIR="$PWD/.build-xflow-updates" XFLOW_ARCH=x86_64 ./scripts/package_app.sh
XFLOW_BUILD_DIR="$PWD/.build-xflow-updates" ./scripts/package_updates.sh
```

The host remains sandboxed. Packaging expands the bundle-specific `-spks` and `-spki` Mach lookup entitlements and enables Sparkle's installer XPC service. Nested helpers are signed inside-out, without applying host sandbox entitlements to them. The license is included in the app's Resources.

Without an Apple Developer account, ad-hoc hardened-runtime builds need the host-only `com.apple.security.cs.disable-library-validation` entitlement: neither the host nor Sparkle has an Apple Team ID to satisfy library validation. This permits loading the embedded framework but reduces the host's library-loading restriction. Developer ID builds omit this exception. Downloaded archives must still pass Ed25519 verification before extraction. There is no system-wide Gatekeeper change. Non-notarized distribution can still show macOS warnings; successful local tests are not a guarantee for every Mac or install location.

## Release outputs and publication

`dist/updates/arm64` and `dist/updates/x86_64` contain signed ZIP archives and signed appcasts. Archive names include marketing version, build, and architecture. `package_updates.sh` refuses to replace an existing archive with the same name. Never reuse a published build number or change an archive after signing.

Feed URLs are embedded separately for each architecture:

- `https://raw.githubusercontent.com/distantg/xFlow/main/updates/arm64/appcast.xml`
- `https://raw.githubusercontent.com/distantg/xFlow/main/updates/x86_64/appcast.xml`

Upload ZIPs to the GitHub release tag matching the marketing version before copying the generated appcasts to those repository paths and pushing them. Publish both architectures together. Build DMGs for new/manual installations using the existing DMG script. Preserve and update the legacy JSON manifest only after that public release exists. Until the feeds are published, the production app's manual update check will report a server error; automatic checks remain quiet on failure.

Older Mosaic versions cannot self-install this first updater-enabled release. Users must install it manually once. Accounts, WebKit stores, column layouts, and preferences stay outside the app bundle and are not migrated by this change.

## Local verification

Use a separate bundle ID and app path, never the production bundle, for simulated updates. `XFLOW_BUNDLE_ID`, `XFLOW_APP_DIR_NAME`, `XFLOW_VERSION`, `XFLOW_BUILD_NUMBER`, and `XFLOW_UPDATE_FEED_URL` support isolated packaging. A custom feed is rejected for the production bundle ID. A localhost HTTP feed also needs a test-only `NSAppTransportSecurity/NSAllowsLocalNetworking` plist setting and re-signing. Production feeds use HTTPS.

Test a newer signed archive through the actual Mosaic UI, then verify the installed CFBundleVersion and relaunch. Enable automatic checks/downloads and test installation on quit separately. Serve a modified archive with its original signature to verify rejection, and a missing archive to verify download failure. Confirm the installed build is unchanged on each failure. Snapshot isolated account/layout preferences and WebKit data before and after successful installation. Do not use real credentials in test fixtures.

Run `swift test --scratch-path .build-xflow-updates -j 2` and `python3 scripts/verify_update_package.py --require-updates` after packaging. Intel runtime verification requires an Intel Mac or a suitable Rosetta test environment; architecture and signatures can be checked locally.

## Deployment audits

For release DMGs, set `XFLOW_DMG_HEADLESS=1` when running `package_dmg.sh` to avoid Finder automation and Finder-generated layout metadata. The app and Applications shortcut are still included.

Mount both final DMGs read-only below a temporary directory as `arm64` and `x86_64`. Run `scripts/audit_release_artifacts.py --version VERSION --build BUILD --scanner /path/to/gitleaks --mount-root /path/to/mounts`. The audit checks exact ZIP/DMG app contents, architecture, signatures, unexpected bundled resources, common secrets, and local personal identifiers. It writes redacted reports and approved hashes under ignored `dist/release-audit`. Inspect any finding rather than disabling the check. Only upload files whose hashes match the approved set.
