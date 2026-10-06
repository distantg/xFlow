import WebKit
import XCTest
@testable import XFlow

@MainActor
final class DirectMessageThemeTests: XCTestCase {
    func testShadowInboxAndComposerUseInheritedMosaicPalettes() async throws {
        let web = try await makeWebView()
        defer { web.stopLoading() }
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)

        for palette in ["dark", "light"] {
            _ = try await web.evaluateJavaScript("document.documentElement.dataset.palette = '\(palette)'")
            let result: [String: String] = try await value(web, """
            (() => {
              const root = document.getElementById('route').shadowRoot;
              const style = selector => getComputedStyle(root.querySelector(selector));
              const probe = document.getElementById('token-probe');
              return {
                ink: style('[data-testid="dm-container"]').color,
                expectedInk: getComputedStyle(probe).color,
                header: style('[data-testid="dm-conversation-header"]').backgroundColor,
                expectedHeader: getComputedStyle(probe).backgroundColor,
                searchInk: style('[data-testid="dm-search-input"]').color,
                searchSurface: style('[data-testid="dm-search-input"]').backgroundColor,
                expectedInset: getComputedStyle(document.getElementById('inset-probe')).backgroundColor,
                composerInk: style('[data-testid="dm-composer-textarea"]').color,
                selectedRow: style('[data-testid^="dm-conversation-item-"]:has([aria-selected="true"])').backgroundColor,
                selectedInset: style('[role="option"][aria-selected="true"] > div').backgroundColor,
                expectedSelection: getComputedStyle(document.getElementById('selection-probe')).backgroundColor,
                rowBlur: style('[role="option"] > div').backdropFilter,
                overlay: getComputedStyle(document.getElementById('overlays').shadowRoot.querySelector('[role="dialog"]')).backgroundColor,
                overlayOpacity: getComputedStyle(document.getElementById('overlays').shadowRoot.querySelector('[role="dialog"]')).opacity,
                canvas: style('.bg-background').backgroundColor,
                outside: getComputedStyle(document.getElementById('outside')).backgroundColor
              };
            })()
            """)
            XCTAssertEqual(result["ink"], result["expectedInk"], palette)
            XCTAssertEqual(result["searchInk"], result["expectedInk"], palette)
            XCTAssertEqual(result["searchSurface"], result["expectedInset"], palette)
            XCTAssertEqual(result["composerInk"], result["expectedInk"], palette)
            XCTAssertEqual(result["header"], result["expectedHeader"], palette)
            XCTAssertEqual(result["overlay"], result["expectedHeader"], palette)
            XCTAssertEqual(result["overlayOpacity"], "0", "Theme paint must preserve X's overlay opening and closing transitions")
            XCTAssertEqual(result["selectedRow"], result["expectedSelection"], palette)
            XCTAssertEqual(result["selectedInset"], "rgba(0, 0, 0, 0)", "Highlight belongs to the full row, not its inset content")
            XCTAssertEqual(result["rowBlur"], "none", "Every virtual row must avoid an additional blur layer")
            XCTAssertEqual(result["canvas"], "rgba(0, 0, 0, 0)", palette)
            XCTAssertEqual(result["outside"], "rgb(9, 19, 29)", "The DM theme must not restyle unrelated page content")
        }
        let overlayStyles: Int = try await value(web, "document.getElementById('overlays').shadowRoot.querySelectorAll('#mosaic-direct-message-shadow-style').length")
        XCTAssertEqual(overlayStyles, 1, "X renders menus and dialogs in a separate shadow root")

