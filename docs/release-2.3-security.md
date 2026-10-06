# Mosaic 2.3 release verification

Version 2.3, build 218.

- All 83 Swift tests passed.
- Both architecture DMGs match their signed update ZIP contents; versions, architectures, nested code signatures, and update configuration passed validation.
- Both update ZIPs and appcasts passed Sparkle signature verification. Signing material remained in Keychain.
- Gitleaks found no secrets in scanned Git history, the release source snapshot, or either mounted DMG.
- Production source history and release contents contain no detected local personal identifiers, personal account handle, or personal home paths. The audit script's generic home-path detection pattern was reviewed as a false positive.
- Historical personal-handle fixtures remain only in a private local backup branch, excluded from the production push. Production fixtures already use example data.
- No account stores, screenshots, diagnostics, or backup applications are included in the release assets.
- Installed build 218 was verified and reopened on Apple Silicon. Intel execution, clean-machine Gatekeeper testing, and a fresh end-to-end updater installation were not performed for this release. Apps remain ad-hoc signed and not notarized. Automated scans cannot exclude every possible form of sensitive data.

## Artifact SHA-256 hashes

- `Mosaic-2.3-218-arm64.zip`: `d82ce1d077eb632001b939465a6944f09ba80c004f759508a3042f924bd1eb21`
- `Mosaic-AppleSilicon.dmg`: `3446d242c05cdea867e39e438db0230f416f34bfe454ddd7c520c211e0bb3c72`
- `Mosaic-2.3-218-x86_64.zip`: `f51951277167a369e19ba53cc15a03e444ee30ff865e3a483932785d45dc1c62`
- `Mosaic-Intel.dmg`: `59d54c3e74017a563fdd279dfa90ae726014d0be5e95ad169aff31cf15025526`
