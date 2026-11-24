import XCTest
@testable import XFlow

final class SettingsTransferTests: XCTestCase {
    @MainActor
    func testAllAccountLayoutsAndPreferencesSurviveFileTransferAndRestart() throws {
        let personal = DeckAccount(fallbackName: "Personal", handle: "personal", requiresLogin: false)
        let work = DeckAccount(fallbackName: "Work", handle: "work", requiresLogin: false)
        let empty = DeckAccount(fallbackName: "Empty", handle: "empty", requiresLogin: false)
        let personalColumns = [DeckColumn(type: .bookmarks, width: 610)]
        let workColumns = [
            DeckColumn(type: .list, parameter: "123456", customTitle: "My list", width: 480),
            DeckColumn(type: .search, parameter: "swift lang", customTitle: "Development", width: 550,
                       filter: ColumnFilter(includeKeywords: "swift", excludeKeywords: "spam", hideReplies: true, hideReposts: true))
        ]
        let sourceDefaults = try makeDefaults()
        let source = try makeStore(
            defaults: sourceDefaults, accounts: [personal, work, empty], active: work.id,
            layouts: [personal.id: personalColumns, work.id: workColumns, empty.id: []]
        )
        source.appearanceMode = .light
        source.columnAppearanceMode = .originalX
        sourceDefaults.set(true, forKey: TimelineAdHiding.storageKey)
        // The active deck may have changes newer than a previously exported file.
        source.columns[1].width = 600

        let exported = source.settingsArchive(automaticallyChecksForUpdates: false, automaticallyDownloadsUpdates: true)
        let decoded = try MosaicSettingsArchive.decode(exported.encoded())
        XCTAssertEqual(decoded.accounts.map(\.id), [personal.id, work.id, empty.id])
        XCTAssertEqual(decoded.preferences.automaticallyChecksForUpdates, false)
        XCTAssertEqual(decoded.preferences.automaticallyDownloadsUpdates, true)
        XCTAssertEqual(decoded.accounts[1].columns[1].width, 600)
        XCTAssertTrue(decoded.accounts[2].columns.isEmpty)

        let destinationDefaults = try makeDefaults()
        let destination = DeckStore(defaults: destinationDefaults)
        try destination.importSettings(decoded)
        let restarted = DeckStore(defaults: destinationDefaults)
        let restored = restarted.settingsArchive(automaticallyChecksForUpdates: false, automaticallyDownloadsUpdates: true)

        XCTAssertEqual(restarted.accounts.map(\.id), [personal.id, work.id, empty.id])
        XCTAssertEqual(restarted.activeAccountID, work.id)
        XCTAssertTrue(restarted.accounts.allSatisfy(\.requiresLogin))
        XCTAssertEqual(restored.preferences, decoded.preferences)
        for (actual, expected) in zip(restored.accounts, decoded.accounts) {
            XCTAssertEqual(actual.fallbackName, expected.fallbackName)
            XCTAssertEqual(actual.handle, expected.handle)
            assertColumnSettingsEqual(actual.columns, expected.columns)
        }
        XCTAssertTrue(Set(restarted.columns.map(\.id)).isDisjoint(with: Set(workColumns.map(\.id))))
    }

