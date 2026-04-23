import SwiftUI

struct QuickActionPanelView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss

    let destination: QuickPanelDestination
    let accountID: UUID

    @State private var refreshKey = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(destination.action.title)
                    .font(.title3.weight(.bold))

                Spacer()

                Button {
                    refreshKey = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button("Done") {
                    store.dismissQuickPanel()
                    dismiss()
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)

            WebColumnView(
                url: destination.url,
                refreshKey: refreshKey.uuidString,
                accountID: accountID,
                filter: .none,
                onNavigation: { url in
                    guard destination.action == .profile else {
                        return
                    }
                    store.captureHandle(for: accountID, from: url)
                },
                onDetectedHandle: { handle in
                    store.setHandle(accountID: accountID, handle: handle)
                },
                onDetectedProfileImage: { imageURL in
                    store.setProfileImage(accountID: accountID, imageURL: imageURL)
                },
                enableChromeStripping: true,
                enableMediaCapture: true,
                enableHandleDetection: destination.action.allowsAccountMetadataDetection,
                enableAccountTextHandleDetection: destination.action == .notifications,
                enableBroadHandleDetection: destination.action == .profile
            )
        }
        .frame(minWidth: 1020, minHeight: 760)
    }
}
