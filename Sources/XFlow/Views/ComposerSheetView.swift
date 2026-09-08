import SwiftUI

struct ComposerSheetView: View {
    @State private var showsLocationAccess = false
    let account: DeckAccount
    let onReady: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        WebColumnView(
            url: URL(string: "https://x.com/compose/post")!,
            refreshKey: "compose-\(account.id.uuidString)",
            accountID: account.id,
            filter: .none,
            // The composer has its own curated theme. Timeline transforms and
            // header/toolbar marking must not run inside its nested forms.
            columnAppearanceMode: .originalX,
            onComposerPresentationReady: onReady,
            onComposerDismissed: onDismiss,
            onLocationRequested: { showsLocationAccess = true },
            enableChromeStripping: false,
            enableMediaCapture: false,
            enableHandleDetection: false,
            routeHorizontalScrollToParent: false
        )
        .id("compose-\(account.id.uuidString)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Compose post")
        .sheet(isPresented: $showsLocationAccess) { LocationAccessView() }
    }
}
