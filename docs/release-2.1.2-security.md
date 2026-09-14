# Mosaic 2.1.2 release verification

Version 2.1.2, build 193. Release notes: “Squashed some bugs.”

- All 68 Swift tests passed. The reply layout and compose opening were also checked in the Apple Silicon app during development.
- Both architecture-specific DMGs match their update ZIP contents. Bundle versions, CPU architectures, nested code signatures, update URLs, and public verification keys passed validation.
- Both update archives and appcasts passed Sparkle signature verification. Signing material stayed in Keychain.
- Gitleaks 8.30.1 found no secrets in Git history, the tracked source snapshot, or either mounted DMG. The scanner download checksum was verified.
- Additional artifact scans found no local account identities, home paths, private-key headers, common credentials, or known personal account references. No session data, diagnostic logs, screenshots, backups, or specialty builds are included.
- Intel execution and clean-machine Gatekeeper testing were not available. The apps remain ad-hoc signed and not notarized. Pattern scans do not prove absence of every possible secret encoding.

## Artifact SHA-256 hashes

- `Mosaic-2.1.2-193-arm64.zip`: `ff725c75ef2d3685d1239cd8b51914f67938eb1346454ea1cc2fe0349f142129`
- `Mosaic-2.1.2-193-x86_64.zip`: `d6267f1633c085d5d31823839f69aafb2b9784e819dd575c10ccbb36af8145bb`
- `Mosaic-AppleSilicon.dmg`: `25266e8de359fef9d4072609c154fc7c75788961278b96467801ce2a98f3eab2`
- `Mosaic-Intel.dmg`: `addd0818dba4fd1bdf20644a21a36b7c5db447f77584c657100ddb43c2fb3bc5`
