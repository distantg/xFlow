import AppKit
import Foundation

@MainActor
final class DeckStore: ObservableObject {
    @Published var columns: [DeckColumn] {
        didSet {
            guard !isHydratingColumns else {
                return
            }
            persistColumns()
        }
    }

    @Published var accounts: [DeckAccount] {
        didSet {
            persistAccounts()
            pruneSettingsImportAliases()
        }
    }

    @Published var activeAccountID: UUID {
        didSet {
            defaults.set(activeAccountID.uuidString, forKey: activeAccountStorageKey)
        }
    }

    @Published var appearanceMode: AppAppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: appearanceModeStorageKey)
        }
    }

    @Published var columnAppearanceMode: ColumnAppearanceMode {
        didSet {
            ColumnAppearancePreference.save(columnAppearanceMode, to: defaults)
        }
    }

    @Published var presentedLoginAccountID: UUID?
    @Published var quickPanelDestination: QuickPanelDestination?
    @Published var scrollTargetColumnID: UUID?
    @Published private(set) var notificationNavigationURLs: [UUID: URL] = [:]

    @Published var refreshSignal = UUID()
    @Published private(set) var layoutResetSignal = UUID()
    @Published var isAddColumnSheetPresented = false
    @Published private(set) var addColumnInitialType: DeckColumnType = .home
    @Published var isComposerSheetPresented = false

    private let defaults: UserDefaults
    private let columnsStorageKey = "xflow.columns.v3"
    private let legacyColumnsStorageKey = "xdeck.columns.v3"
    private let columnsByAccountStorageKey = "xflow.columnsByAccount.v1"
    private let legacyColumnsByAccountStorageKey = "xdeck.columnsByAccount.v1"
    private let accountsStorageKey = "xflow.accounts.v1"
    private let legacyAccountsStorageKey = "xdeck.accounts.v1"
    private let activeAccountStorageKey = "xflow.activeAccountID.v1"
    private let legacyActiveAccountStorageKey = "xdeck.activeAccountID.v1"
    private let appearanceModeStorageKey = "xflow.appearanceMode.v1"
    private let legacyAppearanceModeStorageKey = "xdeck.appearanceMode.v1"
    private let settingsImportAliasesStorageKey = "xflow.settingsImportAliases.v1"
    private var profileMetaRefreshInFlight: Set<UUID> = []
    private var profileMetaRetryCount: [UUID: Int] = [:]
    private var columnsByAccount: [String: [DeckColumn]] = [:]
    private var isHydratingColumns = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        columns = DeckColumn.starterColumns

        let loadedAccounts = Self.loadAccounts(from: defaults, key: accountsStorageKey)
            ?? Self.loadAccounts(from: defaults, key: legacyAccountsStorageKey)
            ?? []
        if loadedAccounts.isEmpty {
            let first = DeckAccount(fallbackName: "Account 1", requiresLogin: true)
            accounts = [first]
            activeAccountID = first.id
        } else {
            accounts = loadedAccounts

            if let rawActive = defaults.string(forKey: activeAccountStorageKey)
                ?? defaults.string(forKey: legacyActiveAccountStorageKey),
               let parsed = UUID(uuidString: rawActive),
               loadedAccounts.contains(where: { $0.id == parsed }) {
                activeAccountID = parsed
            } else {
                activeAccountID = loadedAccounts[0].id
            }
        }

        if let rawAppearance = defaults.string(forKey: appearanceModeStorageKey)
            ?? defaults.string(forKey: legacyAppearanceModeStorageKey),
           let parsedAppearance = AppAppearanceMode(rawValue: rawAppearance) {
            appearanceMode = parsedAppearance
        } else {
            appearanceMode = .dark
        }

        columnAppearanceMode = ColumnAppearancePreference.load(from: defaults)

        columnsByAccount = Self.loadColumnsByAccount(from: defaults, key: columnsByAccountStorageKey)
            ?? Self.loadColumnsByAccount(from: defaults, key: legacyColumnsByAccountStorageKey)
            ?? [:]
        pruneColumnLayoutsForExistingAccounts()
        // Migrate pre-account layouts into the currently active account.
        if columnsByAccount.isEmpty,
           let legacy = Self.loadColumns(from: defaults, key: columnsStorageKey)
            ?? Self.loadColumns(from: defaults, key: legacyColumnsStorageKey),
           !legacy.isEmpty {
            columnsByAccount[activeAccountID.uuidString] = legacy
            persistColumnsByAccount()
        }

        loadColumnsForActiveAccount()
        persistAccounts()
        pruneSettingsImportAliases()
        defaults.set(activeAccountID.uuidString, forKey: activeAccountStorageKey)
        defaults.set(appearanceMode.rawValue, forKey: appearanceModeStorageKey)

        // MainDeckView restores the active web session behind the launch splash
        // before loading columns or deciding whether a sign-in sheet is needed.
    }

    var activeAccount: DeckAccount? {
        accounts.first(where: { $0.id == activeAccountID })
    }

    func account(with id: UUID) -> DeckAccount? {
        accounts.first(where: { $0.id == id })
    }

    func presentAddColumnSheet(type: DeckColumnType = .home) {
        addColumnInitialType = type
        isAddColumnSheetPresented = true
    }

    func dismissAddColumnSheet() {
        isAddColumnSheetPresented = false
    }

    func presentComposer() {
        isComposerSheetPresented = true
    }

    func dismissComposer() {
        isComposerSheetPresented = false
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        appearanceMode = mode
    }

    func setColumnAppearanceMode(_ mode: ColumnAppearanceMode) {
        columnAppearanceMode = mode
    }

    func settingsArchive(
        automaticallyChecksForUpdates: Bool,
        automaticallyDownloadsUpdates: Bool
    ) -> MosaicSettingsArchive {
        MosaicSettingsArchive(
            activeAccountID: activeAccountID,
            preferences: .init(
                appearanceMode: appearanceMode,
                columnAppearanceMode: columnAppearanceMode,
                hideAds: defaults.bool(forKey: TimelineAdHiding.storageKey),
                automaticallyChecksForUpdates: automaticallyChecksForUpdates,
                automaticallyDownloadsUpdates: automaticallyDownloadsUpdates
            ),
            accounts: accounts.map { account in
                .init(
                    id: account.id,
                    fallbackName: account.fallbackName,
                    handle: account.handle,
                    columns: account.id == activeAccountID
                        ? columns
                        : columnsByAccount[account.id.uuidString] ?? DeckColumn.starterColumns
                )
            }
        )
    }

    /// Matching by handle lets a layout follow an account signed in on another Mac.
    /// An ID alone must never associate a different identity with a local session.
    private func settingsAccountMatches(in archive: MosaicSettingsArchive) -> [UUID: DeckAccount] {
        var matches: [UUID: DeckAccount] = [:]
        var usedIDs = Set<UUID>()
        // Reserve exact matches first, including duplicate sign-ins of one handle.
        for saved in archive.accounts {
            if let exact = accounts.first(where: {
                $0.id == saved.id && $0.handle?.lowercased() == saved.handle?.lowercased()
            }) {
                matches[saved.id] = exact
                usedIDs.insert(exact.id)
            }
        }
        // A source slot may not have had a handle when it was first imported.
        // Remember its local slot even after sign-in supplies that identity, or
        // after a source UUID collision required assigning a different UUID.
        let aliases = settingsImportAliases
        for saved in archive.accounts where matches[saved.id] == nil {
            guard let rawID = aliases[settingsImportAliasKey(for: saved)],
                  let localID = UUID(uuidString: rawID),
                  !usedIDs.contains(localID),
                  let existing = accounts.first(where: { $0.id == localID }),
                  saved.handle == nil || saved.handle?.lowercased() == existing.handle?.lowercased() else {
                continue
            }
            matches[saved.id] = existing
            usedIDs.insert(existing.id)
        }
        for saved in archive.accounts where matches[saved.id] == nil {
            guard let handle = saved.handle?.lowercased(),
                  let existing = accounts.first(where: {
                      !usedIDs.contains($0.id) && $0.handle?.lowercased() == handle
                  }) else { continue }
            matches[saved.id] = existing
            usedIDs.insert(existing.id)
        }
        return matches
    }

    func matchingSettingsAccountCount(in archive: MosaicSettingsArchive) -> Int {
        settingsAccountMatches(in: archive).count
    }

    func importSettings(_ archive: MosaicSettingsArchive) throws {
        // Validate the complete document before changing any persisted preference.
        try archive.validate()

        var importedAccounts: [DeckAccount] = []
        var importedLayouts: [String: [DeckColumn]] = [:]
        var importedActiveID: UUID?
        var usedIDs = Set(accounts.map(\.id))
        var aliases = settingsImportAliases
        let matches = settingsAccountMatches(in: archive)
        for saved in archive.accounts {
            var account: DeckAccount
            if let existing = matches[saved.id] {
                // Keep this Mac's authentication state, avatar, and WebKit store.
                account = existing
                account.fallbackName = saved.fallbackName
            } else {
                // New slots always need a local sign-in. Keep the source ID when
                // available so repeat imports also match accounts without handles.
                let id = usedIDs.contains(saved.id) ? UUID() : saved.id
                account = DeckAccount(
                    id: id,
                    fallbackName: saved.fallbackName,
                    handle: saved.handle,
                    requiresLogin: true
                )
            }
            usedIDs.insert(account.id)
            aliases[settingsImportAliasKey(for: saved)] = account.id.uuidString
            importedAccounts.append(account)
            // Fresh column IDs discard transient navigation and rendering state.
            importedLayouts[account.id.uuidString] = saved.columns.map {
                DeckColumn(type: $0.type, parameter: $0.parameter, customTitle: $0.customTitle,
                           width: $0.width, filter: $0.filter)
            }
            if saved.id == archive.activeAccountID { importedActiveID = account.id }
        }

        let importedIDs = Set(importedAccounts.map(\.id))
        let emptyInitialSlot = pristineInitialAccountID
        let otherAccounts = accounts.filter {
            !importedIDs.contains($0.id) && $0.id != emptyInitialSlot
        }
        var layouts = columnsByAccount
        layouts[activeAccountID.uuidString] = columns
        if let emptyInitialSlot, !importedIDs.contains(emptyInitialSlot) {
            layouts.removeValue(forKey: emptyInitialSlot.uuidString)
        }
        layouts.merge(importedLayouts, uniquingKeysWith: { _, imported in imported })

        let mergedAccounts = importedAccounts + otherAccounts
        let mergedActiveID = importedActiveID ?? importedAccounts[0].id
        guard mergedAccounts.count <= 100 else { throw SettingsImportError.tooManyAccounts }
        let mergedArchive = MosaicSettingsArchive(
            activeAccountID: mergedActiveID,
            preferences: archive.preferences,
            accounts: mergedAccounts.map { account in
                .init(id: account.id, fallbackName: account.fallbackName, handle: account.handle,
                      columns: layouts[account.id.uuidString] ?? DeckColumn.starterColumns)
            }
        )
        do {
            // A valid file can still exceed limits when merged with accounts
            // already on this Mac. Keep the resulting workspace exportable.
            _ = try mergedArchive.encoded()
        } catch {
            throw SettingsImportError.workspaceCannotBeExported(error.localizedDescription)
        }
        let mergedIDs = Set(mergedAccounts.map { $0.id.uuidString })
        aliases = aliases.filter { mergedIDs.contains($0.value) }

        presentedLoginAccountID = nil
        isAddColumnSheetPresented = false
        isComposerSheetPresented = false
        quickPanelDestination = nil
        scrollTargetColumnID = nil
        notificationNavigationURLs = [:]
        columnsByAccount = layouts
        accounts = mergedAccounts
        activeAccountID = mergedActiveID
        loadColumnsForActiveAccount()
        persistColumnsByAccount()
        appearanceMode = archive.preferences.appearanceMode
        columnAppearanceMode = archive.preferences.columnAppearanceMode
        defaults.set(archive.preferences.hideAds, forKey: TimelineAdHiding.storageKey)
        defaults.set(aliases, forKey: settingsImportAliasesStorageKey)
        refreshAllColumns()
    }

    private var settingsImportAliases: [String: String] {
        defaults.dictionary(forKey: settingsImportAliasesStorageKey) as? [String: String] ?? [:]
    }

    private func settingsImportAliasKey(for account: MosaicSettingsArchive.Account) -> String {
        account.id.uuidString + ":" + (account.handle?.lowercased() ?? "")
    }

    private func pruneSettingsImportAliases() {
        let aliases = settingsImportAliases
        let accountIDs = Set(accounts.map { $0.id.uuidString })
        let retained = aliases.filter { accountIDs.contains($0.value) }
        if retained != aliases {
            defaults.set(retained, forKey: settingsImportAliasesStorageKey)
        }
    }

    enum SettingsImportError: LocalizedError {
        case tooManyAccounts
        case workspaceCannotBeExported(String)

        var errorDescription: String? {
            switch self {
            case .tooManyAccounts:
                return "Importing these settings would exceed Mosaic's limit of 100 accounts in a settings file. Remove unused accounts and try again. No settings were changed."
            case .workspaceCannotBeExported(let reason):
                return "Importing these settings would make the combined workspace too large or invalid to export. No settings were changed. \(reason)"
            }
        }
    }

    private var pristineInitialAccountID: UUID? {
        guard accounts.count == 1, let account = accounts.first,
              account.requiresLogin, account.handle == nil, account.profileImageURL == nil,
              account.fallbackName == "Account 1",
              columns.count == DeckColumn.starterColumns.count else { return nil }
        let unchanged = zip(columns, DeckColumn.starterColumns).allSatisfy { column, starter in
            column.type == starter.type && column.parameter == starter.parameter &&
            column.customTitle == starter.customTitle && column.width == starter.width &&
            column.filter == starter.filter
        }
        return unchanged ? account.id : nil
    }

    func presentQuickAction(_ action: XSidebarAction) {
        if action == .compose {
            presentComposer()
            return
        }

        guard let url = action.url(forHandle: activeAccount?.handle) else {
            return
        }

        quickPanelDestination = QuickPanelDestination(action: action, url: url)
    }

    func dismissQuickPanel() {
        quickPanelDestination = nil
    }

    func handleSidebarAction(_ action: XSidebarAction) {
        switch action {
        case .home:
            ensureHomeColumnAndScroll()
        case .search:
            addSearchColumnAndScroll()
        case .notifications:
            focusOrAddColumn(type: .notifications, defaultWidth: 360)
        case .messages:
            focusOrAddColumn(type: .messages, defaultWidth: 360)
        case .bookmarks:
            focusOrAddColumn(type: .bookmarks, defaultWidth: 360)
        case .creatorStudio:
            focusOrAddListsColumn()
        case .articles:
            if let url = action.url(forHandle: activeAccount?.handle),
               TrustedURLPolicy.isTrustedExternalWebURL(url) {
                NSWorkspace.shared.open(url)
            }
        case .compose:
            presentComposer()
        case .profile, .more:
            presentQuickAction(action)
        }
    }

    func addAccount() {
        let account = DeckAccount(fallbackName: "Account \(accounts.count + 1)", requiresLogin: true)
        accounts.append(account)
        columnsByAccount[account.id.uuidString] = DeckColumn.starterColumns
        persistColumnsByAccount()
        switchAccount(to: account.id)
        presentLoginFlow(for: account.id)
    }

    func removeAccount(_ accountID: UUID) {
        guard let removeIndex = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }

        let removingActive = activeAccountID == accountID
        AccountAvatarStorage.shared.remove(accountID)
        // Keep an empty slot for the app's non-optional active account without
        // retaining the removed account's identity, cookies, or column layout.
        let removedLastAccount = accounts.count == 1
        if removedLastAccount {
            accounts = [DeckAccount(fallbackName: "Account 1", requiresLogin: true)]
        } else {
            accounts.remove(at: removeIndex)
        }
        profileMetaRefreshInFlight.remove(accountID)
        profileMetaRetryCount.removeValue(forKey: accountID)
        columnsByAccount.removeValue(forKey: accountID.uuidString)
        persistColumnsByAccount()

        if presentedLoginAccountID == accountID {
            presentedLoginAccountID = nil
        }

        if removingActive {
            isComposerSheetPresented = false
            quickPanelDestination = nil
            notificationNavigationURLs = [:]
            let fallbackIndex = min(removeIndex, max(0, accounts.count - 1))
            let fallbackID = accounts[fallbackIndex].id
            activeAccountID = fallbackID
            loadColumnsForActiveAccount()
            refreshAllColumns()
            if !removedLastAccount {
                refreshAuthenticationState(for: fallbackID, shouldPromptIfNeeded: true)
            }
        }

        // Let SwiftUI dismantle any visible web views before deleting the persistent WebKit store.
        DispatchQueue.main.async {
            WebSessionPool.shared.purgeAccount(accountID)
        }
    }

    func switchAccount(to accountID: UUID) {
        guard accounts.contains(where: { $0.id == accountID }) else {
            return
        }

        persistColumns()
        activeAccountID = accountID
        loadColumnsForActiveAccount()
        refreshAllColumns()
        refreshAuthenticationState(for: accountID, shouldPromptIfNeeded: true)
        refreshProfileMetadataIfNeeded(for: accountID, force: true)
    }

    func presentLoginFlow(for accountID: UUID) {
        guard accounts.contains(where: { $0.id == accountID }) else {
            return
        }
        presentedLoginAccountID = accountID
    }

    func dismissLoginFlow() {
        presentedLoginAccountID = nil
    }

    func markAccountSignedIn(accountID: UUID) {
        updateAccount(accountID) { account in
            account.requiresLogin = false
        }

        if presentedLoginAccountID == accountID {
            presentedLoginAccountID = nil
        }

        refreshAllColumns()
        refreshProfileMetadataIfNeeded(for: accountID, force: true)
    }

    func completeLaunchSessionRestoration(accountID: UUID, authenticated: Bool) {
        guard activeAccountID == accountID else { return }
        AccountAvatarSession.shared.setAuthenticated(authenticated, accountID: accountID)
        updateAccount(accountID) { $0.requiresLogin = !authenticated }
        presentedLoginAccountID = authenticated ? nil : accountID
        if authenticated {
            refreshProfileMetadataIfNeeded(for: accountID, force: true)
        }
    }

    func refreshAuthenticationState(
        for accountID: UUID,
        shouldPromptIfNeeded: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard accounts.contains(where: { $0.id == accountID }) else {
            completion?(false)
            return
        }

        WebSessionPool.shared.appearsAuthenticated(accountID: accountID) { [weak self] authenticated in
            guard let self else {
                completion?(authenticated)
                return
            }

            self.updateAccount(accountID) { account in
                account.requiresLogin = !authenticated
            }

            if authenticated {
                if self.presentedLoginAccountID == accountID {
                    self.presentedLoginAccountID = nil
                }
                self.refreshProfileMetadataIfNeeded(for: accountID, force: true)
            } else if shouldPromptIfNeeded {
                self.presentedLoginAccountID = accountID
            }

            completion?(authenticated)
        }
    }

    func captureHandle(for accountID: UUID, from url: URL?) {
        // Navigation can lead to anyone's profile or post. Verify the viewer
        // through account controls instead of adopting the visited username.
        refreshProfileMetadataIfNeeded(for: accountID, force: false)
    }

    func captureListMetadata(for columnID: UUID, from url: URL?, pageTitle: String?) {
        guard let index = columns.firstIndex(where: { $0.id == columnID }),
              columns[index].type == .list else {
            return
        }

        let effectiveURL = url ?? columns[index].url
        guard let listRoute = Self.extractListRoute(from: effectiveURL) else {
            return
        }

        let resolvedTitle = Self.normalizedListTitle(pageTitle)
            ?? listRoute.titleHint
            ?? columns[index].customTitle
            ?? "Lists"

        let oldParameter = columns[index].parameter?.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldTitle = columns[index].customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard oldParameter != listRoute.parameter || oldTitle != resolvedTitle else {
            return
        }

        columns[index].parameter = listRoute.parameter
        columns[index].customTitle = resolvedTitle
    }

    func setHandle(accountID: UUID, handle: String) {
        let normalized = handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()

        guard TrustedURLPolicy.isValidXHandle(normalized) else {
            return
        }

        updateAccount(accountID) { account in
            account.handle = normalized
            if account.profileImageURL?.isEmpty != false {
                account.profileImageURL = "https://x.com/\(normalized)/profile_image?size=normal"
            }
        }

        refreshProfileMetadataIfNeeded(for: accountID, force: false)
    }

    func setProfileImage(accountID: UUID, imageURL: URL?) {
        guard let imageURL else {
            return
        }

        guard TrustedURLPolicy.isTrustedProfileImageURL(imageURL) else {
            return
        }

        let raw = imageURL.absoluteString

        updateAccount(accountID) { account in
            account.profileImageURL = raw
        }
        profileMetaRetryCount[accountID] = 0
    }

    func addColumn(
        type: DeckColumnType,
        parameter: String?,
        customTitle: String?,
        filter: ColumnFilter
    ) {
        columns.append(
            DeckColumn(
                type: type,
                parameter: parameter,
                customTitle: customTitle,
                filter: filter
            )
        )
        isAddColumnSheetPresented = false
    }

    func removeColumn(id: UUID) {
        columns.removeAll(where: { $0.id == id })
    }

    func duplicateColumn(id: UUID) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else {
            return
        }

        let source = columns[index]
        let duplicate = DeckColumn(
            type: source.type,
            parameter: source.parameter,
            customTitle: source.customTitle,
            width: source.width,
            filter: source.filter
        )

        columns.insert(duplicate, at: index + 1)
    }

    func shiftColumn(id: UUID, by delta: Int) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else {
            return
        }

        let destination = min(max(index + delta, 0), columns.count - 1)
        guard destination != index else {
            return
        }

        let moved = columns.remove(at: index)
        columns.insert(moved, at: destination)
    }

    func adjustWidth(for id: UUID, delta: Double) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else {
            return
        }

        columns[index].width = max(
            DeckColumn.minWidth,
            min(DeckColumn.maxWidth, columns[index].width + delta)
        )
    }

    func setWidth(for id: UUID, width: Double) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else {
            return
        }

        columns[index].width = max(
            DeckColumn.minWidth,
            min(DeckColumn.maxWidth, width)
        )
    }

    func updateFilter(for id: UUID, filter: ColumnFilter) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else {
            return
        }
        columns[index].filter = filter
    }

    func refreshAllColumns() {
        refreshSignal = UUID()
    }

    func focusOrAddNotificationsColumnFromSystemEvent(targetURL: URL? = nil) {
        focusOrAddColumn(type: .notifications, defaultWidth: 360)
        guard let column = columns.first(where: { $0.type == .notifications }) else { return }
        notificationNavigationURLs[column.id] = targetURL
    }

    func clearColumns() {
        columns.removeAll()
    }

    func resetToStarterColumns() {
        layoutResetSignal = UUID()
        columns = DeckColumn.starterColumns
        refreshAllColumns()
    }

    private func updateAccount(_ id: UUID, mutate: (inout DeckAccount) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&accounts[index])
    }

    private func refreshProfileMetadataIfNeeded(for accountID: UUID, force: Bool) {
        guard let account = account(with: accountID), !account.requiresLogin else {
            return
        }

        if !force {
            let hasHandle = (account.handle?.isEmpty == false)
            let hasAvatar = (account.profileImageURL?.isEmpty == false)
            if hasHandle && hasAvatar {
                return
            }
        }

        guard !profileMetaRefreshInFlight.contains(accountID) else {
            return
        }
        profileMetaRefreshInFlight.insert(accountID)

        WebSessionPool.shared.fetchProfileMeta(accountID: accountID) { [weak self] meta in
            guard let self else { return }
            self.profileMetaRefreshInFlight.remove(accountID)

            guard let current = self.account(with: accountID), !current.requiresLogin else {
                return
            }

            let resolvedHandle = meta?.handle ?? current.handle
            if let resolvedHandle, !resolvedHandle.isEmpty {
                self.setHandle(accountID: accountID, handle: resolvedHandle)
            }

            if let avatar = meta?.profileImageURL {
                self.setProfileImage(accountID: accountID, imageURL: avatar)
            } else if let resolvedHandle, !resolvedHandle.isEmpty {
                let fallback = URL(string: "https://x.com/\(resolvedHandle)/profile_image?size=normal")
                self.setProfileImage(accountID: accountID, imageURL: fallback)
            } else {
                let retry = (self.profileMetaRetryCount[accountID] ?? 0) + 1
                self.profileMetaRetryCount[accountID] = retry
                if retry <= 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                        self?.refreshProfileMetadataIfNeeded(for: accountID, force: true)
                    }
                }
                return
            }

            self.profileMetaRetryCount[accountID] = 0
        }
    }

    private func ensureHomeColumnAndScroll() {
        if let existingIndex = columns.firstIndex(where: { $0.type == .home }) {
            if existingIndex != 0 {
                let home = columns.remove(at: existingIndex)
                columns.insert(home, at: 0)
            }

            if let homeID = columns.first?.id {
                requestScroll(to: homeID)
            }
            return
        }

        let home = DeckColumn(type: .home, width: 430)
        columns.insert(home, at: 0)
        requestScroll(to: home.id)
    }

    private func focusOrAddListsColumn() {
        if let existingIndex = columns.firstIndex(where: { $0.type == .list }) {
            let normalizedParameter = columns[existingIndex].parameter?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalizedParameter == nil || normalizedParameter == "i/lists",
               let handle = activeAccount?.handle {
                columns[existingIndex].parameter = "\(handle)/lists"
            }
            requestScroll(to: columns[existingIndex].id)
            return
        }

        let parameter = activeAccount?.handle.map { "\($0)/lists" }
        let added = DeckColumn(type: .list, parameter: parameter, customTitle: "Lists", width: 360)
        columns.append(added)
        requestScroll(to: added.id)
    }

    private func addSearchColumnAndScroll() {
        let search = DeckColumn(type: .search, parameter: nil, customTitle: nil, width: 360)
        columns.append(search)
        requestScroll(to: search.id)
    }

    private func focusOrAddColumn(type: DeckColumnType, defaultWidth: Double) {
        if let existing = columns.first(where: { $0.type == type }) {
            requestScroll(to: existing.id)
            return
        }

        let added = DeckColumn(type: type, width: defaultWidth)
        columns.append(added)
        requestScroll(to: added.id)
    }

    private func requestScroll(to columnID: UUID) {
        scrollTargetColumnID = nil
        DispatchQueue.main.async { [weak self] in
            self?.scrollTargetColumnID = columnID
        }
    }

    private func loadColumnsForActiveAccount() {
        let key = activeAccountID.uuidString
        let target: [DeckColumn]
        if let saved = columnsByAccount[key] {
            target = saved
        } else {
            target = DeckColumn.starterColumns
            columnsByAccount[key] = target
            persistColumnsByAccount()
        }

        isHydratingColumns = true
        columns = target
        isHydratingColumns = false
    }

    private func pruneColumnLayoutsForExistingAccounts() {
        let validKeys = Set(accounts.map { $0.id.uuidString })
        let pruned = columnsByAccount.filter { validKeys.contains($0.key) }
        guard pruned.count != columnsByAccount.count else {
            return
        }
        columnsByAccount = pruned
        persistColumnsByAccount()
    }

    private static func loadColumns(from defaults: UserDefaults, key: String) -> [DeckColumn]? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode([DeckColumn].self, from: data)
    }

    private static func loadColumnsByAccount(from defaults: UserDefaults, key: String) -> [String: [DeckColumn]]? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode([String: [DeckColumn]].self, from: data)
    }

    private static func loadAccounts(from defaults: UserDefaults, key: String) -> [DeckAccount]? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode([DeckAccount].self, from: data)
    }

    private func persistColumns() {
        columnsByAccount[activeAccountID.uuidString] = columns
        persistColumnsByAccount()
    }

    private func persistColumnsByAccount() {
        guard let data = try? JSONEncoder().encode(columnsByAccount) else {
            return
        }
        defaults.set(data, forKey: columnsByAccountStorageKey)
    }

    private func persistAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else {
            return
        }
        defaults.set(data, forKey: accountsStorageKey)
    }

    private static func extractHandle(from url: URL?) -> String? {
        guard let url, TrustedURLPolicy.isTrustedXPage(url) else {
            return nil
        }

        let segments = url.path
            .split(separator: "/")
            .map(String.init)

        guard let candidate = segments.first?.lowercased(), !candidate.isEmpty else {
            return nil
        }

        if reservedPathSegments.contains(candidate) {
            return nil
        }

        let validChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        let charset = CharacterSet(charactersIn: candidate)
        guard candidate.count <= 15, validChars.isSuperset(of: charset) else {
            return nil
        }

        return candidate
    }

    private static func extractListRoute(from url: URL?) -> (parameter: String, titleHint: String?)? {
        guard let url, TrustedURLPolicy.isTrustedXListURL(url) else {
            return nil
        }

        let segments = url.path
            .split(separator: "/")
            .map(String.init)

        guard !segments.isEmpty else {
            return ("i/lists", "Lists")
        }

        if segments.count >= 2,
           segments[0].lowercased() == "i",
           segments[1].lowercased() == "lists" {
            if segments.count >= 3 {
                return ("i/lists/\(segments[2])", nil)
            }
            return ("i/lists", "Lists")
        }

        if segments.count >= 3,
           segments[1].lowercased() == "lists" {
            let parameter = "\(segments[0])/lists/\(segments[2])"
            let titleHint = segments[2]
                .removingPercentEncoding?
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (parameter, (titleHint?.isEmpty == false) ? titleHint : nil)
        }

        if segments.count == 2,
           segments[1].lowercased() == "lists" {
            return ("\(segments[0])/lists", "Lists")
        }

        return nil
    }

    private static func normalizedListTitle(_ raw: String?) -> String? {
        guard var title = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }

        let suffixes = [" / X", " / Twitter", " / x", " / twitter", " on X"]
        for suffix in suffixes where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if title.isEmpty || title.lowercased() == "x" {
            return nil
        }

        if title.lowercased() == "lists" {
            return "Lists"
        }

        return title
    }

    private static let reservedPathSegments: Set<String> = [
        "home",
        "notifications",
        "messages",
        "explore",
        "search",
        "i",
        "compose",
        "settings",
        "tos",
        "privacy",
        "about",
        "intent",
        "share",
        "login",
        "logout",
        "signup",
        "hashtag"
    ]
}
