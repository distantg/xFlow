import Foundation

enum WhatsNewPresentation {
    static let release = "2.2"
    static let storageKey = "mosaic.whatsNew.lastPresentedRelease"

    static func shouldPresent(in defaults: UserDefaults = .standard) -> Bool {
        // Read before DeckStore creates a new installation's starter account.
        let isExistingInstallation = defaults.object(forKey: "xflow.accounts.v1") != nil
            || defaults.object(forKey: "xdeck.accounts.v1") != nil
        return isExistingInstallation && defaults.string(forKey: storageKey) != release
    }

    static func markPresented(in defaults: UserDefaults = .standard) {
        defaults.set(release, forKey: storageKey)
    }
}
