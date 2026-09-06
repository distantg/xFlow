import SwiftUI

struct QuickActionPanelView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let destination: QuickPanelDestination
    let accountID: UUID

    @State private var refreshKey = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: destination.action.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MosaicTheme.activeAccent(for: colorScheme))

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.action.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Quick view")
                        .font(.caption)
                        .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                }

                Spacer()

                Button {
                    refreshKey = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(MosaicIconButtonStyle(size: 34))
                .help("Refresh")

                Button("Done") {
                    store.dismissQuickPanel()
                    dismiss()
                }
                .buttonStyle(MosaicButtonStyle(compact: true))
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MosaicSurface(level: .raised, cornerRadius: 0))

            WebColumnView(
                url: destination.url,
                refreshKey: refreshKey.uuidString,
                accountID: accountID,
                filter: .none,
                columnAppearanceMode: store.columnAppearanceMode,
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
        .background(MosaicSurface(level: .base, cornerRadius: 0))
    }
}
