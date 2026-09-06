import SwiftUI

struct ColumnSettingsSheet: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let column: DeckColumn

    @State private var includeKeywords: String
    @State private var excludeKeywords: String
    @State private var hideReplies: Bool
    @State private var hideReposts: Bool

    init(column: DeckColumn) {
        self.column = column
        _includeKeywords = State(initialValue: column.filter.includeKeywords ?? "")
        _excludeKeywords = State(initialValue: column.filter.excludeKeywords ?? "")
        _hideReplies = State(initialValue: column.filter.hideReplies)
        _hideReposts = State(initialValue: column.filter.hideReposts)
    }

    var body: some View {
        ZStack {
            MosaicBackdrop()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tune this tile")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text(column.title)
                        .font(.callout)
                        .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                }

                MosaicPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("CONTENT FILTERS", systemImage: "line.3.horizontal.decrease")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))

                        TextField("Include keywords, comma-separated", text: $includeKeywords)
                            .textFieldStyle(MosaicTextFieldStyle())
                        TextField("Exclude keywords, comma-separated", text: $excludeKeywords)
                            .textFieldStyle(MosaicTextFieldStyle())

                        HStack(spacing: 18) {
                            Toggle("Hide replies", isOn: $hideReplies)
                            Toggle("Hide reposts", isOn: $hideReposts)
                        }
                    }
                    .padding(15)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(MosaicButtonStyle())

                    Button("Save Filters") {
                        store.updateFilter(
                            for: column.id,
                            filter: ColumnFilter(
                                includeKeywords: includeKeywords,
                                excludeKeywords: excludeKeywords,
                                hideReplies: hideReplies,
                                hideReposts: hideReposts
                            )
                        )
                        dismiss()
                    }
                    .buttonStyle(MosaicButtonStyle(kind: .prominent))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 350)
    }
}
