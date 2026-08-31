import WebKit
import XCTest
@testable import XFlow

final class NavigationPolicyTests: XCTestCase {
    typealias Disposition = WebColumnView.Coordinator.NavigationDisposition

    func testXLinksStayInXFlow() {
        XCTAssertEqual(disposition("https://x.com/home", type: .other), .allowInWebView)
        XCTAssertEqual(
            disposition("https://www.x.com/i/bookmarks", type: .linkActivated),
            .allowInWebView
        )
    }

    func testUserActivatedExternalHTTPSLinkOpensExternally() {
        XCTAssertEqual(
            disposition("https://example.com/article", type: .linkActivated),
            .openExternally
        )
    }

    func testUserActivatedExternalHTTPLinkOpensExternally() {
        XCTAssertEqual(
            disposition("http://example.com/article", type: .linkActivated),
            .openExternally
        )
    }

    func testAutomaticExternalNavigationIsCancelled() {
        XCTAssertEqual(disposition("https://example.com/tracker", type: .other), .cancel)
        XCTAssertEqual(disposition("http://example.com/tracker", type: .other), .cancel)
        XCTAssertEqual(
            disposition("https://accounts.google.com/gsi/button", type: .other),
            .cancel
        )
    }

    func testSafeSubframesStayInsideWebKitWithoutLaunchingBrowser() {
        XCTAssertEqual(
            disposition(
                "https://accounts.google.com/gsi/button",
                isMainFrame: false,
                type: .other
            ),
            .allowInWebView
        )
        XCTAssertEqual(
            disposition("about:blank", isMainFrame: false, type: .other),
            .allowInWebView
        )
    }

    func testUnsafeTopLevelSchemesAreCancelled() {
        XCTAssertEqual(disposition("file:///etc/passwd", type: .linkActivated), .cancel)
        XCTAssertEqual(disposition("javascript:alert(1)", type: .linkActivated), .cancel)
    }

    private func disposition(
        _ rawURL: String,
        isMainFrame: Bool = true,
        type: WKNavigationType
    ) -> Disposition {
        WebColumnView.Coordinator.navigationDisposition(
            for: URL(string: rawURL)!,
            isMainFrame: isMainFrame,
            navigationType: type
        )
    }
}
