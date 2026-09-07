import SwiftUI

struct AccountLockedDeckView: View {
    let accountName: String
    let onOpenLogin: () -> Void

    var body: some View {
        MosaicEmptyState(
            symbol: "person.crop.circle.badge.exclamationmark",
            title: "Sign in to continue",
            detail: "Complete X login for \(accountName), then every tile will return exactly where you left it."
        ) {
            Button("Open Login", action: onOpenLogin)
                .buttonStyle(MosaicButtonStyle(kind: .prominent))
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
    }
}
