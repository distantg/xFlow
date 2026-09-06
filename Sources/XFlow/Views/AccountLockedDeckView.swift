import SwiftUI

struct AccountLockedDeckView: View {
    let accountName: String
    let onOpenLogin: () -> Void

    var body: some View {
        MosaicEmptyState(
            symbol: "person.crop.circle.badge.exclamationmark",
            title: "Sign in to continue",
            detail: "Complete X login for \(accountName), then every tile will return exactly where you left it.",
            actionTitle: "Open Login",
            action: onOpenLogin
        )
        .padding(28)
    }
}
