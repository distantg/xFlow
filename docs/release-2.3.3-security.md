# Mosaic 2.3.3 release verification

Version 2.3.3, build 231.

This release adds settings export/import across all configured accounts and fixes clickwheel mouse events that could move column frames without scrolling their content.

- All 113 Swift tests passed, including archive validation, multi-account transfer and persistence, and native WebKit wheel-event regression tests.
- An isolated UI import/export check preserved both sample accounts, column order, widths, titles, filters, active account, and app preferences. The pre-import backup contained the original settings.
- Both architecture DMGs match their signed update ZIP contents. Version, architecture, nested code signatures, sandbox entitlements, and update configuration passed validation.
- Both update ZIPs and appcasts passed Sparkle signature verification with the existing signing identity. Signing material remained in Keychain.
- Gitleaks and targeted privacy scans found no secrets or unresolved personal identifiers in the release source snapshot, production branch history, or exact release asset contents. Generic security-test fixtures and the home-path detection expression were reviewed.
- Commit metadata uses the public repository handle and a GitHub no-reply address. Only the production branch and the new release tag are in scope for publication.
- No user account stores, settings exports, screenshots, diagnostics, audit snapshots, or backup applications are included in the four release assets.
- The installed Apple Silicon app's executable and version metadata match the packaged release. Version 2.3.3 (231) was verified in About Mosaic; the previous installation was backed up.
- Intel execution and clean-machine Gatekeeper testing were not performed. Apps remain ad-hoc signed and not notarized. Automated scans cannot exclude every possible form of sensitive data.

## Artifact SHA-256 hashes

- `Mosaic-2.3.3-231-arm64.zip`: `c0887fbf3035c2255c44151014507209b33d9eafde9ca5556b62be8d5a984e9a`
- `Mosaic-AppleSilicon.dmg`: `e93cba3de5dd94cc6c12ea4aa12680765521655f127a27b607e02dc6311e1983`
- `Mosaic-2.3.3-231-x86_64.zip`: `e19a97d14b1277043695d8efe793667a19869dba4e9af0ff934cfe1c39d4b6cb`
- `Mosaic-Intel.dmg`: `a828136cba2f31a78abf60dc9bf67e3ceed41248b3c339e776b07d37b641b85f`
