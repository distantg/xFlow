import SwiftUI

struct ComposerSheetView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss

    let account: DeckAccount
    @State private var refresh = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Compose")
                    .font(.title3.weight(.bold))

                Text(account.name)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.15))
                    )

                Spacer()

                Button {
                    refresh = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button("Done") {
                    store.dismissComposer()
                    dismiss()
                }
            }
            .padding(12)
            .background(Color.black.opacity(0.2))

            WebColumnView(
                url: URL(string: "https://x.com/compose/post")!,
                refreshKey: refresh.uuidString,
                accountID: account.id,
                filter: .none,
                enableChromeStripping: false,
                enableMediaCapture: false,
                enableHandleDetection: false
            )
            .id("compose-\(account.id.uuidString)")
        }
        .frame(minWidth: 900, minHeight: 680)
    }
}
