import XCTest
@testable import XFlow

final class MosaicSettingsArchiveTests: XCTestCase {
    func testRoundTripPreservesEveryAccountAndPreferenceWithoutSessionData() throws {
        let first = MosaicSettingsArchive.Account(
            id: UUID(), fallbackName: "Personal", handle: "personal",
            columns: [DeckColumn(
                type: .search, parameter: "swift lang", customTitle: "Development", width: 520,
                filter: ColumnFilter(includeKeywords: "swift", excludeKeywords: "spam", hideReplies: true, hideReposts: true)
            )]
        )
        let second = MosaicSettingsArchive.Account(
            id: UUID(), fallbackName: "Work", handle: "work", columns: []
        )
        let archive = makeArchive(accounts: [first, second], activeAccountID: second.id)
        let data = try archive.encoded()

        XCTAssertEqual(try MosaicSettingsArchive.decode(data), archive)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["format"] as? String, "mosaic-settings")
        XCTAssertEqual(object["version"] as? Int, 1)
        let accountObject = try XCTUnwrap((object["accounts"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(accountObject.keys), ["id", "fallbackName", "handle", "columns"])
        XCTAssertNil(accountObject["requiresLogin"])
        XCTAssertNil(accountObject["cookies"])
    }

    func testFutureVersionIsReportedBeforeDecodingItsUnknownPayload() throws {
        let data = Data(#"{"format":"mosaic-settings","version":2,"futureSettings":{}}"#.utf8)
        XCTAssertThrowsError(try MosaicSettingsArchive.decode(data)) { error in
            XCTAssertEqual(error as? MosaicSettingsArchive.ArchiveError, .unsupportedVersion(2))
            XCTAssertTrue(error.localizedDescription.contains("Update Mosaic"))
        }
    }

    func testMalformedMissingHeaderAndUnrelatedJSONAreRejected() {
        for content in ["not json", "{}", #"{"format":"another-app","version":1}"#, #"{"format":"mosaic-settings"}"#] {
            XCTAssertThrowsError(try MosaicSettingsArchive.decode(Data(content.utf8))) { error in
                XCTAssertEqual(error as? MosaicSettingsArchive.ArchiveError, .invalidFile)
            }
        }
    }

    func testOversizedFileIsRejectedBeforeParsing() {
        let data = Data(repeating: 32, count: MosaicSettingsArchive.maximumFileSize + 1)
        XCTAssertThrowsError(try MosaicSettingsArchive.decode(data)) { error in
            XCTAssertEqual(error as? MosaicSettingsArchive.ArchiveError, .fileTooLarge)
        }
    }

    func testDuplicateAccountIDsAndMissingActiveAccountAreRejected() {
        let account = makeAccount(handle: "name")
        for archive in [
            makeArchive(accounts: [account, account]),
            makeArchive(accounts: [account], activeAccountID: UUID()),
            makeArchive(accounts: [])
        ] {
            XCTAssertThrowsError(try archive.validate())
        }
    }

    func testMultipleSlotsForTheSameHandleArePreserved() throws {
        let archive = makeArchive(accounts: [makeAccount(handle: "name"), makeAccount(handle: "NAME")])
        XCTAssertEqual(try MosaicSettingsArchive.decode(archive.encoded()), archive)
    }

    func testInvalidHandleAndAccountLimitsAreRejected() {
        for handle in ["@name", " name", "name ", "bad/name", "", "sixteenchar_name1"] {
            XCTAssertThrowsError(try makeArchive(accounts: [makeAccount(handle: handle)]).validate())
        }
        XCTAssertThrowsError(try makeArchive(accounts: (0..<101).map { _ in makeAccount() }).validate())
        let unnamed = MosaicSettingsArchive.Account(id: UUID(), fallbackName: " \n", handle: nil, columns: [])
        XCTAssertThrowsError(try makeArchive(accounts: [unnamed]).validate())
    }

    func testInvalidColumnWidthsAndDuplicateColumnIDsAreRejected() {
        for width in [DeckColumn.minWidth - 1, DeckColumn.maxWidth + 1, .infinity, .nan] {
            var column = DeckColumn(type: .home)
            column.width = width
            XCTAssertThrowsError(try makeArchive(accounts: [makeAccount(columns: [column])]).validate())
        }
        let column = DeckColumn(type: .home)
        XCTAssertThrowsError(try makeArchive(accounts: [makeAccount(columns: [column, column])]).validate())
        XCTAssertThrowsError(try makeArchive(accounts: [makeAccount(columns: (0..<201).map { _ in DeckColumn(type: .home) })]).validate())
    }

    func testDecodedOutOfRangeWidthDoesNotBypassValidation() throws {
        let data = try makeArchive(accounts: [makeAccount(columns: [DeckColumn(type: .home)])]).encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var accounts = try XCTUnwrap(object["accounts"] as? [[String: Any]])
        var columns = try XCTUnwrap(accounts[0]["columns"] as? [[String: Any]])
        columns[0]["width"] = 1
        accounts[0]["columns"] = columns
        object["accounts"] = accounts
        XCTAssertThrowsError(try MosaicSettingsArchive.decode(JSONSerialization.data(withJSONObject: object))) { error in
            XCTAssertEqual(error as? MosaicSettingsArchive.ArchiveError, .invalidColumns)
        }
    }

    func testSameColumnIDsAcrossDifferentAccountsAreAllowed() throws {
        let columns = DeckColumn.starterColumns
        try makeArchive(accounts: [makeAccount(columns: columns), makeAccount(columns: columns)]).validate()
    }

    private func makeAccount(handle: String? = nil, columns: [DeckColumn] = []) -> MosaicSettingsArchive.Account {
        MosaicSettingsArchive.Account(id: UUID(), fallbackName: "Account", handle: handle, columns: columns)
    }

    private func makeArchive(
        accounts: [MosaicSettingsArchive.Account], activeAccountID: UUID? = nil
    ) -> MosaicSettingsArchive {
        MosaicSettingsArchive(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            activeAccountID: activeAccountID ?? accounts.first?.id ?? UUID(),
            preferences: .init(
                appearanceMode: .light, columnAppearanceMode: .originalX, hideAds: true,
                automaticallyChecksForUpdates: false, automaticallyDownloadsUpdates: true
            ),
            accounts: accounts
        )
    }
}
