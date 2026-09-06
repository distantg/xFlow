import CoreGraphics
import XCTest
@testable import XFlow

final class ColumnResidencyPolicyTests: XCTestCase {
    func testDistantColumnsHibernateOutsideOverscan() {
        let columns = (0..<6).map { _ in DeckColumn(type: .search, parameter: "swift") }
        let frames = Dictionary(uniqueKeysWithValues: columns.enumerated().map { index, column in
            (column.id, CGRect(x: CGFloat(index) * 404, y: 0, width: 390, height: 700))
        })

        let live = ColumnResidencyPolicy.desiredLiveColumnIDs(
            columns: columns,
            frames: frames,
            viewportSize: CGSize(width: 1_100, height: 700),
            columnSpacing: 14
        )

        XCTAssertTrue(live.contains(columns[0].id))
        XCTAssertTrue(live.contains(columns[3].id))
        XCTAssertFalse(live.contains(columns[4].id))
        XCTAssertFalse(live.contains(columns[5].id))
    }

    func testNotificationAndMessageColumnsRemainLiveOffscreen() {
        let home = DeckColumn(type: .home)
        let nearbySearch = DeckColumn(type: .search, parameter: "nearby")
        let distantSearch = DeckColumn(type: .search, parameter: "distant")
        let notifications = DeckColumn(type: .notifications)
        let messages = DeckColumn(type: .messages)
        let columns = [home, nearbySearch, distantSearch, notifications, messages]
        let frames = [
            home.id: CGRect(x: 0, y: 0, width: 390, height: 700),
            nearbySearch.id: CGRect(x: 404, y: 0, width: 390, height: 700),
            distantSearch.id: CGRect(x: 3_596, y: 0, width: 390, height: 700),
            notifications.id: CGRect(x: 4_000, y: 0, width: 390, height: 700),
            messages.id: CGRect(x: 4_404, y: 0, width: 390, height: 700)
        ]

        let live = ColumnResidencyPolicy.desiredLiveColumnIDs(
            columns: columns,
            frames: frames,
            viewportSize: CGSize(width: 1_100, height: 700),
            columnSpacing: 14
        )

        XCTAssertTrue(live.contains(home.id))
        XCTAssertTrue(live.contains(nearbySearch.id))
        XCTAssertFalse(live.contains(distantSearch.id))
        XCTAssertTrue(live.contains(notifications.id))
        XCTAssertTrue(live.contains(messages.id))
    }
}
