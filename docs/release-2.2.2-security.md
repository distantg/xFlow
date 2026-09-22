# Mosaic 2.2.2 release verification

Version 2.2.2, build 206.

- All 74 Swift tests passed for the app changes; the release changes only version/build metadata and release notes.
- Google sign-in now presents guidance to use an X username/password. This response was verified in the running app; Google SSO itself is not enabled.
- Horizontal scrolling uses macOS scroller preferences and wheel-event detection. Physical traditional-mouse validation remains outstanding.
- The launch splash now uses a consistent two-second duration rather than early dismissal on fresh accounts.
- Apple Silicon and Intel DMGs match their signed update ZIP contents. Versions, architectures, nested code signatures, update URLs, and public verification keys passed validation.
- Both update archives and appcasts passed Sparkle signature verification. Signing material remained in Keychain.
- Gitleaks found no secrets in Git history, the release source snapshot, or either mounted DMG.
- Artifact scans found no local identities, personal home paths, private-key headers, or common credentials. Source review found only the audit script’s generic home-path detection pattern.
- Release assets contain no account sessions, screenshots, diagnostic logs, backups, or specialty builds.
- Intel execution and clean-machine Gatekeeper testing were unavailable. Apps remain ad-hoc signed and not notarized. Automated scans cannot rule out every possible encoding of sensitive data.

## Artifact SHA-256 hashes

- `Mosaic-2.2.2-206-arm64.zip`: `65b87b3a67d0d6b3b3eb2ac34502fd55de9487ceac1ec8700f332e9546af517b`
- `Mosaic-AppleSilicon.dmg`: `29888e331ff3db08c927a5dc099ebab15711d0372d2bdaa8866f3bbff248ce31`
- `Mosaic-2.2.2-206-x86_64.zip`: `ae96522070825e8b46e860c829e2f22eeddfd24f87a1f5efe4cdfff57646aa90`
- `Mosaic-Intel.dmg`: `83004fdbd2a4b14568a15ac16c8d97fffd5ff0cd472a52367d9d662a8ca662dc`
