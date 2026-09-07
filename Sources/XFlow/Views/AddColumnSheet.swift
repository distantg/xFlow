import SwiftUI

struct AddColumnSheet: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var type: DeckColumnType
    @State private var parameter = ""
    @State private var customTitle = ""
    @State private var includeKeywords = ""
    @State private var excludeKeywords = ""
    @State private var hideReplies = false
    @State private var hideReposts = false
    @State private var availableLists: [XListChoice] = []
    @State private var selectedListURL = ""
    @State private var isLoadingLists = false
    @State private var listLoadError: String?
    @State private var usesManualListEntry = false
    @State private var listRequestToken = UUID()
    @State private var listLoadAccountID: UUID?
    @State private var autoFilledListTitle: String?

    init(initialType: DeckColumnType) {
        _type = State(initialValue: initialType)
    }

    var body: some View {
        ZStack {
            MosaicBackdrop()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Customize \(type.defaultTitle)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Fine-tune this tile before adding it to your workspace.")
                            .font(.callout)
                            .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                    }

                    MosaicPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            fieldLabel("SOURCE", symbol: "rectangle.stack")

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.defaultTitle)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(type.summary)
                                        .font(.caption)
                                        .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                                }

                                Spacer()

                                AddColumnTypeMenu { selectedType in
                                    type = selectedType
                                } label: {
                                    Label("Change", systemImage: "chevron.up.chevron.down")
                                }
                                .buttonStyle(MosaicButtonStyle(kind: .quiet, compact: true))
                                .accessibilityLabel("Change source")
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(MosaicInsetSurface(cornerRadius: MosaicTheme.Radius.control))

                            if type == .list {
                                listSourcePicker
                            } else if let prompt = type.parameterPrompt {
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

                    HStack {
                        Spacer()
                        Button("Cancel") {
                            store.dismissAddColumnSheet()
                            dismiss()
                        }
                        .buttonStyle(
                            MosaicButtonStyle(
                                kind: .standard,
                                cornerRadius: MosaicTheme.Radius.pill
                            )
                        )

                        Button("Add to Mosaic") {
                            store.addColumn(
                                type: type,
                                parameter: parameter,
                                customTitle: customTitle,
                                filter: ColumnFilter(
                                    includeKeywords: includeKeywords,
                                    excludeKeywords: excludeKeywords,
                                    hideReplies: hideReplies,
                                    hideReposts: hideReposts
                                )
                            )
                            dismiss()
                        }
                        .buttonStyle(
                            MosaicButtonStyle(
                                kind: .prominent,
                                cornerRadius: MosaicTheme.Radius.pill
                            )
                        )
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAddColumn)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            if type == .list {
                loadListsForActiveAccount()
            }
        }
        .onChange(of: type) { selectedType in
            resetParameterForTypeChange()
            if selectedType == .list {
                loadListsForActiveAccount()
            }
        }
        .onChange(of: store.activeAccountID) { _ in
            guard type == .list else { return }
            resetListSelection()
            loadListsForActiveAccount()
        }
        .onDisappear {
            if let listLoadAccountID {
                XListDiscoveryService.shared.cancel(for: listLoadAccountID)
            }
        }
    }

    @ViewBuilder
    private var listSourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("From \(activeAccountLabel)", systemImage: "person.crop.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))

                Spacer()

                if !usesManualListEntry {
                    Button {
                        loadListsForActiveAccount(force: true)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MosaicTheme.activeAccent(for: colorScheme))
                    .disabled(isLoadingLists)
                }
            }

            if usesManualListEntry {
                TextField(
                    "List URL or list ID",
                    text: $parameter,
                    prompt: Text("https://x.com/i/lists/188887")
                )
                .textFieldStyle(MosaicTextFieldStyle())
            } else if isLoadingLists {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading Lists from \(activeAccountLabel)…")
                        .font(.callout)
                        .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if !availableLists.isEmpty {
                Picker("X List", selection: $selectedListURL) {
                    ForEach(availableLists) { list in
                        Text(list.name).tag(list.url.absoluteString)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(MosaicInsetSurface(cornerRadius: MosaicTheme.Radius.control))
                .onChange(of: selectedListURL) { newValue in
                    selectList(withURL: newValue)
                }
            } else {
                Text(listLoadError ?? "No Lists were found for \(activeAccountLabel).")
                    .font(.callout)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))

                if listLoadError != nil {
                    Button("Try Again") {
                        loadListsForActiveAccount(force: true)
                    }
                    .buttonStyle(MosaicButtonStyle(kind: .standard))
                }
            }

            Button(usesManualListEntry ? "Choose from the active account" : "Enter a List URL instead") {
                usesManualListEntry.toggle()
                if usesManualListEntry {
                    if let listLoadAccountID {
                        XListDiscoveryService.shared.cancel(for: listLoadAccountID)
                    }
                    listRequestToken = UUID()
                    listLoadAccountID = nil
                    isLoadingLists = false
                    parameter = ""
                } else if let selected = availableLists.first(where: { $0.id == selectedListURL }) {
                    applyListSelection(selected)
                } else {
                    loadListsForActiveAccount()
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MosaicTheme.activeAccent(for: colorScheme))
        }
    }

    private func fieldLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
    }

    private var canAddColumn: Bool {
        if type == .list, !usesManualListEntry {
            return availableLists.contains(where: { $0.id == selectedListURL }) &&
                !parameter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if type.requiresParameter {
            return !parameter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var activeAccountLabel: String {
        store.activeAccount?.name ?? "the active account"
    }

    private func resetParameterForTypeChange() {
        parameter = ""
        if customTitle == autoFilledListTitle {
            customTitle = ""
        }
        autoFilledListTitle = nil

        if type != .list {
            resetListSelection()
        }
    }

    private func resetListSelection() {
        if let listLoadAccountID {
            XListDiscoveryService.shared.cancel(for: listLoadAccountID)
        }
        listRequestToken = UUID()
        listLoadAccountID = nil
        availableLists = []
        selectedListURL = ""
        isLoadingLists = false
        listLoadError = nil
        usesManualListEntry = false
        parameter = ""
        if customTitle == autoFilledListTitle {
            customTitle = ""
        }
        autoFilledListTitle = nil
    }

    private func loadListsForActiveAccount(force: Bool = false) {
        guard type == .list, !usesManualListEntry else { return }

        let accountID = store.activeAccountID
        if isLoadingLists, listLoadAccountID == accountID, !force {
            return
        }

        if force, let listLoadAccountID {
            XListDiscoveryService.shared.cancel(for: listLoadAccountID)
        }

        let token = UUID()
        listRequestToken = token
        listLoadAccountID = accountID
        isLoadingLists = true
        listLoadError = nil

        XListDiscoveryService.shared.fetchLists(
            for: accountID,
            handle: store.activeAccount?.handle
        ) { result in
            guard listRequestToken == token,
                  store.activeAccountID == accountID,
                  type == .list,
                  !usesManualListEntry else {
                return
            }

            isLoadingLists = false
            listLoadAccountID = nil

            switch result {
            case .success(let lists):
                availableLists = lists
                if let retained = lists.first(where: { $0.id == selectedListURL }) {
                    applyListSelection(retained)
                } else if let first = lists.first {
                    applyListSelection(first)
                } else {
                    selectedListURL = ""
                    parameter = ""
                }
            case .failure(let error):
                availableLists = []
                selectedListURL = ""
                parameter = ""
                listLoadError = error.errorDescription
            }
        }
    }

    private func selectList(withURL url: String) {
        guard let selected = availableLists.first(where: { $0.id == url }) else { return }
        applyListSelection(selected)
    }

    private func applyListSelection(_ list: XListChoice) {
        selectedListURL = list.url.absoluteString
        parameter = list.url.absoluteString

        if customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            customTitle == autoFilledListTitle {
            customTitle = list.name
            autoFilledListTitle = list.name
        }
    }
}
