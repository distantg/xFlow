# Automatic update verification — 2026-09-07

Host: Apple Silicon, macOS 15.7.9. Sparkle 2.9.2. Production release prepared as Mosaic 2.0.3, build 166.

## Passed

- Apple Silicon and Intel release builds, embedded helper/framework checks, architecture-specific feed metadata, and deep/strict code-signature verification.
- Existing Swift suite: 62 tests, zero failures. The obsolete custom JSON update evaluator tests were removed with that implementation.
- Actual Mosaic update from isolated build 163 to 164: manual check, signed download, verification, installation, and relaunch. Installed CFBundleVersion confirmed as 164.
- Actual background update from isolated build 164 to 165: automatic-download preference enabled, overdue last-check timestamp, verified download, normal quit, and CFBundleVersion confirmed as 165. No forced restart.
- Four persisted `xflow.*` preference values and four checked WebKit cookie/local-storage files matched across installation on quit.
- A same-length ZIP with one modified byte was rejected with “The update is improperly signed and could not be validated.” Installed build remained 165.
- A missing ZIP produced a download error. Installed build remained 165.
- Settings reflected persisted automatic-check/download preferences and disabled downloading when automatic checks were off.

## Findings and limits

The first ad-hoc hardened-runtime build could not load Sparkle because neither binary had an Apple Team ID. Packaging now adds the host-only library-validation exception for ad-hoc builds; the sandbox and other hardened-runtime protections remain enabled. Developer ID builds omit the exception.

The UI automation connection timed out after the first self-relaunch. A process sample showed the app's main event loop running normally; a fresh test-app launch restored UI control. The update and relaunch themselves completed and the changed build was verified.

The Intel build was validated statically, not exercised on Intel hardware. These local tests do not validate Gatekeeper behavior for a fresh download on another Mac, administrator-owned installations, all account/session configurations, or public HTTPS hosting. No GitHub release or feed was published. The production feed URLs will return an update-check error until publication.

Test artifacts are in ignored `dist/update-test/`; they use bundle ID `com.distantg.xflow.updatetest`. They are not release assets. Final release assets are in `dist/updates/`.
