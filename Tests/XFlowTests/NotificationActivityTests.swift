import XCTest
@testable import XFlow

final class NotificationActivityTests: XCTestCase {
    func testPreservesNamesCaseAndPostPreview() {
        let activity = NotificationActivity(payload: [
            "title": "  Jane Doe liked your post  ",
            "body": "Hello, Swift!\nA second line."
        ])
        XCTAssertEqual(activity?.title, "Jane Doe liked your post")
        XCTAssertEqual(activity?.body, "Hello, Swift! A second line.")
    }

    func testOnlyRoutesToTrustedPostLinks() {
        XCTAssertEqual(NotificationActivity.validatedTargetURL("https://twitter.com/jane/status/123?s=20")?.absoluteString, "https://x.com/jane/status/123")
        for raw in ["https://evil.test/jane/status/123", "https://x.com@evil.test/jane/status/123", "http://x.com/jane/status/123", "https://x.com/settings", "https://x.com:8443/jane/status/123", "javascript:alert(1)"] {
            XCTAssertNil(NotificationActivity.validatedTargetURL(raw), raw)
        }
    }

    func testRejectsEmptyOrMalformedContent() {
        XCTAssertNil(NotificationActivity(payload: [:]))
        XCTAssertNil(NotificationActivity(payload: ["title": 42]))
        XCTAssertNil(NotificationActivity(payload: ["title": "\n\t"]))
    }

    func testBoundsUntrustedTextWithoutBreakingEmoji() {
        let activity = NotificationActivity(payload: ["title": String(repeating: "👨‍👩‍👧‍👦", count: 150), "body": String(repeating: "x", count: 500)])
        XCTAssertEqual(activity?.title.count, 120)
        XCTAssertEqual(activity?.title.last, "…")
        XCTAssertEqual(activity?.body.count, 400)
    }
}
