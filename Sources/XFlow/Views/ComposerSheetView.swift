import SwiftUI

struct ComposerSheetView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let account: DeckAccount
    @State private var refresh = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MosaicTheme.activeAccent(for: colorScheme))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Compose")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Posting as \(account.name)")
                        .font(.caption)
                        .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                }

                Spacer()

                Button {
                    refresh = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(MosaicIconButtonStyle(size: 34))
                .help("Refresh composer")

                Button("Done") {
                    withAnimation(MosaicMotion.expressive(reduceMotion: reduceMotion)) {
                        store.dismissComposer()
                    }
                }
                .buttonStyle(MosaicButtonStyle(kind: .standard, compact: true))
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MosaicSurface(level: .raised, cornerRadius: 0))

            WebColumnView(
                url: URL(string: "https://x.com/compose/post")!,
                refreshKey: refresh.uuidString,
                accountID: account.id,
                filter: .none,
                columnAppearanceMode: store.columnAppearanceMode,
                enableChromeStripping: true,
                enableMediaCapture: false,
                enableHandleDetection: false
            )
            .id("compose-\(account.id.uuidString)")
        }
        .frame(minWidth: 900, minHeight: 680)
        .background(MosaicSurface(level: .overlay, cornerRadius: MosaicTheme.Radius.panel))
        .clipShape(RoundedRectangle(cornerRadius: MosaicTheme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MosaicTheme.Radius.panel, style: .continuous)
                .strokeBorder(MosaicTheme.activeAccent(for: colorScheme).opacity(0.32), lineWidth: 1)
        )
        .animation(MosaicMotion.micro(reduceMotion: reduceMotion), value: refresh)
    }
}
