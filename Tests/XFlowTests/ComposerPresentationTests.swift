import AppKit
import WebKit
import XCTest
@testable import XFlow

@MainActor
final class ComposerPresentationTests: XCTestCase, WKNavigationDelegate, WKScriptMessageHandler {
    private var loaded: XCTestExpectation?
    private var events: [String] = []

    func testComposerHidesInitialOpaquePageUntilDialogIsStyled() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: WebColumnView.Coordinator.composerPresentationScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 980, height: 700), configuration: configuration)
        webView.navigationDelegate = self
        loaded = expectation(description: "Composer loading page")
        webView.loadHTMLString("""
        <html style="background:black"><body style="background:black">
        <script>window.initialOpacity = getComputedStyle(document.documentElement).opacity;</script>
        <div id="layers"></div></body></html>
        """, baseURL: URL(string: "https://x.com/compose/post"))
        await fulfillment(of: [try XCTUnwrap(loaded)], timeout: 10)
        let initialOpacity = try await webView.evaluateJavaScript("window.initialOpacity") as? String
        XCTAssertEqual(initialOpacity, "0", "Opaque page must be hidden before page scripts execute")
        let background = try await webView.evaluateJavaScript("getComputedStyle(document.documentElement).backgroundColor") as? String
        XCTAssertEqual(background, "rgba(0, 0, 0, 0)")
        _ = try await webView.evaluateJavaScript("""
        document.getElementById('layers').innerHTML = '<div role="dialog"><div data-testid="tweetTextarea_0" contenteditable="true" role="textbox"></div></div>'; void 0;
        """)
        let ready = try await webView.evaluateJavaScript("""
        getComputedStyle(document.documentElement).opacity === '1' &&
        document.querySelector('[role=dialog]').dataset.mosaicComposeDialog === 'true'
        """) as? Bool
        XCTAssertEqual(ready, true, "Reveal only after the real dialog has its composer theme")
    }

    func testReplyOpenerMovesToExpandedComposerContainingBlock() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        webView.navigationDelegate = self
        loaded = expectation(description: "Inline reply fixture loaded")
        webView.loadHTMLString("""
        <style>
        body { margin:0; } #composer { position:relative; margin:16px; }
        #oldShell { position:relative; margin-left:50px; }
        #submit { width:76px; height:36px; margin-left:auto; display:block; }
        </style>
        <div data-testid="primaryColumn"><div id="composer"><a href="/test"><img width="40" height="40"></a>
        <div id="oldShell"><div data-testid="tweetTextarea_0" role="textbox" contenteditable="true"></div>
        <div data-testid="toolBar"><input type="file" data-testid="fileInput" hidden>
        <button id="submit" data-testid="tweetButtonInline" disabled>Reply</button></div></div></div></div>
        """, baseURL: URL(string: "https://x.com/test/status/123"))
        await fulfillment(of: [try XCTUnwrap(loaded)], timeout: 10)
        for width in [320, 390, 600] {
            webView.frame.size.width = CGFloat(width)
            _ = try await webView.evaluateJavaScript(WebColumnView.Coordinator.integratedColumnThemeScript)
            // Reproduce X retaining the old opener below a positioned editor shell
            // while expansion selects the outer avatar container as the composer.
            _ = try await webView.evaluateJavaScript("""
            void document.getElementById('oldShell').appendChild(document.querySelector('[data-mosaic-reply-opener]'));
            """)
            _ = try await webView.evaluateJavaScript(WebColumnView.Coordinator.integratedColumnThemeScript)
            let aligned = try await webView.evaluateJavaScript("""
            (() => {
              const opener = document.querySelector('[data-mosaic-reply-opener]');
              const button = document.getElementById('submit');
              const a = opener.getBoundingClientRect(), b = button.getBoundingClientRect();
              return opener.parentElement === document.querySelector('[data-mosaic-composer]') &&
                Math.abs(a.left-b.left) < 1 && Math.abs(a.top-b.top) < 1 &&
                Math.abs(a.width-b.width) < 1 && a.right <= innerWidth;
            })()
            """) as? Bool
            XCTAssertEqual(aligned, true, "Expanded reply overlay must match the real button at width \(width)")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.fulfill()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let payload = message.body as? [String: String], let event = payload["event"] {
            events.append(event)
        }
    }

    func testGrokRedirectOriginsStaySeparateFromNativeXBridges() throws {
        for value in ["https://grok.com/imagine", "https://accounts.x.ai/sign-in", "https://accounts.grok.com/login", "https://x.com/i/grok"] {
            XCTAssertTrue(TrustedURLPolicy.isTrustedComposerToolPage(try XCTUnwrap(URL(string: value))))
        }
        for value in ["http://grok.com", "https://grok.com.evil.example", "https://evilgrok.com", "https://user:secret@grok.com", "https://grok.com:8443"] {
            XCTAssertFalse(TrustedURLPolicy.isTrustedComposerToolPage(try XCTUnwrap(URL(string: value))))
        }
        XCTAssertFalse(TrustedURLPolicy.isTrustedXPage(URL(string: "https://grok.com")!))
    }

    func testBlankChildWindowDoesNotReplaceDraft() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 980, height: 700), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        let coordinator = WebColumnView.Coordinator(onNavigation: nil, onDetectedHandle: nil,
            onDetectedProfileImage: nil, onPageTitle: nil, onMediaRequest: nil,
            onUnreadNotificationCountChanged: nil, onComposerPresentationReady: {}, onComposerDismissed: {},
            columnAppearanceMode: .originalX, enableHandleDetection: false,
            enableAccountTextHandleDetection: false, enableBroadHandleDetection: false, onPageReadyScript: nil)
        webView.uiDelegate = coordinator
        webView.navigationDelegate = self
        loaded = expectation(description: "Popup fixture loaded")
        webView.loadHTMLString("<p id=draft>Unsaved test draft</p>", baseURL: URL(string: "https://x.com/compose/post"))
        await fulfillment(of: [try XCTUnwrap(loaded)], timeout: 10)
        let opened = try await webView.evaluateJavaScript("window.child = window.open('about:blank'); Boolean(window.child)") as? Bool
        XCTAssertEqual(opened, true, "X needs a real child Window to populate after opening")
        let draft = try await webView.evaluateJavaScript("document.getElementById('draft').textContent") as? String
        XCTAssertEqual(draft, "Unsaved test draft")
        _ = try await webView.evaluateJavaScript("window.child.close()")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(window.attachedSheet)
        window.close()
        withExtendedLifetime(coordinator) {}
    }

    func testPopupKeepsAccountStoreButDoesNotInheritDialogHiding() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let originalScripts = configuration.userContentController
        originalScripts.addUserScript(WKUserScript(source: WebColumnView.Coordinator.composerPresentationScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let originalStore = configuration.websiteDataStore
        var closed = 0
        let popup = ComposerPopupController(configuration: configuration) { closed += 1 }
        XCTAssertTrue(popup.webView.configuration.websiteDataStore === originalStore)
        XCTAssertFalse(popup.webView.configuration.userContentController === originalScripts)
        XCTAssertEqual(originalScripts.userScripts.count, 1)
        XCTAssertFalse(popup.webView.configuration.userContentController.userScripts.contains {
            $0.source.contains("__mosaicComposerPresentationInstalled")
        })
        popup.close()
        popup.close()
        XCTAssertEqual(closed, 1)
    }

    func testNestedComposerPortalsRemainVisibleAndOnlyFinalCloseDismisses() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "xflowComposerPresentation")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 980, height: 640), configuration: configuration)
        webView.navigationDelegate = self
        loaded = expectation(description: "Fixture loaded")
        webView.loadHTMLString("""
        <body><main id="timeline">Timeline</main><div id="layers">
        <div id="mask" data-testid="mask" style="position:fixed;inset:0;background-color:rgb(0,0,0)"></div>
        <div id="untypedPicker"><label>Schedule date<input type="date"></label></div>
        <div role="dialog" id="composer" style="width:3000px;height:2000px"><div data-testid="tweetTextarea_0" contenteditable="true" role="textbox"></div>
        <div role="tablist" id="tools"><input data-testid="fileInput" type="file"><button data-testid="gifSearchButton">GIF</button><button data-testid="geoButton" aria-label="Tag location" style="pointer-events:none" disabled>Location</button></div>
        <button data-testid="tweetButton" disabled style="opacity:0.2"><span style="color:transparent;opacity:0">Post</span></button></div>
        <div role="menu" id="audience"><button>Everyone</button></div><div data-testid="emojiPicker" id="emoji"><button>Smile</button></div></div></body>
        """, baseURL: URL(string: "https://x.com/compose/post"))
        await fulfillment(of: [try XCTUnwrap(loaded)], timeout: 10)
        _ = try await webView.evaluateJavaScript(WebColumnView.Coordinator.composerPresentationScript)
        let visibility = try await webView.evaluateJavaScript("[getComputedStyle(document.querySelector('#audience button')).visibility, getComputedStyle(document.querySelector('#timeline')).visibility]") as? [String]
        XCTAssertEqual(visibility, ["visible", "hidden"])
        let toolsRole = try await webView.evaluateJavaScript("document.getElementById('tools').getAttribute('role')") as? String
        XCTAssertEqual(toolsRole, "toolbar")
        let location = try await webView.evaluateJavaScript("[document.querySelector('[data-mosaic-location-access]').getAttribute('aria-label'), String(document.querySelector('[data-mosaic-location-access]').disabled), getComputedStyle(document.querySelector('[data-testid=geoButton]')).display]") as? [String]
        XCTAssertEqual(location, ["Location access", "false", "none"])
        let pointerEvents = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('[data-mosaic-location-access]')).pointerEvents") as? String
        XCTAssertEqual(pointerEvents, "auto")

        let emojiVisibility = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('#emoji button')).visibility") as? String
        XCTAssertEqual(emojiVisibility, "visible")
        let portalAppearance = try await webView.evaluateJavaScript("[getComputedStyle(document.querySelector('#untypedPicker input')).visibility, getComputedStyle(document.querySelector('#mask')).backgroundColor]") as? [String]
        XCTAssertEqual(portalAppearance, ["visible", "rgba(0, 0, 0, 0)"])

        let appearance = try await webView.evaluateJavaScript("""
        (() => {
          const button = document.querySelector('[data-testid="tweetButton"]');
          const label = getComputedStyle(button.querySelector('span'));
          const rect = document.getElementById('composer').getBoundingClientRect();
          return [label.color, label.opacity, String(rect.width <= innerWidth), String(rect.height <= innerHeight), getComputedStyle(button).backgroundColor];
        })()
        """) as? [String]
        XCTAssertEqual(appearance, ["rgb(34, 28, 21)", "1", "true", "true", "rgb(151, 143, 130)"])

        XCTAssertTrue(events.contains("ready"), "A hidden preloaded web view must report ready without animation frames")

        // A picker replaces the editor and navigates to another compose route.
        _ = try await webView.evaluateJavaScript("""
        history.pushState({}, '', '/compose/post/schedule');
        document.getElementById('composer').remove();
        document.getElementById('audience').remove();
        document.getElementById('layers').innerHTML = '<div role="dialog" id="schedule"><select aria-label="Month"><option>September</option></select><button data-testid="app-bar-close">Back</button></div>';
        """)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(events.contains("dismissed"))
        let scheduleLayout = try await webView.evaluateJavaScript("""
        (() => {
          const dialog = document.getElementById('schedule');
          const button = getComputedStyle(dialog.querySelector('button'));
          return [String(dialog.getBoundingClientRect().height >= 160), button.color !== button.backgroundColor];
        })()
        """) as? [Any]
        XCTAssertEqual(scheduleLayout?.first as? String, "true", "Schedule forms need enough space for their controls")
        XCTAssertEqual(scheduleLayout?.last as? Bool, true, "Secondary actions must have contrasting labels")
        // A nested close must reach X's own handler without interception.
        let clickReachedX = try await webView.evaluateJavaScript("""
        window.receivedClose = false;
        document.querySelector('button').addEventListener('click', () => { window.receivedClose = true; });
        document.querySelector('button').click();
        window.receivedClose;
        """) as? Bool
        XCTAssertEqual(clickReachedX, true)
        XCTAssertFalse(events.contains("dismissed"))

        // Returning from a picker can leave a brief gap between React mounts.
        _ = try await webView.evaluateJavaScript("""
        document.getElementById('layers').innerHTML = '';
        setTimeout(() => { document.getElementById('layers').innerHTML = '<div role="dialog"><div data-testid="tweetTextarea_0"></div></div>'; }, 100);
        """)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertFalse(events.contains("dismissed"))
        _ = try await webView.evaluateJavaScript("document.getElementById('layers').innerHTML = ''; history.pushState({}, '', '/home');")
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(events.filter { $0 == "dismissed" }.count, 1)
        configuration.userContentController.removeScriptMessageHandler(forName: "xflowComposerPresentation")
    }
}
