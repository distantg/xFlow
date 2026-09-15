import WebKit
import XCTest
@testable import XFlow

@MainActor
final class TimelineAdHidingTests: XCTestCase {
    func testAdsRestoreWithoutChangingPostsOrFilters() async throws {
        let web = WKWebView()
        web.loadHTMLString("""
        <div data-testid="primaryColumn">
          <div data-testid="cellInnerDiv" id="ad"><div data-testid="placementTracking">Ad</div></div>
          <div data-testid="cellInnerDiv" id="post"><article data-testid="tweet">I was promoted. Ads are everywhere.</article></div>
          <div data-testid="cellInnerDiv" id="filtered"><article style="display:none">Filtered post</article></div>
        </div>
        <div data-testid="cellInnerDiv" id="outside"><div data-testid="placementTracking">Outside timeline</div></div>
        """, baseURL: nil)
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('ad')")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        _ = try await web.evaluateJavaScript(TimelineAdHiding.script(enabled: true))
        let hidden = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('ad')).display") as? String
        XCTAssertEqual(hidden, "none")
        for id in ["post", "outside"] {
            let display = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('\(id)')).display") as? String
            XCTAssertNotEqual(display, "none")
        }
        _ = try await web.evaluateJavaScript("document.querySelector('[data-testid=placementTracking]').remove()")
        let recycled = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('ad')).display") as? String
        XCTAssertNotEqual(recycled, "none")
        _ = try await web.evaluateJavaScript(TimelineAdHiding.script(enabled: false))
        let filtered = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('#filtered article')).display") as? String
        XCTAssertEqual(filtered, "none")
        let styles = try await web.evaluateJavaScript("document.querySelectorAll('#mosaic-timeline-ad-hiding').length") as? Int
        XCTAssertEqual(styles, 0)
    }
}
