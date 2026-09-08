# Mosaic 2.1.1 deployment

Prepared version 2.1.1, build 187. Public release notes are exactly:

> General bug fixes.

The local preparation does not publish or push. Public appcasts, the legacy JSON manifest, and README downloads stay on v2.1 until the new release assets are available. Separate signed Apple Silicon and Intel appcasts are staged in `dist/publish/v2.1.1/activation`.

## Publish when authorized

Run from the repository root. Review `release-2.1.1-security.md`, including its runtime-test limitations, before publication. The prepared commit is recorded in `dist/publish/v2.1.1/release-commit.txt`. Do not rebuild or modify these artifacts after signing; changed artifacts require a new audit.

First verify the exact upload files:

```bash
(cd dist/publish/v2.1.1/assets && shasum -a 256 -c SHA256SUMS.txt)
```

Push the prepared commit to the release branch before creating a release. Use that exact commit as the release target:

```bash
RELEASE_COMMIT=$(cat dist/publish/v2.1.1/release-commit.txt)
gh release create v2.1.1 \
  --repo distantg/xFlow --target "$RELEASE_COMMIT" \
  --title 'Mosaic 2.1.1' \
  --notes-file dist/publish/v2.1.1/release-notes.md \
  dist/publish/v2.1.1/assets/Mosaic-AppleSilicon.dmg \
  dist/publish/v2.1.1/assets/Mosaic-Intel.dmg \
  dist/publish/v2.1.1/assets/Mosaic-2.1.1-187-arm64.zip \
  dist/publish/v2.1.1/assets/Mosaic-2.1.1-187-x86_64.zip \
  dist/publish/v2.1.1/assets/SHA256SUMS.txt
```

Verify all five release assets are publicly downloadable and match the approved hashes. Only then activate the feeds:

```bash
cp dist/publish/v2.1.1/activation/updates/arm64/appcast.xml updates/arm64/appcast.xml
cp dist/publish/v2.1.1/activation/updates/x86_64/appcast.xml updates/x86_64/appcast.xml
cp dist/publish/v2.1.1/activation/update-manifest.json update-manifest.json
```

Set the legacy manifest's `publishedAt` to the actual publication timestamp. Update README download links from `/download/v2.1/` to `/download/v2.1.1/`; a prepared README is provided as a reference, but preserve any intervening README edits. Do not edit signed appcasts. Commit the two feeds, manifest, and README and push the activation commit to `main`. Verify both raw feed URLs and check for updates from a v2.1 installation on each available architecture.

The app uses its architecture-specific feed. Existing pre-Sparkle installations still need a manual DMG upgrade once. Automatic downloads remain opt-in; users can install on quit or choose Install and Relaunch. Non-notarized installation limitations continue to apply.

Never upload backups, raw audit logs, Keychain exports, recovery material, or the whole `dist` directory.
