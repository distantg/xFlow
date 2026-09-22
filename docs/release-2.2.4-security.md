# Mosaic 2.2.4 release verification

Version 2.2.4, build 214.

- All 76 Swift tests passed.
- Search suggestion layering and mouse selection were verified in the running app. The Kraken label was visually verified in dark and light mode.
- Both architecture DMGs match their signed update ZIP contents; versions, architecture, nested code signatures, and update configuration passed validation.
- Both update ZIPs and appcasts passed Sparkle signature verification. Signing material remained in Keychain.
- Gitleaks found no secrets in Git history, the release source snapshot, or either mounted DMG.
- Source and artifact scans found no local personal identifiers or personal home paths. Artifact scans also checked private-key headers and common credentials.
- No account stores, screenshots, diagnostics, or backup applications are included in the release assets.
- Intel execution, clean-machine Gatekeeper testing, and a fresh end-to-end updater installation were not performed for this release. Apps remain ad-hoc signed and not notarized. Automated scans cannot exclude every possible form of sensitive data.

## Artifact SHA-256 hashes

- `Mosaic-2.2.4-214-arm64.zip`: `ddafbc909f7d70479ab81fedbe0b41481b5534151d2b8e33a4efb3a623199e69`
- `Mosaic-AppleSilicon.dmg`: `088abc4939dba6b5ca03c36b9ea08807d4e4af6abc671260dc394ba41eb5782f`
- `Mosaic-2.2.4-214-x86_64.zip`: `bbe22dc93badfaaa0dd786575b593b29f79394a8b3e1c8ac43d7350795029a60`
- `Mosaic-Intel.dmg`: `0dda9183fa14d8419b98702dad2790fe1d39da40f0c04a050bde2dde4425719f`
