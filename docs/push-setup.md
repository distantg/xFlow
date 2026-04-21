# Remote Push Setup (Quit-State Support)

This app now includes APNs client plumbing and account-routing behavior:

- Device token registration from macOS app.
- Device/account mapping sync to a backend endpoint.
- Notification click routing to the matching X account inside xFlow.

To receive notifications while the app is closed, you must complete backend + signing setup below.

## 1. Start the relay backend

The repo includes a starter relay:

```bash
node ./scripts/push_relay.mjs
```

Endpoints:

- `POST /v1/devices/sync` receives device/account mappings from xFlow.
- `POST /v1/push/test` sends a test APNs notification for a specific account.

Required environment for APNs send:

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_AUTH_KEY_PATH` (path to `.p8`)
- `APNS_ENV` (`development` or `production`)

## 2. Point xFlow to the relay

Set backend URL in macOS defaults:

```bash
defaults write com.distantg.xflow xflow.pushBackendURL -string "http://localhost:8787/v1/devices/sync"
```

Or run the app with environment variable:

```bash
XFLOW_PUSH_BACKEND_URL="http://localhost:8787/v1/devices/sync" swift run XFlow
```

## 3. Build with push-capable signing

Ad-hoc signing cannot receive APNs pushes. Use a real signing identity:

```bash
XFLOW_CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
XFLOW_APS_ENVIRONMENT=development \
./scripts/package_app.sh
```

`package_app.sh` will generate entitlements with `com.apple.developer.aps-environment`.

## 4. Test routing by account

After signing and launching xFlow with at least two logged-in accounts, send a test push:

```bash
curl -X POST http://localhost:8787/v1/push/test \
  -H "Content-Type: application/json" \
  -d '{"accountID":"<ACCOUNT_UUID>","title":"Test","body":"Account scoped notification"}'
```

Expected behavior:

- If app is closed: macOS launches xFlow and selecting the notification switches to that account.
- If app is open: selecting the notification switches to that account and focuses notifications.
