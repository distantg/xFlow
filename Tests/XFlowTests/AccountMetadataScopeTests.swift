import XCTest
@testable import XFlow

final class AccountMetadataScopeTests: XCTestCase {
    func testProfileLikeColumnsCannotUpdateAccountIdentity() {
        XCTAssertFalse(DeckColumnType.profile.allowsAccountMetadataDetection)
        XCTAssertFalse(DeckColumnType.search.allowsAccountMetadataDetection)
        XCTAssertFalse(DeckColumnType.list.allowsAccountMetadataDetection)
    }

    func testAccountOwnedColumnsCanUpdateAccountIdentity() {
        XCTAssertTrue(DeckColumnType.home.allowsAccountMetadataDetection)
        XCTAssertTrue(DeckColumnType.notifications.allowsAccountMetadataDetection)
        XCTAssertTrue(DeckColumnType.messages.allowsAccountMetadataDetection)
        XCTAssertTrue(DeckColumnType.bookmarks.allowsAccountMetadataDetection)
        XCTAssertTrue(DeckColumnType.explore.allowsAccountMetadataDetection)
    }
}
