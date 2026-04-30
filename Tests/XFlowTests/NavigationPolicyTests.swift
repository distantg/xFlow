import XCTest
@testable import XFlow

final class NavigationPolicyTests: XCTestCase {
    func testXLinksStayInXFlow() {
        XCTAssertFalse(WebColumnView.Coordinator.shouldOpenExternally(URL(string: "https://x.com/home")!))
        XCTAssertFalse(WebColumnView.Coordinator.shouldOpenExternally(URL(string: "https://www.x.com/i/bookmarks")!))
    }

    func testNonXLinksOpenExternally() {
        XCTAssertTrue(WebColumnView.Coordinator.shouldOpenExternally(URL(string: "https://example.com/article")!))
        XCTAssertTrue(WebColumnView.Coordinator.shouldOpenExternally(URL(string: "https://github.com/distantg/xFlow")!))
    }

    func testNonWebSchemesStayWithWebKitPolicy() {
        XCTAssertFalse(WebColumnView.Coordinator.shouldOpenExternally(URL(string: "about:blank")!))
        XCTAssertFalse(WebColumnView.Coordinator.shouldOpenExternally(URL(string: "blob:https://x.com/123")!))
    }

    func testEmbeddedGoogleSignInButtonDoesNotOpenExternally() {
        let url = URL(string: "https://accounts.google.com/gsi/button?theme=outline&client_id=abc.apps.googleusercontent.com")!

        XCTAssertFalse(WebColumnView.Coordinator.shouldOpenExternally(url))
    }
}
