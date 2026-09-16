# Mosaic 2.2.1 release verification

Version 2.2.1, build 204.

- All 73 remaining Swift tests passed after removing the two obsolete What’s New presentation tests. Rapid-scroll update coalescing and media gallery validation are covered.
- Removed the What’s New overlay and its presentation tracking. The regular launch screen remains.
- Apple Silicon and Intel DMGs match their signed update ZIP contents. Versions, architectures, nested code signatures, update URLs, and public verification keys passed validation.
- Both update archives and appcasts passed Sparkle signature verification. Signing material remained in Keychain.
- Gitleaks found no secrets in Git history, the release source snapshot, or either mounted DMG.
- Artifact scans found no local identities, personal home paths, private-key headers, or common credentials. Source review found only the audit script’s generic home-path detection pattern.
- Release assets contain no account sessions, screenshots, diagnostic logs, backups, or specialty builds.
- Intel execution and clean-machine Gatekeeper testing were unavailable. Apps remain ad-hoc signed and not notarized. Automated scans cannot rule out every possible encoding of sensitive data. The latest scroll optimization passed regression tests; elimination of the reported live dragging jitter has not been confirmed.

## Artifact SHA-256 hashes

- `Mosaic-2.2.1-204-arm64.zip`: `f6154660be264ded2f82d97be8787c7fadeb1e915b36db329e943062d4fb37c4`
- `Mosaic-2.2.1-204-x86_64.zip`: `b0cc2ef4a494bd3cbd024f743487c554062bfccd7aa219adeebb3f5bd5603b2e`
- `Mosaic-AppleSilicon.dmg`: `7fba1752b64393766fbc155e377af38f674baa4a47610d754909f15b7cce4110`
- `Mosaic-Intel.dmg`: `c00a11583e1915d1ce4c1eabe947d139cb4aad8b5ee457c599069b889996fb63`
