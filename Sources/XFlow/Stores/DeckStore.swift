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

    @Published var presentedLoginAccountID: UUID?
    @Published var quickPanelDestination: QuickPanelDestination?
    @Published var scrollTargetColumnID: UUID?

    @Published var refreshSignal = UUID()
    @Published var isAddColumnSheetPresented = false
    @Published var isComposerSheetPresented = false

    private let defaults = UserDefaults.standard
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
    private var profileMetaRefreshInFlight: Set<UUID> = []
    private var profileMetaRetryCount: [UUID: Int] = [:]
    private var columnsByAccount: [String: [DeckColumn]] = [:]
    private var isHydratingColumns = false

    init() {
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
            appearanceMode = .auto
        }

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
        defaults.set(activeAccountID.uuidString, forKey: activeAccountStorageKey)
        defaults.set(appearanceMode.rawValue, forKey: appearanceModeStorageKey)

        refreshAuthenticationState(for: activeAccountID, shouldPromptIfNeeded: true)
        for account in accounts where !account.requiresLogin {
            refreshProfileMetadataIfNeeded(for: account.id, force: false)
        }
    }

    var activeAccount: DeckAccount? {
        accounts.first(where: { $0.id == activeAccountID })
    }

    func account(with id: UUID) -> DeckAccount? {
        accounts.first(where: { $0.id == id })
    }

    func presentAddColumnSheet() {
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
        case .compose:
            presentComposer()
        case .articles, .grok, .premium, .profile, .more:
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
        guard accounts.count > 1 else {
            return
        }
        guard let removeIndex = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }

        let removingActive = activeAccountID == accountID
        accounts.remove(at: removeIndex)
        profileMetaRefreshInFlight.remove(accountID)
        profileMetaRetryCount.removeValue(forKey: accountID)
        columnsByAccount.removeValue(forKey: accountID.uuidString)
        persistColumnsByAccount()
        WebSessionPool.shared.purgeAccount(accountID)

        if presentedLoginAccountID == accountID {
            presentedLoginAccountID = nil
        }

        if removingActive {
            let fallbackIndex = min(removeIndex, max(0, accounts.count - 1))
            let fallbackID = accounts[fallbackIndex].id
            activeAccountID = fallbackID
            loadColumnsForActiveAccount()
            refreshAllColumns()
            refreshAuthenticationState(for: fallbackID, shouldPromptIfNeeded: true)
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
        refreshProfileMetadataIfNeeded(for: accountID, force: false)
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
                self.refreshProfileMetadataIfNeeded(for: accountID, force: false)
            } else if shouldPromptIfNeeded {
                self.presentedLoginAccountID = accountID
            }

            completion?(authenticated)
        }
    }

    func captureHandle(for accountID: UUID, from url: URL?) {
        guard let handle = Self.extractHandle(from: url) else {
            return
        }
        setHandle(accountID: accountID, handle: handle)
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

        guard !normalized.isEmpty else {
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

        let raw = imageURL.absoluteString
        guard raw.hasPrefix("http") else {
            return
        }

        updateAccount(accountID) { account in
            account.profileImageURL = raw
        }
        profileMetaRetryCount[accountID] = 0
    }

    func addColumn(
        type: DeckColumnType,
        parameter: String?,
        customTitle: String?,
        width: Double,
        filter: ColumnFilter
    ) {
        columns.append(
            DeckColumn(
                type: type,
                parameter: parameter,
                customTitle: customTitle,
                width: width,
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

    func focusOrAddNotificationsColumnFromSystemEvent() {
        focusOrAddColumn(type: .notifications, defaultWidth: 360)
    }

    func clearColumns() {
        columns.removeAll()
    }

    func resetToStarterColumns() {
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
        if let existing = columns.first(where: { $0.type == .list }) {
            requestScroll(to: existing.id)
            return
        }

        let added = DeckColumn(type: .list, parameter: nil, customTitle: "Lists", width: 360)
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
        guard let url else {
            return nil
        }

        guard let host = url.host?.lowercased(), host == "x.com" || host == "www.x.com" else {
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
        guard let url,
              let host = url.host?.lowercased(),
              host == "x.com" || host == "www.x.com" else {
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
