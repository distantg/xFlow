import AppKit
import Foundation

final class XFlowAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        XFlowNotificationCenter.shared.requestAuthorizationIfNeeded()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            XFlowNotificationCenter.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            XFlowNotificationCenter.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { @MainActor in
            XFlowNotificationCenter.shared.handleIncomingRemoteNotification(userInfo: userInfo)
        }
    }
}
