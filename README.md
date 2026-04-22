# xFlow

xFlow is a native macOS multi-column app for X, inspired by the old TweetDeck workflow.

It gives you a persistent column deck for home, notifications, search, messages, bookmarks, lists, profiles, and more, with account switching and a glass-style native Mac interface.

## Download

Use the version that matches your Mac:

- **Apple Silicon**: M1, M2, M3, M4, or newer
- **Intel**: older Intel-based Macs

If you are not sure which Mac you have, open **Apple menu > About This Mac**. If it says **Chip**, use Apple Silicon. If it says **Processor: Intel**, use Intel.

## Install

1. Download the correct `.dmg` file from the GitHub Release.
2. Double-click the `.dmg` file to open it.
3. Drag `xFlow.app` into the **Applications** shortcut in the DMG window.
4. Open your **Applications** folder.
5. Double-click `xFlow.app`.

## If macOS Blocks xFlow

Because xFlow is currently distributed without Apple notarization, macOS may show this warning:

> Apple could not verify “xFlow” is free of malware that may harm your Mac or compromise your privacy.

If you see that warning:

1. Open **Apple menu > System Settings**.
2. Click **Privacy & Security** in the sidebar.
3. Scroll down to **Security**.
4. Click **Open Anyway** for xFlow.
5. Enter your Mac login password if prompted.
6. Click **OK**.

xFlow should open after that.

The **Open Anyway** button is only available for about one hour after you first try to open the app. If you do not see it, try opening `xFlow.app` again, then return to **Privacy & Security**.

## Why This Happens

xFlow is not notarized because it is currently distributed without an Apple Developer account. macOS shows this warning for non-notarized apps. This does not mean the app is malware, but you should only install apps from sources you trust.

## Updates

xFlow has a lightweight update checker. The sidebar **Check for updates** button checks this public manifest:

```text
https://raw.githubusercontent.com/distantg/xFlow/main/update-manifest.json
```

Manual checks show available updates immediately. Automatic background checks wait 7 days after a release is published before notifying users.

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
dist/Apple Silicon/xFlow.app
dist/Intel/xFlow.app
```

Build distributable DMGs:

```bash
XFLOW_ARCH=arm64 ./scripts/package_dmg.sh
XFLOW_ARCH=x86_64 ./scripts/package_dmg.sh
```

The release DMGs are created here:

```text
dist/xFlow-AppleSilicon.dmg
dist/xFlow-Intel.dmg
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

- xFlow embeds `x.com` in native WebKit columns.
- It does not require paid X API access.
- Each account uses an isolated WebKit session.
- X changes its web UI often, so some visual or filtering behavior may need maintenance over time.
