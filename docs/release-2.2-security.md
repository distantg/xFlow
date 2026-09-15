# Mosaic 2.2 release verification

Version 2.2, build 200.

- All 71 Swift tests passed. Ad hiding, Settings navigation, revised layouts, and once-per-update presentation were checked in the Apple Silicon app during development.
- Apple Silicon and Intel DMGs match their signed update ZIP contents. Versions, architectures, nested code signatures, update URLs, and public verification keys passed validation.
- Both update archives and appcasts passed Sparkle signature verification. Signing material remained in Keychain.
- Gitleaks found no secrets in Git history, the release source snapshot, or either mounted DMG.
- Artifact scans found no local identities, personal home paths, private-key headers, or common credentials. Source review found only the audit script's generic home-path detection pattern, not a personal path.
- No screenshots, account sessions, diagnostic logs, backups, specialty builds, or preview overrides are included in the release assets.
- Intel execution and clean-machine Gatekeeper testing were unavailable. Apps remain ad-hoc signed and not notarized. Scans cannot prove absence of every possible encoding of sensitive data.

## Artifact SHA-256 hashes

- `Mosaic-2.2-200-arm64.zip`: `8c8bdd43617345cc647e9dfb98fdeff2933ff8adb1e7cfd10d2a5cf5a2df5eb8`
- `Mosaic-2.2-200-x86_64.zip`: `67c781a65e192155b772f87269253cc56e6c01814b643040cdce8fd1b2fcbe9f`
- `Mosaic-AppleSilicon.dmg`: `579d557ba74488c2625b74ff792be85e770a72b8e24ff6eb95ed3a447e5226bf`
- `Mosaic-Intel.dmg`: `c058e8c5eeaff9344823616e6b23b2327155447961101c37e094dce6aaa9c89d`
