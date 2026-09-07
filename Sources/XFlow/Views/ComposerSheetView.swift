import SwiftUI

struct ComposerSheetView: View {
    @EnvironmentObject private var store: DeckStore

    let account: DeckAccount
    let onReady: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        WebColumnView(
            url: URL(string: "https://x.com/compose/post")!,
            refreshKey: "compose-\(account.id.uuidString)",
            accountID: account.id,
            filter: .none,
            columnAppearanceMode: store.columnAppearanceMode,
            onNavigation: handleNavigation,
            onComposerPresentationReady: onReady,
            onComposerDismissed: onDismiss,
            enableChromeStripping: false,
            enableMediaCapture: false,
            enableHandleDetection: false,
            routeHorizontalScrollToParent: false
        )
        .id("compose-\(account.id.uuidString)")
        .frame(width: 980, height: 640)
        .accessibilityLabel("Compose post")
    }

    private func handleNavigation(_ url: URL?) {
        guard let url,
              url.host?.lowercased() == "x.com",
              !url.path.hasPrefix("/compose/post") else { return }
        onDismiss()
    }
}