    @MainActor
    func testHandleMatchPreservesLocalSessionIdentityAndAvatar() throws {
        let local = DeckAccount(
            fallbackName: "Local label", handle: "personal",
            profileImageURL: "https://pbs.twimg.com/profile_images/123/avatar.jpg", requiresLogin: false
        )
        let defaults = try makeDefaults()
        let store = try makeStore(defaults: defaults, accounts: [local], active: local.id,
                                  layouts: [local.id: [DeckColumn(type: .home)]])
        let imported = savedAccount(handle: "PERSONAL", name: "Imported label", columns: [DeckColumn(type: .search, parameter: "news")])
        try store.importSettings(archive([imported]))

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.activeAccountID, local.id)
        XCTAssertEqual(store.activeAccount?.handle, "personal")
        XCTAssertEqual(store.activeAccount?.fallbackName, "Imported label")
        XCTAssertEqual(store.activeAccount?.profileImageURL, local.profileImageURL)
        XCTAssertEqual(store.activeAccount?.requiresLogin, false)
        assertColumnSettingsEqual(store.columns, imported.columns)
        let restarted = DeckStore(defaults: defaults)
        XCTAssertEqual(restarted.activeAccount, store.activeAccount)
    }

    @MainActor
    func testDuplicateHandlesMatchOneToOneAndReserveExactIDsBeforeHandleMatches() throws {
        let first = DeckAccount(fallbackName: "First", handle: "same", requiresLogin: false)
        let second = DeckAccount(fallbackName: "Second", handle: "same", requiresLogin: true)
        let store = try makeStore(defaults: makeDefaults(), accounts: [first, second], active: first.id,
                                  layouts: [first.id: [], second.id: []])
        // The non-exact account comes first in the file. It must not consume
        // the local slot needed by the later exact-ID match.
        let remote = savedAccount(handle: "same", name: "Remote", columns: [DeckColumn(type: .bookmarks)])
        let exact = savedAccount(id: first.id, handle: "same", name: "Exact", columns: [DeckColumn(type: .notifications)])
        let third = savedAccount(handle: "same", name: "Third", columns: [])
        let imported = archive([remote, exact, third], active: remote.id)
        XCTAssertEqual(store.matchingSettingsAccountCount(in: imported), 2)
        try store.importSettings(imported)

        XCTAssertEqual(store.accounts.map(\.id), [second.id, first.id, third.id])
        XCTAssertEqual(store.accounts.map(\.requiresLogin), [true, false, true])
        XCTAssertEqual(store.activeAccountID, second.id)
        let exported = store.settingsArchive(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false)
        assertColumnSettingsEqual(exported.accounts[0].columns, remote.columns)
        assertColumnSettingsEqual(exported.accounts[1].columns, exact.columns)
        XCTAssertTrue(exported.accounts[2].columns.isEmpty)

        try store.importSettings(imported)
        XCTAssertEqual(store.accounts.map(\.id), [second.id, first.id, third.id])
    }

    @MainActor
    func testUnmentionedAccountsKeepTheirOrderSessionsAndLayouts() throws {
        let first = DeckAccount(fallbackName: "Keep first", handle: "first", requiresLogin: false)
        let second = DeckAccount(fallbackName: "Keep second", handle: "second", requiresLogin: true)
        let firstColumns = [DeckColumn(type: .profile, parameter: "swiftlang", width: 450)]
        let secondColumns = [DeckColumn(type: .messages, width: 590)]
        let defaults = try makeDefaults()
        let store = try makeStore(defaults: defaults, accounts: [first, second], active: first.id,
                                  layouts: [first.id: firstColumns, second.id: secondColumns])
        store.columns[0].customTitle = "Locally edited"
        let activeColumnsBeforeImport = store.columns
        let imported = savedAccount(handle: "new", columns: [])
        try store.importSettings(archive([imported]))

        XCTAssertEqual(store.accounts.map(\.id), [imported.id, first.id, second.id])
        XCTAssertEqual(store.account(with: first.id), first)
        XCTAssertEqual(store.account(with: second.id), second)
        let restored = DeckStore(defaults: defaults).settingsArchive(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false)
        XCTAssertEqual(restored.accounts[1].columns, activeColumnsBeforeImport)
        XCTAssertEqual(restored.accounts[2].columns, secondColumns)
    }

    @MainActor
    func testPristinePlaceholderIsRemovedButCustomizedSignedOutAccountIsKept() throws {
        let imported = savedAccount(handle: "new", columns: [])
        let freshDefaults = try makeDefaults()
        let fresh = DeckStore(defaults: freshDefaults)
        let placeholderID = fresh.activeAccountID
        try fresh.importSettings(archive([imported]))
        XCTAssertEqual(fresh.accounts.map(\.id), [imported.id])
        let persistedLayouts = try JSONDecoder().decode(
            [String: [DeckColumn]].self,
            from: XCTUnwrap(freshDefaults.data(forKey: "xflow.columnsByAccount.v1"))
        )
        XCTAssertNil(persistedLayouts[placeholderID.uuidString])

        let customized = DeckStore(defaults: try makeDefaults())
        let customizedID = customized.activeAccountID
        customized.columns = [DeckColumn(type: .bookmarks, customTitle: "Keep this")]
        let customizedColumns = customized.columns
        try customized.importSettings(archive([imported]))
        XCTAssertEqual(customized.accounts.map(\.id), [imported.id, customizedID])
        let exported = customized.settingsArchive(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false)
        XCTAssertEqual(exported.accounts[1].columns, customizedColumns)
    }

    @MainActor
    func testRepeatedImportDoesNotDuplicateNamedOrUnnamedNewAccounts() throws {
        let store = DeckStore(defaults: try makeDefaults())
        let named = savedAccount(handle: "named", columns: [DeckColumn(type: .home)])
        let unnamed = savedAccount(name: "Not signed in yet", columns: [])
        let imported = archive([named, unnamed], active: unnamed.id)
        try store.importSettings(imported)
        let accountIDs = store.accounts.map(\.id)
        try store.importSettings(imported)

        XCTAssertEqual(store.accounts.map(\.id), accountIDs)
        XCTAssertEqual(store.activeAccountID, unnamed.id)
        XCTAssertTrue(store.accounts.allSatisfy(\.requiresLogin))
        XCTAssertTrue(store.columns.isEmpty)
    }

    @MainActor
    func testMatchingUUIDWithDifferentHandleNeverReusesLocalSession() throws {
        let local = DeckAccount(fallbackName: "Local", handle: "local", requiresLogin: false)
        let localColumns = [DeckColumn(type: .messages)]
        let store = try makeStore(defaults: makeDefaults(), accounts: [local], active: local.id,
                                  layouts: [local.id: localColumns])
        let imported = savedAccount(id: local.id, handle: "remote", columns: [DeckColumn(type: .bookmarks)])
        try store.importSettings(archive([imported]))

        XCTAssertEqual(store.accounts.count, 2)
        XCTAssertNotEqual(store.activeAccountID, local.id)
        XCTAssertEqual(store.activeAccount?.handle, "remote")
        XCTAssertEqual(store.activeAccount?.requiresLogin, true)
        XCTAssertEqual(store.account(with: local.id), local)
        let exported = store.settingsArchive(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false)
        XCTAssertEqual(exported.accounts[1].columns, localColumns)
        let importedLocalID = store.activeAccountID
        try store.importSettings(archive([imported]))
        XCTAssertEqual(store.accounts.count, 2)
        XCTAssertEqual(store.activeAccountID, importedLocalID)
    }

    @MainActor
    func testInvalidArchiveLeavesMemoryAndPersistedSettingsUnchanged() throws {
        let defaults = try makeDefaults()
        let store = DeckStore(defaults: defaults)
        store.columns = [DeckColumn(type: .messages, width: 500)]
        store.isComposerSheetPresented = true
        store.isAddColumnSheetPresented = true
        store.presentedLoginAccountID = store.activeAccountID
        let accounts = store.accounts
        let columns = store.columns
        let activeID = store.activeAccountID
        let refresh = store.refreshSignal
        let savedAccounts = defaults.data(forKey: "xflow.accounts.v1")
        let savedLayouts = defaults.data(forKey: "xflow.columnsByAccount.v1")
        let originalAppearance = store.appearanceMode
        let originalColumnsAppearance = store.columnAppearanceMode
        var invalidColumn = DeckColumn(type: .home)
        invalidColumn.width = 1
        let invalid = archive([savedAccount(handle: "new", columns: [invalidColumn])])

        XCTAssertThrowsError(try store.importSettings(invalid))

        XCTAssertEqual(store.accounts, accounts)
        XCTAssertEqual(store.columns, columns)
        XCTAssertEqual(store.activeAccountID, activeID)
        XCTAssertEqual(store.refreshSignal, refresh)
        XCTAssertEqual(store.appearanceMode, originalAppearance)
        XCTAssertEqual(store.columnAppearanceMode, originalColumnsAppearance)
        XCTAssertFalse(defaults.bool(forKey: TimelineAdHiding.storageKey))
        XCTAssertTrue(store.isComposerSheetPresented)
        XCTAssertTrue(store.isAddColumnSheetPresented)
        XCTAssertEqual(store.presentedLoginAccountID, activeID)
        XCTAssertEqual(defaults.data(forKey: "xflow.accounts.v1"), savedAccounts)
        XCTAssertEqual(defaults.data(forKey: "xflow.columnsByAccount.v1"), savedLayouts)
    }

    @MainActor
    func testMergedAccountLimitRejectsImportWithoutChangingWorkspace() throws {
        let localAccounts = (0..<100).map {
            DeckAccount(fallbackName: "Local \($0)", handle: "local\($0)", requiresLogin: false)
        }
        let defaults = try makeDefaults()
        let store = try makeStore(
            defaults: defaults, accounts: localAccounts, active: localAccounts[0].id,
            layouts: Dictionary(uniqueKeysWithValues: localAccounts.map { ($0.id, []) })
        )
        let imported = archive([savedAccount(handle: "new", columns: [])])
        XCTAssertNoThrow(try imported.encoded())
        XCTAssertNoThrow(try store.settingsArchive(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false).encoded())

        assertImportRejectedWithoutChanges(imported, store: store, defaults: defaults)
        XCTAssertEqual(DeckStore(defaults: defaults).accounts, localAccounts)
    }

    @MainActor
    func testMergedFileSizeLimitRejectsIndividuallyValidWorkspacesWithoutChanges() throws {
        let local = DeckAccount(fallbackName: "Local", handle: "local", requiresLogin: false)
        let largeQuery = String(repeating: "a", count: 14_000)
        let localColumns = (0..<200).map { _ in DeckColumn(type: .search, parameter: largeQuery) }
        let importedColumns = (0..<200).map { _ in DeckColumn(type: .search, parameter: largeQuery) }
        let defaults = try makeDefaults()
        let store = try makeStore(defaults: defaults, accounts: [local], active: local.id, layouts: [local.id: localColumns])
        let imported = archive([savedAccount(handle: "remote", columns: importedColumns)])
        let localData = try store.settingsArchive(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false).encoded()
        let importedData = try imported.encoded()
        XCTAssertLessThan(localData.count, MosaicSettingsArchive.maximumFileSize)
        XCTAssertLessThan(importedData.count, MosaicSettingsArchive.maximumFileSize)
        XCTAssertGreaterThan(localData.count + importedData.count, MosaicSettingsArchive.maximumFileSize)

        assertImportRejectedWithoutChanges(imported, store: store, defaults: defaults)
        let restarted = DeckStore(defaults: defaults)
        XCTAssertEqual(restarted.accounts, [local])
        XCTAssertEqual(restarted.columns, localColumns)
    }

    @MainActor
    func testUnnamedSourceWithConflictingUUIDReusesImportedSlotAfterRestart() throws {
        let local = DeckAccount(fallbackName: "Local", handle: "local", requiresLogin: false)
        let localColumns = [DeckColumn(type: .messages)]
        let defaults = try makeDefaults()
        let store = try makeStore(defaults: defaults, accounts: [local], active: local.id, layouts: [local.id: localColumns])
        let imported = archive([savedAccount(id: local.id, name: "Unsigned source", columns: [DeckColumn(type: .bookmarks)])])
        try store.importSettings(imported)
        let importedLocalID = store.activeAccountID
        XCTAssertNotEqual(importedLocalID, local.id)
        XCTAssertEqual(store.accounts.count, 2)

        let restarted = DeckStore(defaults: defaults)
        XCTAssertEqual(restarted.matchingSettingsAccountCount(in: imported), 1)
        try restarted.importSettings(imported)
        XCTAssertEqual(restarted.accounts.map(\.id), [importedLocalID, local.id])
        XCTAssertEqual(restarted.activeAccountID, importedLocalID)
        XCTAssertEqual(restarted.account(with: local.id), local)
        XCTAssertEqual(restarted.activeAccount?.requiresLogin, true)
        let exported = restarted.settingsArchive(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false)
        XCTAssertEqual(exported.accounts[1].columns, localColumns)
    }

    @MainActor
    func testUnnamedImportedAccountKeepsItsSignedInIdentityOnRepeatImportAfterRestart() throws {
        let defaults = try makeDefaults()
        let store = DeckStore(defaults: defaults)
        let saved = savedAccount(name: "Unsigned source", columns: [DeckColumn(type: .bookmarks)])
        let imported = archive([saved])
        try store.importSettings(imported)
        let importedID = store.activeAccountID
        // Model the identity discovered when the imported slot signs in locally.
        store.accounts[0].handle = "signedin"
        store.accounts[0].requiresLogin = false
        store.accounts[0].profileImageURL = "https://pbs.twimg.com/profile_images/123/avatar.jpg"
        let signedInAccount = store.accounts[0]

        let restarted = DeckStore(defaults: defaults)
        XCTAssertEqual(restarted.matchingSettingsAccountCount(in: imported), 1)
        try restarted.importSettings(imported)
        XCTAssertEqual(restarted.accounts, [signedInAccount])
        XCTAssertEqual(restarted.activeAccountID, importedID)
        XCTAssertEqual(restarted.activeAccount?.requiresLogin, false)
        assertColumnSettingsEqual(restarted.columns, saved.columns)
        let exported = try restarted.settingsArchive(automaticallyChecksForUpdates: true, automaticallyDownloadsUpdates: false).encoded()
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("settingsImportAliases"))
    }

    @MainActor
    func testRemovingAnImportedAccountPrunesItsPersistedAlias() throws {
        let defaults = try makeDefaults()
        let store = DeckStore(defaults: defaults)
        let removed = savedAccount(name: "Removed", columns: [])
        let kept = savedAccount(handle: "kept", columns: [])
        try store.importSettings(archive([removed, kept], active: kept.id))
        let aliasKey = "xflow.settingsImportAliases.v1"
        let aliasesBefore = try XCTUnwrap(defaults.dictionary(forKey: aliasKey) as? [String: String])
        XCTAssertTrue(aliasesBefore.values.contains(removed.id.uuidString))

        // Exercise account persistence without opening or purging WebKit stores.
        store.accounts.removeAll { $0.id == removed.id }

        let aliasesAfter = defaults.dictionary(forKey: aliasKey) as? [String: String] ?? [:]
        XCTAssertFalse(aliasesAfter.values.contains(removed.id.uuidString))
        XCTAssertTrue(aliasesAfter.values.contains(kept.id.uuidString))
        _ = DeckStore(defaults: defaults)
        XCTAssertEqual(defaults.dictionary(forKey: aliasKey) as? [String: String], aliasesAfter)
    }

    @MainActor
    private func assertImportRejectedWithoutChanges(
        _ archive: MosaicSettingsArchive, store: DeckStore, defaults: UserDefaults,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        store.isComposerSheetPresented = true
        store.isAddColumnSheetPresented = true
        store.presentedLoginAccountID = store.activeAccountID
        let accounts = store.accounts
        let columns = store.columns
        let activeID = store.activeAccountID
        let refresh = store.refreshSignal
        let appearance = store.appearanceMode
        let columnAppearance = store.columnAppearanceMode
        let persisted = defaults.dictionaryRepresentation().filter {
            $0.key.hasPrefix("xflow.") || $0.key == TimelineAdHiding.storageKey
        }

        XCTAssertThrowsError(try store.importSettings(archive), file: file, line: line) { error in
            XCTAssertTrue(error is LocalizedError, file: file, line: line)
            XCTAssertFalse(error.localizedDescription.isEmpty, file: file, line: line)
        }

        XCTAssertEqual(store.accounts, accounts, file: file, line: line)
        XCTAssertEqual(store.columns, columns, file: file, line: line)
        XCTAssertEqual(store.activeAccountID, activeID, file: file, line: line)
        XCTAssertEqual(store.refreshSignal, refresh, file: file, line: line)
        XCTAssertEqual(store.appearanceMode, appearance, file: file, line: line)
        XCTAssertEqual(store.columnAppearanceMode, columnAppearance, file: file, line: line)
        XCTAssertTrue(store.isComposerSheetPresented, file: file, line: line)
        XCTAssertTrue(store.isAddColumnSheetPresented, file: file, line: line)
        XCTAssertEqual(store.presentedLoginAccountID, activeID, file: file, line: line)
        let after = defaults.dictionaryRepresentation().filter {
            $0.key.hasPrefix("xflow.") || $0.key == TimelineAdHiding.storageKey
        }
        XCTAssertEqual(NSDictionary(dictionary: after), NSDictionary(dictionary: persisted), file: file, line: line)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "SettingsTransferTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    @MainActor
    private func makeStore(
        defaults: UserDefaults, accounts: [DeckAccount], active: UUID, layouts: [UUID: [DeckColumn]]
    ) throws -> DeckStore {
        defaults.set(try JSONEncoder().encode(accounts), forKey: "xflow.accounts.v1")
        defaults.set(active.uuidString, forKey: "xflow.activeAccountID.v1")
        defaults.set(try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: layouts.map { ($0.key.uuidString, $0.value) })),
                     forKey: "xflow.columnsByAccount.v1")
        return DeckStore(defaults: defaults)
    }

    private func savedAccount(
        id: UUID = UUID(), handle: String? = nil, name: String = "Account", columns: [DeckColumn]
    ) -> MosaicSettingsArchive.Account {
        .init(id: id, fallbackName: name, handle: handle, columns: columns)
    }

    private func archive(_ accounts: [MosaicSettingsArchive.Account], active: UUID? = nil) -> MosaicSettingsArchive {
        MosaicSettingsArchive(
            activeAccountID: active ?? accounts[0].id,
            preferences: .init(appearanceMode: .light, columnAppearanceMode: .originalX, hideAds: true,
                               automaticallyChecksForUpdates: false, automaticallyDownloadsUpdates: true),
            accounts: accounts
        )
    }

    private func assertColumnSettingsEqual(
        _ actual: [DeckColumn], _ expected: [DeckColumn], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actual, expected) in zip(actual, expected) {
            XCTAssertEqual(actual.type, expected.type, file: file, line: line)
            XCTAssertEqual(actual.parameter, expected.parameter, file: file, line: line)
            XCTAssertEqual(actual.customTitle, expected.customTitle, file: file, line: line)
            XCTAssertEqual(actual.width, expected.width, file: file, line: line)
            XCTAssertEqual(actual.filter, expected.filter, file: file, line: line)
        }
    }
}
