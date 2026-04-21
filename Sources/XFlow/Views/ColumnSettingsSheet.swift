import SwiftUI

struct ColumnSettingsSheet: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss

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
        VStack(alignment: .leading, spacing: 14) {
            Text("Column Settings")
                .font(.title3.weight(.bold))

            Text(column.title)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Filters")
                    .font(.headline)

                TextField("Include keywords (comma-separated)", text: $includeKeywords)
                    .textFieldStyle(.roundedBorder)

                TextField("Exclude keywords (comma-separated)", text: $excludeKeywords)
                    .textFieldStyle(.roundedBorder)

                Toggle("Hide replies", isOn: $hideReplies)
                Toggle("Hide reposts", isOn: $hideReposts)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
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
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 500)
    }
}
