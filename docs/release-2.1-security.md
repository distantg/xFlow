# Mosaic 2.1 release security verification

Release: 2.1, build 171. Audit date: 2026-09-07.

## Results

- Both architecture ZIPs and mounted DMGs were inspected. App files in each DMG matched its update ZIP byte-for-byte. Bundle IDs, build/version, architecture, update URL, public key, and nested code signatures passed verification.
- Gitleaks 8.30.1: zero findings in local Git history, the source snapshot, and either mounted DMG. The official scanner archive checksum was verified before execution. Reports were redacted and retained outside version control.
- Additional byte scans of the ZIPs and mounted DMGs, including compressed filesystem metadata, found no common credential formats, private-key headers, local home paths, or local account identity strings.
- No account databases, cookies, preferences, private-key files, backup apps, test apps, or development checkout are included in the approved upload set. Required third-party license/contact information and public image provenance certificates remain.
- Ed25519 signatures on both update archives and both appcasts were cryptographically verified. Only the public verification key ships in the app. The owner confirmed saving a private-key recovery copy in Apple Passwords; the temporary plaintext export was removed.
- Swift test suite: 62 tests, zero failures. Previous isolated end-to-end tests verified manual update/relaunch, installation on quit, preserved preferences/storage, and rejection of corrupt or unavailable downloads.

## Approved upload set

Only the following four artifacts plus `SHA256SUMS.txt` are release uploads. The checksum file lists these exact hashes.

- `Mosaic-2.1-171-arm64.zip`: `e19ece1b91c8445349e116a67b78c2a7c622549e2905d1a11e80d26b5b154610`
- `Mosaic-2.1-171-x86_64.zip`: `7a30e0a22e86ea7c2b90e0f624c190148e78020f5badeb565fff0c74c1de963f`
- `Mosaic-AppleSilicon.dmg`: `114c2502ca9e75d0cb4dd4e41ea27afdda44466a83d04bf69a4c8f771078a574`
- `Mosaic-Intel.dmg`: `a4ba60aa20cfa8ba4d60fda7ca1abe3cff7a0e4eb0f9cb6db4635067a9bbe0ef`

## Limits

These checks found no confirmed PII or private credentials; pattern scanners cannot prove that every possible secret encoding is absent. The public publisher/repository identity is intentionally visible in update URLs and the bundle identifier. This was not a full application penetration test.

A clean-machine Gatekeeper test and Intel runtime test were not available on this host. Mosaic is ad-hoc signed and non-notarized; initial macOS trust warnings remain possible. The host-only library-validation exception for loading the ad-hoc Sparkle framework remains documented. No system-wide security settings were changed.

Publishing uses an explicit asset allowlist. Never upload the whole `dist` directory or Keychain/recovery material.
