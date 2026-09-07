import AppKit
import Foundation
import UserNotifications

@MainActor
final class XFlowNotificationCenter: NSObject, ObservableObject {
    static let shared = XFlowNotificationCenter()

    private weak var store: DeckStore?
    private var lastObservedUnreadByAccount: [UUID: Int] = [:]
    private var pendingAccountSwitchID: UUID?
    private var pendingTargetURL: URL?
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
            activateAccount(accountID: pendingAccountSwitchID, targetURL: pendingTargetURL)
            self.pendingAccountSwitchID = nil
            pendingTargetURL = nil
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

    func observeUnreadBaseline(count: Int, accountID: UUID) {
        lastObservedUnreadByAccount[accountID] = count
    }

    func publishUnreadNotification(count: Int, account: DeckAccount, activity: NotificationActivity? = nil) {
        let previousCount = lastObservedUnreadByAccount.updateValue(count, forKey: account.id)
        guard let previousCount, count > previousCount else { return }

        let content = UNMutableNotificationContent()
        let handle = account.handle.map { "@\($0)" } ?? account.name
        let delta = count - previousCount
        content.title = activity?.title ?? (delta == 1 ? "New notification" : "\(delta) new notifications")
        content.subtitle = handle
        content.body = activity?.body ?? "Open Notifications to see the latest updates."
        content.threadIdentifier = "mosaic-account-\(account.id.uuidString)"
        content.sound = .default
        content.userInfo = ["accountID": account.id.uuidString]
        if let targetURL = activity?.targetURL { content.userInfo["targetURL"] = targetURL.absoluteString }

        let request = UNNotificationRequest(
            identifier: "mosaic-activity-\(account.id.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Mosaic notification delivery failed: \(error.localizedDescription)") }
        }
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
        // Delivery alone must not steal focus or switch the user's current account.
        // The notification response delegate handles explicit clicks, including cold launch.
    }

    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        guard let accountID = accountID(from: response.notification.request.content.userInfo) else {
            return
        }
        let targetURL = NotificationActivity.validatedTargetURL(response.notification.request.content.userInfo["targetURL"] as? String)
        activateAccount(accountID: accountID, targetURL: targetURL)
    }

    private func activateAccount(accountID: UUID, targetURL: URL? = nil) {
        guard let store else {
            pendingAccountSwitchID = accountID
            pendingTargetURL = targetURL
            return
        }
        guard store.account(with: accountID) != nil else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        store.switchAccount(to: accountID)
        store.focusOrAddNotificationsColumnFromSystemEvent(targetURL: targetURL)
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
