import XCTest
@testable import XFlow

final class AccountRemovalTests: XCTestCase {
    @MainActor
    func testRemovingLastAccountCreatesPersistedSignedOutSlot() throws {
        let suite = "AccountRemovalTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeckStore(defaults: defaults)
        let oldID = store.activeAccountID
        store.accounts[0].requiresLogin = false
        store.presentedLoginAccountID = oldID
        store.isComposerSheetPresented = true
        store.columns = [DeckColumn(type: .bookmarks, width: 480)]
        let oldColumnIDs = Set(store.columns.map(\.id))

        store.removeAccount(oldID)

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertNotEqual(store.activeAccountID, oldID)
        XCTAssertEqual(store.activeAccount?.requiresLogin, true)
        XCTAssertNil(store.activeAccount?.handle)
        XCTAssertNil(store.presentedLoginAccountID)
        XCTAssertFalse(store.isComposerSheetPresented)
        XCTAssertTrue(oldColumnIDs.isDisjoint(with: Set(store.columns.map(\.id))))
        let layouts = try XCTUnwrap(defaults.data(forKey: "xflow.columnsByAccount.v1"))
        let saved = try JSONDecoder().decode([String: [DeckColumn]].self, from: layouts)
        XCTAssertNil(saved[oldID.uuidString])
        let restored = DeckStore(defaults: defaults)
        XCTAssertEqual(restored.activeAccountID, store.activeAccountID)
        XCTAssertEqual(restored.accounts.count, 1)
        XCTAssertEqual(restored.activeAccount?.requiresLogin, true)
    }

    @MainActor
    func testRemovingInactiveAccountPreservesActiveDeckAndUnknownRemovalIsNoOp() throws {
        let suite = "AccountRemovalTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeckStore(defaults: defaults)
        let activeID = store.activeAccountID
        let columnIDs = store.columns.map(\.id)
        let other = DeckAccount(fallbackName: "Test account", requiresLogin: true)
        store.accounts.append(other)
        store.removeAccount(other.id)
        store.removeAccount(UUID())
        XCTAssertEqual(store.accounts.map(\.id), [activeID])
        XCTAssertEqual(store.activeAccountID, activeID)
        XCTAssertEqual(store.columns.map(\.id), columnIDs)
    }
}
