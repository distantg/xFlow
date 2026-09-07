import AppKit
import WebKit
import XCTest
@testable import XFlow

@MainActor
final class WebColumnMemoryTests: XCTestCase {
    func testParkingCapturesOnceAndActivationReleasesSnapshot() async {
        let host = DeckWebColumnHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let webView = DeckWKWebView(frame: host.bounds, configuration: WKWebViewConfiguration())
        host.activate()
        host.install(webView)
        var captures = 0
        let parked = expectation(description: "Snapshot completes")
        host.park { _, completion in
            captures += 1
            completion()
        }
        // Wait for WebKit's asynchronous snapshot callback, including its error
        // path for an unloaded page, before testing repeated parked updates.
        for _ in 0..<100 {
            if webView.isHidden { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if webView.isHidden { parked.fulfill() }
        await fulfillment(of: [parked], timeout: 1)
        host.park { _, _ in captures += 1 }
        XCTAssertEqual(captures, 1)
        XCTAssertTrue(host.webView === webView)

        let snapshot = host.subviews.compactMap { $0 as? NSImageView }.first!
        weak var releasedImage: NSImage?
        autoreleasepool {
            let image = NSImage(size: NSSize(width: 390, height: 700))
            snapshot.image = image
            releasedImage = image
        }
        autoreleasepool { host.activate() }
        await Task.yield()
        XCTAssertNil(snapshot.image)
        XCTAssertNil(releasedImage)
        XCTAssertFalse(webView.isHidden)
        host.park { _, _ in captures += 1 }
        XCTAssertEqual(captures, 2)
        host.removeLiveContent { $0.stopLoading() }
        XCTAssertNil(host.webView)
    }

    func testActivationInvalidatesPendingPark() {
        let host = DeckWebColumnHostView(frame: .zero)
        let webView = DeckWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        host.activate()
        host.install(webView)
        var finishCapture: (() -> Void)?
        host.park { _, completion in finishCapture = completion }
        host.activate()
        finishCapture?()
        XCTAssertFalse(webView.isHidden)
        XCTAssertTrue(host.wantsLiveContent)
        host.removeLiveContent { $0.stopLoading() }
    }
}