        // X owns the overlay lifecycle. Opening, closing, and hiding must keep
        // their native behavior while the same themed surface remains mounted.
        let overlayLifecycle: [String] = try await value(web, """
        (() => {
          const dialog = document.getElementById('overlays').shadowRoot.querySelector('[role="dialog"]');
          dialog.style.opacity = '1';
          const opened = getComputedStyle(dialog).opacity;
          dialog.style.opacity = '0';
          const closing = getComputedStyle(dialog).opacity;
          dialog.style.display = 'none';
          return [opened, closing, getComputedStyle(dialog).display];
        })()
        """)
        XCTAssertEqual(overlayLifecycle, ["1", "0", "none"])
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.removeScript)
        let endingStyle: String = try await value(web, "document.getElementById('overlays').shadowRoot.querySelector('[role=dialog]').getAttribute('style')")
        XCTAssertTrue(endingStyle.contains("opacity: 0"))
        XCTAssertTrue(endingStyle.contains("display: none"))
    }

    func testVirtualRowsKeepGeometryAndNativeControlsKeepTheirStateAndHandlers() async throws {
        let web = try await makeWebView()
        defer { web.stopLoading() }
        let baseline: [Double] = try await value(web, "measureRows()")
        let baselineDate: [Double] = try await value(web, "measureDate()")
        let initialOpacity: String = try await value(web, "getComputedStyle(document.getElementById('route').shadowRoot.getElementById('conversation-0')).opacity")
        XCTAssertEqual(initialOpacity, "0", "Fixture reproduces X's pending entrance animation")
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
        let themed: [Double] = try await value(web, "measureRows()")
        let themedDate: [Double] = try await value(web, "measureDate()")
        XCTAssertEqual(themed, baseline, "Changing painted surfaces must not invalidate X's virtual row offsets")
        XCTAssertEqual(themedDate, baselineDate, "The date pill must not change measured transcript geometry")

        _ = try await web.evaluateJavaScript("""
        (() => {
          const root = document.getElementById('route').shadowRoot;
          const rows = root.getElementById('rows');
          const row = rows.firstElementChild.cloneNode(true);
          row.id = 'inserted-row';
          row.dataset.testid = 'dm-conversation-item-new';
          row.style.top = '216px';
          rows.appendChild(row);
          root.getElementById('filter').click();
          root.getElementById('new-message').click();
          root.getElementById('attach').click();
          root.getElementById('send').click();
          root.getElementById('conversation-0').click();
          const search = root.getElementById('search');
          search.value = 'Community';
          search.dispatchEvent(new Event('input', {bubbles: true}));
          const composer = root.getElementById('composer');
          composer.dispatchEvent(new Event('input', {bubbles: true}));
          return true;
        })()
        """)
        let geometry: [Double] = try await value(web, """
        (() => {
          const root = document.getElementById('route').shadowRoot;
          const original = root.getElementById('conversation-0').getBoundingClientRect();
          const inserted = root.getElementById('inserted-row').getBoundingClientRect();
          return [original.height, inserted.height, inserted.top - original.top, original.width, inserted.width];
        })()
        """)
        XCTAssertEqual(geometry[0], geometry[1])
        XCTAssertEqual(geometry[2], 216)
        XCTAssertEqual(geometry[3], geometry[4])
        let state: [String: String] = try await value(web, """
        (() => {
          const root = document.getElementById('route').shadowRoot;
          return {
            events: events.join(','),
            draft: root.getElementById('composer').value,
            transcript: root.getElementById('message-text').textContent,
            sameNodes: String(originalNodes.every(node => node.isConnected)),
            rowColor: getComputedStyle(root.getElementById('conversation-0')).color,
            insertedColor: getComputedStyle(root.getElementById('inserted-row')).color,
            rowOpacity: getComputedStyle(root.getElementById('conversation-0')).opacity,
            insertedOpacity: getComputedStyle(root.getElementById('inserted-row')).opacity
          };
        })()
        """)
        XCTAssertEqual(state["events"], "filter,new-message,attach,send,conversation,search:Community,composer:Unsent draft ♥")
        XCTAssertEqual(state["draft"], "Unsent draft ♥")
        XCTAssertEqual(state["transcript"], "Message content stays exactly as X supplied it.")
        XCTAssertEqual(state["sameNodes"], "true")
        XCTAssertEqual(state["rowColor"], state["insertedColor"])
        XCTAssertEqual(state["rowOpacity"], "1")
        XCTAssertEqual(state["insertedOpacity"], "1", "New virtual rows must remain visible without waiting for X's entrance animation")

        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.removeScript)
        let restored: [Double] = try await value(web, "measureRows().slice(0, 12)")
        XCTAssertEqual(restored, baseline)
        let originalBackground: String = try await value(web, "getComputedStyle(document.getElementById('route').shadowRoot.querySelector('.bg-background')).backgroundColor")
        XCTAssertEqual(originalBackground, "rgb(0, 0, 0)")
    }

    func testRepeatedAppearanceChangesReleaseAllBridgeResources() async throws {
        let web = try await makeWebView()
        defer { web.stopLoading() }
        for _ in 0..<5 {
            _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
            _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
            let active: [String: Int] = try await value(web, "resourceCounts()")
            XCTAssertEqual(active["styles"], 2)
            XCTAssertEqual(active["observers"], 3)
            XCTAssertEqual(active["intervals"], 0, "Settled message columns must not keep a polling timer")
            XCTAssertEqual(active["timeouts"], 0)

            _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.removeScript)
            let stopped: [String: Int] = try await value(web, "resourceCounts()")
            XCTAssertEqual(stopped["styles"], 0)
            XCTAssertEqual(stopped["observers"], 0)
            XCTAssertEqual(stopped["intervals"], 0)
            XCTAssertEqual(stopped["timeouts"], 0)
        }
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
        // Wait for initial style insertion records before measuring row activity.
        try await Task.sleep(nanoseconds: 30_000_000)
        let callbacksBefore: Int = try await value(web, "metrics.callbacks")
        _ = try await web.evaluateJavaScript("""
        (() => {
          const rows = document.getElementById('route').shadowRoot.getElementById('rows');
          for (let index = 0; index < 1000; index++) {
            const row = document.createElement('div');
            row.dataset.testid = 'dm-conversation-item-' + index;
            rows.appendChild(row);
            row.textContent = 'Recycled row ' + index;
            row.remove();
          }
          return true;
        })()
        """)
        try await Task.sleep(nanoseconds: 30_000_000)
        let callbacksAfter: Int = try await value(web, "metrics.callbacks")
        XCTAssertEqual(callbacksAfter, callbacksBefore, "Virtual list churn must not wake observers or retain message rows")
    }

    func testDeferredRootsAndReplacedHostsAreStyledAndCleanedUp() async throws {
        let web = try await makeWebView(deferredRoots: true)
        defer { web.stopLoading() }
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
        let waiting: [String: Int] = try await value(web, "resourceCounts()")
        XCTAssertEqual(waiting["observers"], 1)
        XCTAssertEqual(waiting["intervals"], 1)
        // Attaching a shadow root does not generate a document mutation. A
        // separate hydration mutation must not cancel the pending style retry.
        _ = try await web.evaluateJavaScript("populateHosts(); document.body.appendChild(document.createElement('div')); true")
        try await waitFor(web, "resourceCounts().styles === 2 && resourceCounts().intervals === 0")

        _ = try await web.evaluateJavaScript("""
        (() => {
          window.oldHost = document.getElementById('route');
          const replacement = document.createElement('div');
          replacement.id = 'route';
          replacement.dataset.testid = 'xchatEmbedRoute';
          oldHost.replaceWith(replacement);
          populateRoute(replacement);
          return true;
        })()
        """)
        try await waitFor(web, "resourceCounts().styles === 2 && oldHost.shadowRoot.querySelectorAll('#mosaic-direct-message-shadow-style').length === 0")
        let replacement: [String: Int] = try await value(web, "resourceCounts()")
        XCTAssertEqual(replacement["observers"], 3, "A replaced host's observer must be disconnected")
        XCTAssertEqual(replacement["intervals"], 0)

        // X can replace all of a root's direct children during a route reset.
        _ = try await web.evaluateJavaScript("document.getElementById('route').shadowRoot.getElementById('mosaic-direct-message-shadow-style').remove(); true")
        try await waitFor(web, "resourceCounts().styles === 2")
        _ = try await web.evaluateJavaScript("document.getElementById('route').remove(); true")
        try await waitFor(web, "resourceCounts().observers === 2")
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.removeScript)
        let stopped: [String: Int] = try await value(web, "resourceCounts()")
        XCTAssertEqual(stopped["styles"], 0)
        XCTAssertEqual(stopped["observers"], 0)
        XCTAssertEqual(stopped["intervals"], 0)
        XCTAssertEqual(stopped["timeouts"], 0)
    }

    func testIntegratedAppearanceOwnsTheShadowThemeLifecycle() async throws {
        let web = try await makeWebView()
        defer { web.stopLoading() }
        for _ in 0..<3 {
            _ = try await web.evaluateJavaScript(WebColumnView.Coordinator.integratedColumnThemeScript)
            _ = try await web.evaluateJavaScript(WebColumnView.Coordinator.integratedColumnThemeScript)
            let active: [String: Int] = try await value(web, "resourceCounts()")
            XCTAssertEqual(active["styles"], 2)
            let state: [String: String] = try await value(web, """
            (() => ({
              appearance: document.documentElement.dataset.mosaicAppearance,
              canvas: getComputedStyle(document.getElementById('route').shadowRoot.querySelector('.bg-background')).backgroundColor,
              draft: document.getElementById('route').shadowRoot.getElementById('composer').value
            }))()
            """)
            XCTAssertEqual(state["appearance"], "integrated")
            XCTAssertEqual(state["canvas"], "rgba(0, 0, 0, 0)")
            XCTAssertEqual(state["draft"], "Unsent draft ♥")

            _ = try await web.evaluateJavaScript(WebColumnView.Coordinator.removeIntegratedColumnThemeScript)
            let stopped: [String: Int] = try await value(web, "resourceCounts()")
            XCTAssertEqual(stopped["styles"], 0)
            XCTAssertEqual(stopped["observers"], 0)
            XCTAssertEqual(stopped["intervals"], 0)
            XCTAssertEqual(stopped["timeouts"], 0)
            let removed: Bool = try await value(web, "!globalThis.__mosaicDirectMessageThemeBridge && !document.getElementById('mosaic-integrated-column-style')")
            XCTAssertTrue(removed)
        }
    }

    func testUnrelatedRoutesAllocateNoResourcesAndChatExitReleasesResources() async throws {
        let web = try await makeWebView(deferredRoots: true)
        defer { web.stopLoading() }
        _ = try await web.evaluateJavaScript("""
        document.getElementById('route').remove();
        document.getElementById('overlays').remove();
        history.replaceState(null, '', '/home');
        true
        """)
        for _ in 0..<3 {
            _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
        }
        let unrelated: [String: Int] = try await value(web, "resourceCounts()")
        XCTAssertEqual(unrelated, ["styles": 0, "observers": 0, "intervals": 0, "timeouts": 0])
        let inactive: Bool = try await value(web, "!globalThis.__mosaicDirectMessageThemeBridge")
        XCTAssertTrue(inactive)

        // URL observation starts discovery before X mounts the chat hosts.
        _ = try await web.evaluateJavaScript("history.pushState(null, '', '/i/chat'); true")
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
        let entering: [String: Int] = try await value(web, "resourceCounts()")
        XCTAssertEqual(entering["observers"], 1)
        XCTAssertEqual(entering["intervals"], 0, "Missing hosts must not trigger page polling")
        _ = try await web.evaluateJavaScript("""
        (() => {
          const route = document.createElement('div');
          route.id = 'route';
          route.dataset.testid = 'xchatEmbedRoute';
          document.querySelector('[data-testid="primaryColumn"]').appendChild(route);
          const overlays = document.createElement('div');
          overlays.id = 'overlays';
          overlays.dataset.testid = 'xchatEmbedOverlays';
          document.body.appendChild(overlays);
          populateHosts();
          return true;
        })()
        """)
        try await waitFor(web, "resourceCounts().styles === 2")

        // SPA URLs can update while the prior route's hosts still exist.
        _ = try await web.evaluateJavaScript("history.pushState(null, '', '/home'); true")
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
        _ = try await web.evaluateJavaScript("document.getElementById('route').remove(); document.getElementById('overlays').remove(); true")
        try await waitFor(web, "!globalThis.__mosaicDirectMessageThemeBridge")
        let exited: [String: Int] = try await value(web, "resourceCounts()")
        XCTAssertEqual(exited, ["styles": 0, "observers": 0, "intervals": 0, "timeouts": 0])
    }

    func testDocumentElementReplacementDoesNotLoseHostDiscoveryOrLeakOldRoots() async throws {
        let web = try await makeWebView(deferredRoots: true)
        defer { web.stopLoading() }
        _ = try await web.evaluateJavaScript("""
        window.replacementDocumentElement = document.documentElement.cloneNode(true);
        document.getElementById('route').remove();
        document.getElementById('overlays').remove();
        true
        """)
        _ = try await web.evaluateJavaScript(DirectMessageThemeBridge.installScript)
        _ = try await web.evaluateJavaScript("""
        document.documentElement.replaceWith(replacementDocumentElement);
        populateHosts();
        true
        """)
        try await waitFor(web, "resourceCounts().styles === 2")

        _ = try await web.evaluateJavaScript("""
        window.detachedHosts = [document.getElementById('route'), document.getElementById('overlays')];
        document.documentElement.replaceWith(document.documentElement.cloneNode(true));
        populateHosts();
        true
        """)
        try await waitFor(web, "resourceCounts().styles === 2 && detachedHosts.every(host => !host.shadowRoot.querySelector('#mosaic-direct-message-shadow-style'))")
        let resources: [String: Int] = try await value(web, "resourceCounts()")
        XCTAssertEqual(resources["observers"], 3)
        XCTAssertEqual(resources["intervals"], 0)
        XCTAssertEqual(resources["timeouts"], 0)
    }

    private func value<T>(_ web: WKWebView, _ script: String) async throws -> T {
        let result = try await web.evaluateJavaScript(script)
        return try XCTUnwrap(result as? T, "Unexpected JavaScript result: \(String(describing: result))")
    }

    private func waitFor(_ web: WKWebView, _ condition: String) async throws {
        for _ in 0..<100 {
            if try await value(web, condition) as Bool { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Timed out waiting for \(condition)")
    }

    private func makeWebView(deferredRoots: Bool = false) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 420, height: 800), configuration: configuration)
        web.loadHTMLString(Self.fixture, baseURL: URL(string: "https://x.com/messages"))
        try await waitFor(web, "document.readyState === 'complete' && typeof populateHosts === 'function'")
        if !deferredRoots { _ = try await web.evaluateJavaScript("populateHosts(); true") }
        return web
    }

    private static let fixture = #"""
    <!doctype html><html data-palette="dark"><head><meta charset="utf-8"><style>
    :root {
      --mosaic-ink: rgb(243, 240, 234); --mosaic-secondary: rgb(187, 184, 179);
      --mosaic-accent: rgb(231, 216, 190); --mosaic-accent-line: rgba(231, 216, 190, .3);
      --mosaic-accent-soft: rgba(231, 216, 190, .12); --mosaic-inset: rgba(0, 0, 0, .13);
      --mosaic-hairline: rgba(255, 255, 255, .12); --mosaic-tab-surface: rgba(61, 61, 58, .94);
      --mosaic-shadow: rgba(0, 0, 0, .25); --mosaic-surface: rgba(35, 35, 33, .4); --mosaic-surface-hover: rgba(231, 216, 190, .08);
    }
    :root[data-palette="light"] {
      --mosaic-ink: rgb(39, 44, 47); --mosaic-secondary: rgb(100, 105, 108);
      --mosaic-accent: rgb(128, 99, 58); --mosaic-accent-line: rgba(128, 99, 58, .3);
      --mosaic-accent-soft: rgba(128, 99, 58, .12); --mosaic-inset: rgba(255, 255, 255, .45);
      --mosaic-hairline: rgba(0, 0, 0, .1); --mosaic-tab-surface: rgba(247, 248, 246, .94);
    }
    body { margin: 0; } #token-probe { color: var(--mosaic-ink); background: var(--mosaic-tab-surface); }
    #inset-probe { background: var(--mosaic-inset); } #selection-probe { background: var(--mosaic-accent-soft); }
    #outside { background: rgb(9, 19, 29); }
    </style></head><body>
    <div id="token-probe"></div><div id="inset-probe"></div><div id="selection-probe"></div><div id="outside">Unrelated page content</div>
    <main role="main"><div data-testid="primaryColumn"><div id="route" data-testid="xchatEmbedRoute"></div></div></main>
    <div id="overlays" data-testid="xchatEmbedOverlays"></div>
    <script>
    const metrics = {observers: new Set(), intervals: new Set(), timeouts: new Set(), callbacks: 0};
    const NativeObserver = MutationObserver;
    window.MutationObserver = class extends NativeObserver {
      constructor(callback) { super((records, observer) => { metrics.callbacks++; callback(records, observer); }); }
      observe(...args) { metrics.observers.add(this); return super.observe(...args); }
      disconnect() { metrics.observers.delete(this); return super.disconnect(); }
    };
    const nativeSetInterval = setInterval.bind(window), nativeClearInterval = clearInterval.bind(window);
    const nativeSetTimeout = setTimeout.bind(window), nativeClearTimeout = clearTimeout.bind(window);
    window.setInterval = (callback, delay, ...args) => {
      const timer = nativeSetInterval(callback, delay, ...args); metrics.intervals.add(timer); return timer;
    };
    window.clearInterval = timer => { metrics.intervals.delete(timer); nativeClearInterval(timer); };
    window.setTimeout = (callback, delay, ...args) => {
      const timer = nativeSetTimeout(() => { metrics.timeouts.delete(timer); callback(...args); }, delay);
      metrics.timeouts.add(timer); return timer;
    };
    window.clearTimeout = timer => { metrics.timeouts.delete(timer); nativeClearTimeout(timer); };
    const events = [], originalNodes = [];
    function populateRoute(host) {
      const root = host.attachShadow({mode: 'open'});
      root.innerHTML = `<style id="native-chat-style">
        :host { display: block; } * { box-sizing: border-box; }
        .bg-background { background: rgb(0, 0, 0); color: white; }
        [data-testid="dm-container"] { font: 16px -apple-system; }
        [data-testid="dm-inbox-panel"] { width: 100%; }
        [data-testid="dm-inbox-header"], [data-testid="dm-conversation-header"] { height: 52px; background: black; }
        [data-testid="dm-search-bar"] { height: 44px; padding: 5px 12px; }
        [data-testid="dm-search-input"] { background: rgb(22, 22, 22); color: white; }
        #rows { position: relative; height: 288px; }
        [data-testid^="dm-conversation-item-"] { position: absolute; left: 0; right: 0; height: 72px; padding: 0; border: 0; color: white; opacity: 0; }
        [data-testid^="dm-conversation-item-"] [role="option"] { display: block; width: 100%; height: 100%; padding: 0; border: 0; }
        [data-testid^="dm-conversation-item-"] [role="option"] > div { height: 100%; padding: 12px; background: black; }
        .text-subtext2 { font-size: 12px; line-height: 16px; } #date-label { font-weight: 600; }
        .text-subtext3 { font-size: 11px; }
        [data-testid="dm-message-list"] { height: 140px; }
        [data-testid="dm-composer-container"] { background: black; }
        [data-testid="dm-composer-textarea"] { height: 44px; color: white; background: black; }
      </style>
      <div class="bg-background"><div data-testid="dm-container">
        <div data-testid="dm-inbox-panel">
          <header data-testid="dm-inbox-header">Chat <button id="filter" data-testid="dm-inbox-dropdown-trigger">All</button><button id="new-message" data-testid="dm-new-chat-button" aria-label="New message">+</button></header>
          <div data-testid="dm-search-bar"><input id="search" data-testid="dm-search-input" placeholder="Search"></div>
          <div id="rows">${[0,1,2].map(index => `<div id="conversation-${index}" data-testid="dm-conversation-item-${index}" style="top:${index * 72}px"><button role="option" aria-selected="${index === 0}"><div><span class="text-primary">Conversation ${index}</span><span class="text-secondary text-subtext2">Message preview</span></div></button></div>`).join('')}</div>
        </div>
        <div data-testid="dm-conversation-header"><span>Trace</span><button aria-label="Conversation info">i</button></div>
        <div data-testid="dm-conversation-content">
          <div class="pointer-events-none"></div><div class="rounded-full"><span id="date-label" class="text-gray-600 text-subtext2">Today</span></div>
          <div data-testid="dm-message-list"><div data-testid="message-1" class="justify-end"><div id="message-text" data-testid="message-text-1">Message content stays exactly as X supplied it.</div><span class="text-subtext3">3:20 PM</span></div></div>
        </div>
        <div data-testid="dm-composer-container"><div data-testid="dm-composer-input-container"><button id="attach" aria-label="Attach media">+</button><textarea id="composer" data-testid="dm-composer-textarea">Unsent draft ♥</textarea><button id="send" aria-label="Send">Send</button></div></div>
      </div></div>`;
      for (const id of ['filter', 'new-message', 'attach', 'send']) root.getElementById(id).onclick = () => events.push(id);
      root.getElementById('conversation-0').onclick = () => events.push('conversation');
      root.getElementById('search').oninput = event => events.push('search:' + event.target.value);
      root.getElementById('composer').oninput = event => events.push('composer:' + event.target.value);
      originalNodes.push(...root.querySelectorAll('button, input, textarea, #message-text'));
    }
    function populateHosts() {
      populateRoute(document.getElementById('route'));
      document.getElementById('overlays').attachShadow({mode: 'open'}).innerHTML = '<div role="dialog" class="bg-background" style="opacity:0"><button>Conversation details</button></div>';
    }
    function measureRows() {
      return Array.from(document.getElementById('route').shadowRoot.querySelectorAll('[data-testid^="dm-conversation-item-"]')).flatMap(row => {
        const rect = row.getBoundingClientRect(); return [rect.top, rect.left, rect.width, rect.height];
      });
    }
    function measureDate() {
      const rect = document.getElementById('route').shadowRoot.getElementById('date-label').getBoundingClientRect();
      return [rect.top, rect.left, rect.width, rect.height];
    }
    function resourceCounts() {
      const hosts = Array.from(document.querySelectorAll('[data-testid="xchatEmbedRoute"], [data-testid="xchatEmbedOverlays"]'));
      return {observers: metrics.observers.size, intervals: metrics.intervals.size, timeouts: metrics.timeouts.size,
        styles: hosts.reduce((count, host) => count + (host.shadowRoot ? host.shadowRoot.querySelectorAll('#mosaic-direct-message-shadow-style').length : 0), 0)};
    }
    </script></body></html>
    """#
}
