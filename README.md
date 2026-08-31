# Mosaic

Mosaic is a native macOS multi-column app for X, inspired by the old TweetDeck workflow.

It gives you a persistent column deck for home, notifications, search, messages, bookmarks, lists, profiles, and more, with account switching and a glass-style native Mac interface.

## Download

Use the version that matches your Mac:

- **Apple Silicon**: M1, M2, M3, M4, or newer
- **Intel**: older Intel-based Macs

If you are not sure which Mac you have, open **Apple menu > About This Mac**. If it says **Chip**, use Apple Silicon. If it says **Processor: Intel**, use Intel.

## Install

1. Download the correct `.dmg` file from the GitHub Release.
2. Double-click the `.dmg` file to open it.
3. Drag `Mosaic.app` into the **Applications** shortcut in the DMG window.
4. Open your **Applications** folder.
5. Double-click `Mosaic.app`.

## If macOS Blocks Mosaic

Because Mosaic is currently distributed without Apple notarization, macOS may show this warning:

> Apple could not verify “Mosaic” is free of malware that may harm your Mac or compromise your privacy.

If you see that warning:

1. Open **Apple menu > System Settings**.
2. Click **Privacy & Security** in the sidebar.
3. Scroll down to **Security**.
4. Click **Open Anyway** for Mosaic.
5. Enter your Mac login password if prompted.
6. Click **OK**.

Mosaic should open after that.

The **Open Anyway** button is only available for about one hour after you first try to open the app. If you do not see it, try opening `Mosaic.app` again, then return to **Privacy & Security**.

## Why This Happens

Mosaic is not notarized because it is currently distributed without an Apple Developer account. macOS shows this warning for non-notarized apps. This does not mean the app is malware, but you should only install apps from sources you trust.

## Updates

Mosaic has a lightweight update checker. The sidebar **Check for updates** button checks this public manifest:

```text
https://raw.githubusercontent.com/distantg/xFlow/main/update-manifest.json
```

Manual checks show available updates immediately. Automatic background checks wait 7 days after a release is published before notifying users.

To update Mosaic, download the newest DMG, drag `Mosaic.app` into **Applications**, and choose **Replace** when Finder asks. Your accounts, login sessions, column layouts, and preferences are stored separately from the app bundle and should remain intact when replacing `Mosaic.app`.

## Security

- Each X account uses a separate WebKit website-data store. Removing an account also removes its cookies and stored website data.
- Mosaic accepts native bridge messages only from the main `https://x.com` frame. External HTTPS links open in the default browser only after a user click.
- Update and push requests use isolated, cookie-free sessions, reject redirects, and cap response sizes. The optional push relay uses separate sync and administrator credentials.
- Release builds use App Sandbox with outbound network access only, plus the macOS Hardened Runtime. On the first sandboxed launch, macOS migrates Mosaic preferences and per-account WebKit stores into its protected container so existing layouts and login sessions remain available.
- Builds are still ad-hoc signed and not notarized because the project does not currently use an Apple Developer account.

## Build From Source

Requirements:

- macOS 13 or newer
- Xcode command line tools or Xcode
- Swift Package Manager

Run locally:

```bash
swift run XFlow
```

Run tests:

```bash
swift test -j 1 --scratch-path .build-xflow
```

Build distributable apps:

```bash
XFLOW_ARCH=arm64 ./scripts/package_app.sh
XFLOW_ARCH=x86_64 ./scripts/package_app.sh
```

The packaged apps are created here:

```text
dist/Apple Silicon/Mosaic.app
dist/Intel/Mosaic.app
```

Build distributable DMGs:

```bash
XFLOW_ARCH=arm64 ./scripts/package_dmg.sh
XFLOW_ARCH=x86_64 ./scripts/package_dmg.sh
```

The release DMGs are created here:

```text
dist/Mosaic-AppleSilicon.dmg
dist/Mosaic-Intel.dmg
```

## Release Checklist

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `scripts/package_app.sh`.
2. Update `update-manifest.json` with the new version, release date, GitHub Release URL, and release notes.
3. Build both apps:

```bash
XFLOW_ARCH=arm64 ./scripts/package_app.sh
XFLOW_ARCH=x86_64 ./scripts/package_app.sh
```

4. Build each DMG:

```bash
XFLOW_ARCH=arm64 ./scripts/package_dmg.sh
XFLOW_ARCH=x86_64 ./scripts/package_dmg.sh
```

5. Create a GitHub Release, for example `v1.1`.
6. Upload both DMG files to the release.
7. Push the updated manifest so in-app update checks can find the release.

## Notes

- Mosaic embeds `x.com` in native WebKit columns.
- It does not require paid X API access.
- Each account uses an isolated WebKit session.
- X changes its web UI often, so some visual or filtering behavior may need maintenance over time.
