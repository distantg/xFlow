# Mosaic initial development-build privacy and secret audit

This is the historical build-166 audit. See `release-2.1-security.md` for the final 2.1 release audit.

Date: 2026-09-07. Scope: prepared Mosaic 2.0.3 build 166 update ZIPs, current tracked/unignored release source, packaging scripts, and 286 file blobs reachable from local Git history. No publication was performed.

## Findings

No confirmed personal data or private credentials were found by this focused review. This is an artifact/source exposure audit, not a complete application penetration test or proof that arbitrary secrets cannot exist.

- Both ZIPs contain the app executable, expected resources, and Sparkle framework/helpers. No account databases, cookies, preferences, local-storage folders, test builds, backups, environment files, private-key files, or repository checkout were present.
- Byte scans, including UTF-16 checks for known personal identifiers, found no developer home path, local user name, or observed personal account handle in the ZIPs.
- Common private-key headers, provider credential formats, and literal credential assignments were checked in current source. Common secret patterns and personal home/name patterns were checked across 286 historical file blobs. No confirmed match was found. Unknown/custom, encoded, or split secrets are outside the guarantee of pattern scanning; a dedicated secret scanner remains a recommended independent release gate.
- Test source URL strings and icon size filenames caused email-pattern false positives. Sparkle's license includes a third-party public contact address and required copyright notices.
- The icon and splash artwork were visually reviewed. No personal content was visible. The icon has no textual/EXIF chunks. The splash includes C2PA provenance metadata identifying an AI media service and public signing certificates; these are not private signing keys or personal account credentials.
- Sparkle's public Ed25519 verification key is deliberately embedded. Its private signing key was generated in the local Keychain and is not a packaging input. No private-key export was made for this audit.
- Backend authorization is runtime configuration, not a compiled secret. The push relay is not bundled in the app; it must never be distributed with private APNs keys or server/admin tokens.
- Git history uses a public alias and GitHub noreply author address. The repository/account identifier remains visible in bundle IDs, public feed URLs, and release URLs. These identify the publisher and are not secret; changing publisher anonymity requirements requires a separate hosting/identity decision.

## Audited artifact hashes (SHA-256)

- arm64: `670d3e5c2f3e2c97b8b8136ec1961b80b47ea605f4f35ce54729f2c5d27e6936`
- x86_64: `7dd1511a84170a35ff4816b369fd3490ca38a74020bfc2b82e0d27a06bfa9d0c`

Only these exact ZIP bytes are covered by this result. Rebuilding or modifying an archive invalidates its hash/signature and requires re-audit.

## Release blockers and sequence

1. Rebuild both first-install DMGs from the final release build. The existing DMGs predate the updater integration and were not cleared by this audit. Inspect the mounted DMG contents and metadata, confirm build 166, and scan them before publishing.
2. Keep a secure backup/recovery arrangement for the update-signing key outside the repository and release directory. Never upload private key material.
3. Prepare an explicit upload allowlist: the audited architecture ZIPs, audited DMGs, and intended public release notes. Never upload the entire `dist` folder: it also contains local backups and updater test artifacts that may contain sensitive session data.
4. Create release `v2.0.3` and upload the verified artifacts first. Do not rewrite an artifact after it has been signed or published.
5. Publish the matching appcasts at `updates/arm64/appcast.xml` and `updates/x86_64/appcast.xml` on `main`. Verify the public HTTPS URLs and downloaded bytes/signatures.
6. Update the legacy `update-manifest.json` only after the manual installers are available. Older versions require one manual upgrade to gain Sparkle.
7. Test from the public feed on a clean Mac, including first-install Gatekeeper behavior, correct architecture selection, a signed update, normal quit, and relaunch. Intel runtime and fresh-machine Gatekeeper behavior have not yet been validated.

The app remains ad-hoc signed and non-notarized. Its host-only library-validation exception is documented in the automatic-update guide. Sparkle verifies signed update archives before extraction; this does not remove initial macOS trust warnings.
