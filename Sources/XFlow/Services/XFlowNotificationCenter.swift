import AppKit
import Foundation
import UserNotifications

@MainActor
final class XFlowNotificationCenter: NSObject, ObservableObject {
    static let shared = XFlowNotificationCenter()

    private weak var store: DeckStore?
    private var lastObservedUnreadByAccount: [UUID: Int] = [:]
    private var pendingAccountSwitchID: UUID?
    private var apnsTokenHex: String?
    private let backendClient = XFlowPushBackendClient()

    private override init() {
        super.init()
    }

    func configure(with store: DeckStore) {
        self.store = store
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        requestAuthorizationIfNeeded()
        syncRemoteRouting(accounts: store.accounts, activeAccountID: store.activeAccountID)

        if let pendingAccountSwitchID {
            activateAccount(accountID: pendingAccountSwitchID)
            self.pendingAccountSwitchID = nil
        }
    }

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                return
            }
            DispatchQueue.main.async {
                NSApp.registerForRemoteNotifications()
            }
        }
    }

    func publishUnreadNotification(count: Int, account: DeckAccount, activity: String? = nil) {
        let previousCount = lastObservedUnreadByAccount[account.id] ?? 0
        lastObservedUnreadByAccount[account.id] = count
        guard count > previousCount else {
            return
        }

        let content = UNMutableNotificationContent()
        let handle = account.handle.map { "@\($0)" } ?? account.name
        let delta = max(1, count - previousCount)
        let normalizedActivity = activity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let bodyText: String
        if let normalizedActivity, !normalizedActivity.isEmpty {
            if delta == 1 {
                bodyText = "Account \(handle) has \(normalizedActivity)."
            } else {
                bodyText = "Account \(handle) has \(delta) updates. Latest: \(normalizedActivity)."
            }
        } else {
            if delta == 1 {
                bodyText = "Account \(handle) has new activity."
            } else {
                bodyText = "Account \(handle) has \(delta) new notifications."
            }
        }

        content.title = "New X Notification"
        content.body = bodyText
        content.sound = .default
        content.userInfo = [
            "accountID": account.id.uuidString
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.15, repeats: false)
        let request = UNNotificationRequest(
            identifier: "xflow-notif-\(account.id.uuidString)-\(count)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        apnsTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let store, let token = apnsTokenHex else {
            return
        }
        backendClient.syncDeviceMapping(
            deviceToken: token,
            accounts: store.accounts,
            activeAccountID: store.activeAccountID
        )
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        NSLog("xFlow APNs registration failed: \(error.localizedDescription)")
    }

    func syncRemoteRouting(accounts: [DeckAccount], activeAccountID: UUID) {
        guard let token = apnsTokenHex else {
            return
        }
        backendClient.syncDeviceMapping(
            deviceToken: token,
            accounts: accounts,
            activeAccountID: activeAccountID
        )
    }

    func handleIncomingRemoteNotification(userInfo: [AnyHashable: Any]) {
        if let accountID = accountID(from: userInfo) {
            activateAccount(accountID: accountID)
        }
    }

    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        guard let accountID = accountID(from: response.notification.request.content.userInfo) else {
            return
        }
        activateAccount(accountID: accountID)
    }

    private func activateAccount(accountID: UUID) {
        guard let store else {
            pendingAccountSwitchID = accountID
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        store.switchAccount(to: accountID)
        store.focusOrAddNotificationsColumnFromSystemEvent()
    }

    private func accountID(from userInfo: [AnyHashable: Any]) -> UUID? {
        let keys = ["accountID", "xflowAccountID", "xflow_account_id", "account_id"]
        for key in keys {
            if let raw = userInfo[key] as? String,
               let parsed = UUID(uuidString: raw) {
                return parsed
            }
        }

        if let nested = userInfo["data"] as? [String: Any] {
            for key in keys {
                if let raw = nested[key] as? String,
                   let parsed = UUID(uuidString: raw) {
                    return parsed
                }
            }
        }
        return nil
    }
}

extension XFlowNotificationCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.handleNotificationResponse(response)
            completionHandler()
        }
    }
}
