# Mosaic 2.2.3 release verification

Version 2.2.3, build 207.

- All 76 Swift tests passed, including last-account removal, persisted signed-out state, removal of the old layout, and preservation of the active deck when removing another account.
- Verified in an isolated app copy that the single-account actions menu is enabled and Remove Account returns to a signed-out account. No real user account was removed during verification.
- Last-account removal uses the existing deferred WebKit session purge and a new account identifier. The menu uses the same appearance for one or multiple accounts.
- Apple Silicon and Intel DMGs match their signed update ZIP contents. Versions, architectures, nested code signatures, update URLs, and public verification keys passed validation.
- Both update archives and appcasts passed Sparkle signature verification. Signing material remained in Keychain.
- Gitleaks found no secrets in Git history, the release source snapshot, or either mounted DMG.
- Artifact scans found no local identities, personal home paths, private-key headers, or common credentials. Source review found only the audit script’s generic home-path detection pattern.
- Release assets contain no account sessions, screenshots, diagnostic logs, backups, or specialty/verification builds.
- Intel execution and clean-machine Gatekeeper testing were unavailable. Apps remain ad-hoc signed and not notarized. Automated scans cannot rule out every possible encoding of sensitive data.

## Artifact SHA-256 hashes

- `Mosaic-2.2.3-207-arm64.zip`: `3be3bdc31e672efe46f44d97c8d4380277e0be576ee308326c411b8cd2822efe`
- `Mosaic-AppleSilicon.dmg`: `ae8518ad90fea7c8dfb6faf39102e67d7049026a7c30470b3752e97a8d8c84aa`
- `Mosaic-2.2.3-207-x86_64.zip`: `67028a54ad7d27d032e54885a94a52c11e2b191c9d747e8e705ddbd59e33ef8e`
- `Mosaic-Intel.dmg`: `c2ba6cda6c85c5b8b5aa86f6c30b4388988423dfc853b3a96465a718e8b6bd37`
