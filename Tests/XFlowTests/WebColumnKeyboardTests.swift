import AppKit
import WebKit
import XCTest
@testable import XFlow

@MainActor
final class WebColumnKeyboardTests: XCTestCase {
    private final class KeySink: NSResponder {
        var received: [String] = []
        override func keyDown(with event: NSEvent) { received.append(event.characters ?? "") }
    }

    func testOriginalWebKitKeyInsertsExactlyOnceAndSupportsUndo() async throws {
        let host = DeckWebColumnHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = DeckWKWebView(frame: host.bounds, configuration: configuration)
        host.install(web)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { web.stopLoading(); window.close() }
        web.loadHTMLString("<div id='editor' contenteditable='true' role='textbox'></div><script>window.inputs = 0; document.getElementById('editor').oninput = () => window.inputs++;</script>", baseURL: URL(string: "https://x.com/compose/post"))
        var ready = false
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("Boolean(document.getElementById('editor'))")) as? Bool == true {
                ready = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(ready)
        XCTAssertTrue(window.makeFirstResponder(web))
        _ = try await web.evaluateJavaScript("document.getElementById('editor').focus()")
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        // Send the original event through WebKit, as the real responder chain
        // does. The host must never synthesize its own text insertion.
        web.keyDown(with: event)
        try await Task.sleep(nanoseconds: 200_000_000)
        let value = try await web.evaluateJavaScript("[document.getElementById('editor').textContent, String(window.inputs)]") as? [String]
        XCTAssertEqual(value, ["a", "1"], "The first letter must reach X's existing editor and its input handler once")
        // A late native fallback must not insert or replay the original key.
        host.keyDown(with: event)
        try await Task.sleep(nanoseconds: 100_000_000)
        let duplicate = try await web.evaluateJavaScript("document.getElementById('editor').textContent") as? String
        XCTAssertEqual(duplicate, "a")
        _ = try await web.evaluateJavaScript("document.execCommand('undo')")
        let undone = try await web.evaluateJavaScript("document.getElementById('editor').textContent") as? String
        XCTAssertEqual(undone, "", "Native insertion must preserve the editor's undo history")
    }

    func testWebKitTextFallbackStopsBeforeHostingViewButShortcutsAndNavigationContinue() throws {
        let host = DeckWebColumnHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let web = DeckWKWebView(frame: host.bounds)
        host.install(web)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(web))
        let sink = KeySink()
        host.nextResponder = sink

        func key(_ characters: String, modifiers: NSEvent.ModifierFlags = []) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: 0))
            // This is the fallback arriving at the host AFTER WebKit handled it.
            // Do not intercept the original event en route to the web editor.
            host.keyDown(with: event)
        }
        try key("a")
        try key("A", modifiers: .shift)
        try key("é", modifiers: .option)
        XCTAssertTrue(sink.received.isEmpty, "Text fallback must not reach AppKit's alert-sound handler")
        try key("p", modifiers: .command)
        try key("a", modifiers: .control)
        try key("\r")
        try key("\u{F702}") // Left arrow
        XCTAssertEqual(sink.received, ["p", "a", "\r", "\u{F702}"])

        let other = NSTextView(frame: .zero)
        host.addSubview(other)
        XCTAssertTrue(window.makeFirstResponder(other))
        try key("b")
        XCTAssertEqual(sink.received.last, "b", "Native controls retain their normal responder chain")
        withExtendedLifetime(sink) {}
    }
}
