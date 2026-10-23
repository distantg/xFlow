# Mosaic 2.3.2 release verification

Version 2.3.2, build 228.

- All 88 Swift tests passed.
- Both architecture DMGs match their signed update ZIP contents; versions, architectures, nested code signatures, and update configuration passed validation.
- Both update ZIPs and appcasts passed Sparkle signature verification. Signing material remained in Keychain.
- Gitleaks found no secrets in scanned Git history, the release source snapshot, or either mounted DMG.
- The production branch's 406 historical file blobs and current source contain no detected local personal identifiers or personal account handle. The audit script's generic home-path detector was reviewed as a false positive.
- No account stores, screenshots, diagnostics, or backup applications are included in the four approved release assets.
- Intel execution and clean-machine Gatekeeper testing were not performed. Apps remain ad-hoc signed and not notarized. Automated scans cannot exclude every possible form of sensitive data.

## Artifact SHA-256 hashes

- `Mosaic-2.3.2-228-arm64.zip`: `b5e9cfb13be587d965328b08861348abc2b28a683456196846f25ae309a02b97`
- `Mosaic-AppleSilicon.dmg`: `9b3b704da924480be8d3fd8af74b6b40bea9a259cc1d4ba08e5d825eadf5626a`
- `Mosaic-2.3.2-228-x86_64.zip`: `f9eef457ca6eca5c1e268d4db514c2d34767c3f96a8b05f35233600b7632f5f6`
- `Mosaic-Intel.dmg`: `1fc97a97e50aa0a12511a527641f49b6ddf352516befee52d85c63444ccfae53`
