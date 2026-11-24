import AppKit
import WebKit
import XCTest
@testable import XFlow

@MainActor
final class WebColumnWheelTests: XCTestCase {
    private final class DeckScrollView: NSScrollView {
        var forwardedEvents = 0
        override func scrollWheel(with event: NSEvent) { forwardedEvents += 1 }
    }

    func testVerticalMouseWheelWithHorizontalNoiseScrollsContentInsteadOfDeck() async throws {
        let deck = DeckScrollView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 1200, height: 500))
        deck.documentView = document
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = DeckWKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 500), configuration: configuration)
        document.addSubview(web)
        let window = NSWindow(contentRect: deck.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = deck
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(web)
        defer { web.stopLoading(); window.close() }
        web.loadHTMLString("""
        <style>body { margin: 0; height: 5000px; }</style>
        <script>window.wheelCount = 0; document.addEventListener('wheel', () => window.wheelCount++);</script>
        <p>Scrollable column content</p>
        """, baseURL: URL(string: "https://x.com/home"))
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("document.readyState === 'complete' && document.body.scrollHeight > innerHeight")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let ready = try await web.evaluateJavaScript("document.readyState === 'complete' && document.body.scrollHeight > innerHeight") as? Bool
        XCTAssertEqual(ready, true)
        // WebKit's scrolling tree is committed after DOM readiness.
        try await Task.sleep(nanoseconds: 200_000_000)
        let event = try wheel(window: window, vertical: -3, horizontal: -2)
        XCTAssertFalse(event.hasPreciseScrollingDeltas)
        XCTAssertTrue(event.phase.isEmpty)
        web.scrollWheel(with: event)
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("window.scrollY")) as? Double ?? 0 > 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let position = try await web.evaluateJavaScript("window.scrollY") as? Double ?? 0
        let count = try await web.evaluateJavaScript("window.wheelCount") as? Int ?? 0
        XCTAssertGreaterThan(position, 0, "A primarily vertical wheel tick must move the actual timeline")
        XCTAssertEqual(count, 1, "WebKit must receive the original wheel event exactly once")
        XCTAssertEqual(deck.forwardedEvents, 0, "Vertical mouse scrolling must not move the deck")
    }

    func testOnlyDominantHorizontalMouseTicksReachDeck() throws {
        let deck = DeckScrollView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 1200, height: 500))
        deck.documentView = document
        let web = DeckWKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        document.addSubview(web)
        let window = NSWindow(contentRect: deck.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = deck
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(web)
        defer { web.stopLoading(); window.close() }
        for (vertical, horizontal) in [(-3, 0), (3, 2), (-3, -3)] {
            web.scrollWheel(with: try wheel(window: window, vertical: Int32(vertical), horizontal: Int32(horizontal)))
        }
        XCTAssertEqual(deck.forwardedEvents, 0)
        web.scrollWheel(with: try wheel(window: window, vertical: 0, horizontal: -3))
        web.scrollWheel(with: try wheel(window: window, vertical: -1, horizontal: -3))
        XCTAssertEqual(deck.forwardedEvents, 2)
        web.scrollWheel(with: try wheel(window: window, vertical: -6, horizontal: -4, phase: .began))
        web.scrollWheel(with: try wheel(window: window, vertical: -1, horizontal: -6, phase: .changed))
        web.scrollWheel(with: try wheel(window: window, vertical: 0, horizontal: 0, phase: .ended))
        XCTAssertEqual(deck.forwardedEvents, 2, "A vertical trackpad gesture stays with the column")
        web.scrollWheel(with: try wheel(window: window, vertical: -1, horizontal: -6, phase: .began))
        web.scrollWheel(with: try wheel(window: window, vertical: -6, horizontal: -1, phase: .changed))
        web.scrollWheel(with: try wheel(window: window, vertical: 0, horizontal: 0, phase: .ended))
        XCTAssertEqual(deck.forwardedEvents, 5, "A horizontal trackpad gesture stays with the deck")
        web.capturesHorizontalScrollInWebContent = true
        web.scrollWheel(with: try wheel(window: window, vertical: 0, horizontal: -3))
        XCTAssertEqual(deck.forwardedEvents, 5, "Web content retains its own horizontal tab/carousel scrolling")
        web.capturesHorizontalScrollInWebContent = false
        web.routeHorizontalScrollToParent = false
        web.scrollWheel(with: try wheel(window: window, vertical: 0, horizontal: -3))
        XCTAssertEqual(deck.forwardedEvents, 5, "Standalone web views never route to the surrounding deck")
    }

    private func wheel(window: NSWindow, vertical: Int32, horizontal: Int32, phase: CGScrollPhase? = nil) throws -> NSEvent {
        let units: CGScrollEventUnit = phase == nil ? .line : .pixel
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                                         wheel1: vertical, wheel2: horizontal, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
        let point = window.convertPoint(toScreen: CGPoint(x: 150, y: 250))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        event.location = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }
}
