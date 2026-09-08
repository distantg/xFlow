# Mosaic 2.1.1 release security verification

Release: 2.1.1, build 187. Audit date: 2026-09-07 (local time).

## Results

- Gitleaks 8.30.1 found no secrets in local Git history, the source snapshot, or either mounted release DMG. Its distribution archive checksum matched the official checksum list. Redacted reports are retained under ignored `dist/release-audit`.
- Additional ZIP/DMG byte scans found no private-key headers, common credential formats, local home paths, or local account identities. Compressed metadata was included. The source scan matched the audit script's own home-path regex; review confirmed this was a detector literal, not PII. A separate known personal social-handle scan found no matches in the source snapshot or ZIP contents.
- Each DMG's app matches its architecture's ZIP byte-for-byte. Bundle versions, architecture, public key, feed URLs, embedded Sparkle framework/helpers, entitlements, and nested code signatures passed verification.
- Both update archives and both appcasts passed cryptographic Ed25519 verification. Private signing material remains in Keychain and was not exported. Only the public verification key ships.
- No account databases, cookies, preferences, recovery material, backup apps, test apps, or development checkout are in the approved release assets. Public publisher identity and required third-party license/provenance information remain.
- All 66 Swift tests passed. Native location authorization and composer interactions were exercised during the preceding fixes. Intel packaging was verified statically; Intel runtime testing was unavailable.

## Approved artifact hashes

- `Mosaic-2.1.1-187-arm64.zip`: `b813cef9e01110dd7053bab6e8fd922b83b6ba5e2fcd5f4acf4a4c8b15cddec9`
- `Mosaic-2.1.1-187-x86_64.zip`: `ece6392e197ca22350e6e1d610e7ca8c3ae2988d084ce35417092a545bdcd2b6`
- `Mosaic-AppleSilicon.dmg`: `ac28139589b5798522f59ddfaf9ca25f2d3cd9e9b14792c351439cecf2021054`
- `Mosaic-Intel.dmg`: `764f3434c5101eff79163ca2b831e980400c98876f3c203439d64bd7f6e4cc79`

## Verification limits

This is a source and distribution privacy/secret audit, not a full penetration test. Pattern scans cannot prove every possible secret encoding is absent. Live Grok end-to-end verification remained limited by a UI automation timeout; navigation policy and popup/draft handling were checked separately. A clean-machine Gatekeeper test was unavailable. The app remains ad-hoc signed and non-notarized, with the existing host-only library-validation exception.

The prior Sparkle installation/relaunch and failure-path results are documented in `automatic-updates-verification.md`; those full scenarios were not repeated for build 187. This release's exact archives, feeds, bundles, and signatures were verified anew.

Upload only the four listed artifacts plus `SHA256SUMS.txt` from `dist/publish/v2.1.1/assets`. Never upload the entire `dist` directory.
