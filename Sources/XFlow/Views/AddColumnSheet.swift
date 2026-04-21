import SwiftUI

struct AddColumnSheet: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss

    @State private var type: DeckColumnType = .home
    @State private var parameter = ""
    @State private var customTitle = ""
    @State private var width: Double = DeckColumn.defaultWidth
    @State private var includeKeywords = ""
    @State private var excludeKeywords = ""
    @State private var hideReplies = false
    @State private var hideReposts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Column")
                .font(.title2.weight(.bold))

            Picker("Column Type", selection: $type) {
                ForEach(DeckColumnType.allCases) { option in
                    Text(option.defaultTitle).tag(option)
                }
            }
            .pickerStyle(.menu)

            Text(type.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let prompt = type.parameterPrompt {
                TextField(prompt, text: $parameter, prompt: Text(type.parameterPlaceholder ?? ""))
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Custom column title (optional)", text: $customTitle)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Optional content filters")
                    .font(.headline)

                TextField("Include keywords (comma-separated)", text: $includeKeywords)
                    .textFieldStyle(.roundedBorder)

                TextField("Exclude keywords (comma-separated)", text: $excludeKeywords)
                    .textFieldStyle(.roundedBorder)

                Toggle("Hide replies", isOn: $hideReplies)
                Toggle("Hide reposts", isOn: $hideReposts)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Column Width")
                    Spacer()
                    Text("\(Int(width)) px")
                        .foregroundStyle(.secondary)
                }

                Slider(value: $width, in: DeckColumn.minWidth...DeckColumn.maxWidth, step: 10)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    store.dismissAddColumnSheet()
                    dismiss()
                }

                Button("Add Column") {
                    store.addColumn(
                        type: type,
                        parameter: parameter,
                        customTitle: customTitle,
                        width: width,
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
                .disabled(!canAddColumn)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onChange(of: type) { selectedType in
            if !selectedType.requiresParameter {
                parameter = ""
            }
        }
    }

    private var canAddColumn: Bool {
        if type.requiresParameter {
            return !parameter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
}
