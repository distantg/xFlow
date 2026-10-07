# Mosaic 2.3.1 release verification

Version 2.3.1, build 222.

- All 83 Swift tests passed.
- Both architecture DMGs match their signed update ZIP contents; versions, architectures, code signatures, and update configuration passed validation.
- Both update ZIPs and appcasts passed Sparkle signature verification. Signing material remained in Keychain.
- Gitleaks found no secrets in production Git history, the release source snapshot, or either mounted DMG.
- No detected local personal identifiers, personal account handle, or personal home paths in release contents. The source audit's generic home-path detection pattern was reviewed as a false positive.
- No account stores, screenshots, diagnostics, or backup applications are included in release assets.
- Intel execution, clean-machine Gatekeeper testing, and a fresh end-to-end updater installation were not performed for this release. Apps remain ad-hoc signed and not notarized. Automated scans cannot exclude every possible form of sensitive data.

## Artifact SHA-256 hashes

- `Mosaic-2.3.1-222-arm64.zip`: `a900ba23a8e4211f21dcf8165c76e700c87a1c906f5c0895ee30e16afbe515fd`
- `Mosaic-AppleSilicon.dmg`: `7abacf0fc1c8dd2424e3280212d376c0167182c8b8e39ec468bb5a4eb9c6f5fc`
- `Mosaic-2.3.1-222-x86_64.zip`: `8439f571debe2c1ae1dcf9852403e8dc7def45457daa8bacb79871eb422d190f`
- `Mosaic-Intel.dmg`: `ba9ec68c5a5c3d3da51a36dac43c799dcd7bbb18900e0bb83d9a43813573c06b`
