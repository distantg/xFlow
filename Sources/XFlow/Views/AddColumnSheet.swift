import SwiftUI

struct AddColumnSheet: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var type: DeckColumnType = .home
    @State private var parameter = ""
    @State private var customTitle = ""
    @State private var width: Double = DeckColumn.defaultWidth
    @State private var includeKeywords = ""
    @State private var excludeKeywords = ""
    @State private var hideReplies = false
    @State private var hideReposts = false

    var body: some View {
        ZStack {
            MosaicBackdrop()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add a tile")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Choose what belongs in the next piece of your workspace.")
                            .font(.callout)
                            .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                    }

                    MosaicPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            fieldLabel("SOURCE", symbol: "rectangle.stack")
                            Picker("Column Type", selection: $type) {
                                ForEach(DeckColumnType.allCases) { option in
                                    Text(option.defaultTitle).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(MosaicInsetSurface(cornerRadius: MosaicTheme.Radius.control))

                            Text(type.summary)
                                .font(.caption)
                                .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))

                            if let prompt = type.parameterPrompt {
                                TextField(prompt, text: $parameter, prompt: Text(type.parameterPlaceholder ?? ""))
                                    .textFieldStyle(MosaicTextFieldStyle())
                            }

                            TextField("Custom title (optional)", text: $customTitle)
                                .textFieldStyle(MosaicTextFieldStyle())
                        }
                        .padding(15)
                    }

                    MosaicPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("CONTENT FILTERS", symbol: "line.3.horizontal.decrease")
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

                    MosaicPanel {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                fieldLabel("TILE WIDTH", symbol: "arrow.left.and.right")
                                Spacer()
                                Text("\(Int(width)) px")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                            }
                            Slider(value: $width, in: DeckColumn.minWidth...DeckColumn.maxWidth, step: 10)
                                .tint(MosaicTheme.activeAccent(for: colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(MosaicInsetSurface(cornerRadius: 10, isActive: true))
                        }
                        .padding(15)
                    }

                    HStack {
                        Spacer()
                        Button("Cancel") {
                            store.dismissAddColumnSheet()
                            dismiss()
                        }
                        .buttonStyle(MosaicButtonStyle(kind: .standard))

                        Button("Add to Mosaic") {
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
                        .buttonStyle(MosaicButtonStyle(kind: .prominent))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAddColumn)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 650)
        .onChange(of: type) { selectedType in
            if !selectedType.requiresParameter {
                parameter = ""
            }
        }
    }

    private func fieldLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
    }

    private var canAddColumn: Bool {
        if type.requiresParameter {
            return !parameter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
}
