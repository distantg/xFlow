import JavaScriptCore
import XCTest
@testable import XFlow

final class ColumnAppearanceTests: XCTestCase {
    func testPreferenceDefaultsToMosaic() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(ColumnAppearancePreference.load(from: defaults), .mosaicIntegrated)
    }

    func testPreferencePersistsIntegratedMode() throws {
        let defaults = try makeDefaults()
        ColumnAppearancePreference.save(.mosaicIntegrated, to: defaults)
        XCTAssertEqual(ColumnAppearancePreference.load(from: defaults), .mosaicIntegrated)
    }

    func testInvalidPreferenceFallsBackToMosaic() throws {
        let defaults = try makeDefaults()
        defaults.set("future-mode", forKey: ColumnAppearancePreference.storageKey)
        XCTAssertEqual(ColumnAppearancePreference.load(from: defaults), .mosaicIntegrated)
    }

    func testLaunchSessionRequiresSignedInUIAndWaitsThroughDialogs() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        let login = false, account = false, primary = false, dialog = false;
        const document = {readyState: 'complete', querySelector(selector) {
          if (selector.startsWith('input')) return login ? {} : null;
          if (selector.includes('AccountSwitcher')) return account ? {} : null;
          if (selector.includes('primaryColumn')) return primary ? {} : null;
          if (selector.includes('dialog')) return dialog ? {} : null;
        }};
        """)
        let script = WebColumnView.Coordinator.launchSessionStateScript
        XCTAssertEqual(context.evaluateScript(script)?.toString(), "waiting")
        context.evaluateScript("primary = true")
        XCTAssertEqual(context.evaluateScript(script)?.toString(), "waiting")
        context.evaluateScript("account = true; dialog = true")
        XCTAssertEqual(context.evaluateScript(script)?.toString(), "waiting")
        context.evaluateScript("dialog = false")
        XCTAssertEqual(context.evaluateScript(script)?.toString(), "authenticated")
        context.evaluateScript("login = true")
        XCTAssertEqual(context.evaluateScript(script)?.toString(), "login")
        context.evaluateScript("document.readyState = 'loading'")
        XCTAssertEqual(context.evaluateScript(script)?.toString(), "waiting")
    }

    func testLaunchReadinessWaitsForContentAndVisibleImages() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        let hasPrimary = false, hasContent = false, imageComplete = false;
        const innerHeight = 760;
        const image = { get complete() { return imageComplete; },
          getBoundingClientRect: () => ({top: 100, bottom: 200}) };
        const primary = {querySelector: () => hasContent ? {} : null,
          querySelectorAll: () => [image]};
        const document = {readyState: 'complete', querySelector: () => hasPrimary ? primary : null};
        """)
        let script = WebColumnView.Coordinator.initialContentReadyScript
        XCTAssertFalse(context.evaluateScript(script)?.toBool() ?? true, "SSO without a timeline must stay covered")
        context.evaluateScript("hasPrimary = true")
        XCTAssertFalse(context.evaluateScript(script)?.toBool() ?? true, "An empty app shell is not ready")
        context.evaluateScript("hasContent = true")
        XCTAssertFalse(context.evaluateScript(script)?.toBool() ?? true, "Visible images are still loading")
        context.evaluateScript("imageComplete = true")
        XCTAssertTrue(context.evaluateScript(script)?.toBool() ?? false)
        context.evaluateScript("document.readyState = 'loading'")
        XCTAssertFalse(context.evaluateScript(script)?.toBool() ?? true)
    }

    func testAppearanceScriptsHaveValidJavaScriptSyntax() throws {
        for script in [
            WebColumnView.Coordinator.launchSessionStateScript,
            WebColumnView.Coordinator.initialContentReadyScript,
            WebColumnView.Coordinator.composerPresentationScript,
            WebColumnView.Coordinator.structuralColumnChromeScript,
            WebColumnView.Coordinator.integratedColumnThemeScript,
            WebColumnView.Coordinator.removeIntegratedColumnThemeScript
        ] {
            let context = try XCTUnwrap(JSContext())
            var exception: JSValue?
            context.exceptionHandler = { _, value in exception = value }

            let data = try JSONSerialization.data(withJSONObject: [script])
            let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
            context.evaluateScript("new Function(\(String(encoded.dropFirst().dropLast())))")

            XCTAssertNil(exception, exception?.toString() ?? "Unexpected JavaScript syntax error")
        }
    }

    func testComposerPresentationIsolatesTheDialogAndReportsItsLifecycle() {
        let script = WebColumnView.Coordinator.composerPresentationScript

        XCTAssertTrue(script.contains("body *"))
        XCTAssertTrue(script.contains("visibility: hidden !important"))
        XCTAssertTrue(script.contains("[data-mosaic-compose-dialog=\"true\"] *"))
        XCTAssertTrue(script.contains("[data-testid=\"tweetTextarea_0\"]"))
        XCTAssertTrue(script.contains("editor.closest('[role=\"dialog\"]"))
        XCTAssertTrue(script.contains("send('ready')"))
        XCTAssertTrue(script.contains("send('dismissed')"))
        XCTAssertTrue(script.contains("new MutationObserver(updatePresentation)"))
    }

    func testClosingDialogDoesNotPromoteTimelineComposer() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var events = [], timers = [], update, dialogOpen = true;
        var window = { webkit: { messageHandlers: {
          xflowComposerPresentation: { postMessage: p => events.push(p.event) }
        } } };
        var location = { pathname: '/compose/post' };
        var dialog = { dataset: {}, isConnected: true };
        var inline = { dataset: {}, parentElement: null,
          querySelector: () => ({}) };
        var timelineEditor = { parentElement: inline, closest: () => null };
        var modalEditor = { closest: () => dialog };
        var document = {
          head: { appendChild: () => {} }, documentElement: {},
          addEventListener: () => {},
          createElement: () => ({}),
          querySelectorAll: selector => selector.includes('tweetTextarea')
            ? (dialogOpen ? [timelineEditor, modalEditor] : [timelineEditor])
            : [dialog, inline].filter(n => n.dataset.mosaicComposeDialog === 'true')
        };
        function requestAnimationFrame(f) { f(); }
        function setTimeout(f) { timers.push(f); return timers.length; }
        function clearTimeout() {}
        function MutationObserver(f) { update = f; this.observe = () => {}; }
        """)
        context.evaluateScript(WebColumnView.Coordinator.composerPresentationScript)
        XCTAssertNil(context.exception)
        XCTAssertEqual(context.evaluateScript("events.join(',')")?.toString(), "ready")
        XCTAssertEqual(context.evaluateScript("dialog.dataset.mosaicComposeDialog")?.toString(), "true")
        context.evaluateScript("""
        dialogOpen = false; dialog.isConnected = false;
        update();
        """)
        XCTAssertNil(context.exception)
        XCTAssertEqual(context.evaluateScript("events.join(',')")?.toString(), "ready,dismissed")
        context.evaluateScript("timers.splice(0).forEach(f => f()); update();")
        XCTAssertEqual(context.evaluateScript("events.join(',')")?.toString(), "ready,dismissed")
        XCTAssertTrue(context.evaluateScript("inline.dataset.mosaicComposeDialog === undefined")?.toBool() == true)
        XCTAssertTrue(context.evaluateScript("dialog.dataset.mosaicComposeDialog === undefined")?.toBool() == true)
    }

    func testIntegratedThemeIsIdempotentAndRemovable() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        const __nodes = {};
        const document = {
          documentElement: { dataset: {} },
          head: {
            appendChild(node) {
              __nodes[node.id] = node;
              node.remove = function() { delete __nodes[node.id]; };
            }
          },
          getElementById(id) { return __nodes[id] || null; },
          createElement() { return { id: '', textContent: '' }; }
        };
        """)

        context.evaluateScript(WebColumnView.Coordinator.integratedColumnThemeScript)
        context.evaluateScript(WebColumnView.Coordinator.integratedColumnThemeScript)
        XCTAssertEqual(context.evaluateScript("Object.keys(__nodes).length")?.toInt32(), 1)
        XCTAssertEqual(
            context.evaluateScript("document.documentElement.dataset.mosaicAppearance")?.toString(),
            "integrated"
        )

        context.evaluateScript(WebColumnView.Coordinator.removeIntegratedColumnThemeScript)
        XCTAssertEqual(context.evaluateScript("Object.keys(__nodes).length")?.toInt32(), 0)
        XCTAssertTrue(
            context.evaluateScript("document.documentElement.dataset.mosaicAppearance === undefined")?.toBool() == true
        )
    }

    func testIntegratedThemeUsesContinuousTransparentCanvasAndStableXRoles() {
        let script = WebColumnView.Coordinator.integratedColumnThemeScript

        XCTAssertTrue(script.contains("main[role=\"main\"]"))
        XCTAssertTrue(script.contains("[data-testid=\"primaryColumn\"]"))
        XCTAssertTrue(script.contains("[data-testid=\"primaryColumn\"] *,"))
        XCTAssertTrue(script.contains("[data-testid=\"primaryColumn\"] *::before,"))
        XCTAssertTrue(script.contains("[data-testid=\"primaryColumn\"] *::after"))
        XCTAssertTrue(script.contains("[data-testid=\"cellInnerDiv\"]"))
        XCTAssertTrue(script.contains("[data-testid=\"cellInnerDiv\"]:hover"))
        XCTAssertTrue(script.contains("background: transparent !important"))
        XCTAssertTrue(script.contains("background-color: transparent !important"))
        XCTAssertTrue(script.contains("box-shadow: inset 0 -1px 0 var(--mosaic-hairline) !important"))
        XCTAssertFalse(script.contains("[data-testid=\"cellInnerDiv\"]::before"))
        XCTAssertFalse(script.contains("filter: brightness(1.025) saturate(1.035)"))
        XCTAssertFalse(script.contains("inset: 4px 6px"))
        XCTAssertTrue(script.contains("button[aria-label*=\"Grok\" i]"))
        XCTAssertTrue(script.contains("[data-testid=\"caret\"]"))
        XCTAssertTrue(script.contains("translate: none !important"))
        XCTAssertTrue(script.contains("will-change: auto !important"))
        XCTAssertTrue(script.contains("[role=\"tab\"][aria-selected=\"true\"]::after"))
        XCTAssertTrue(script.contains("[data-testid=\"tweetTextarea_0\"]"))
        XCTAssertTrue(script.contains("[data-testid=\"toolBar\"]"))
        XCTAssertTrue(script.contains(":has([data-testid=\"fileInput\"])"))
        XCTAssertTrue(script.contains(":has([data-testid=\"gifSearchButton\"])"))
        XCTAssertTrue(script.contains("[data-testid=\"tweetButtonInline\"]:disabled"))
        XCTAssertTrue(script.contains("[data-testid=\"tweetButtonInline\"]:not(:disabled):not([aria-disabled=\"true\"])"))
        XCTAssertTrue(script.contains("button:disabled:not([data-testid=\"tweetButtonInline\"])"))
        XCTAssertTrue(script.contains("background: rgb(231, 216, 190) !important"))
        XCTAssertTrue(script.contains("[data-mosaic-composer=\"true\"]:focus-within::before"))
        XCTAssertTrue(script.contains("[data-mosaic-top-tab-shell=\"true\"]"))
        XCTAssertTrue(script.contains("[data-mosaic-top-tab-rail=\"true\"]"))
        XCTAssertTrue(script.contains("overflow-x: auto !important"))
        XCTAssertTrue(script.contains("scroll-snap-type: none !important"))
        XCTAssertTrue(script.contains("--mosaic-tab-surface: rgba(61, 61, 58, 0.94)"))
        XCTAssertTrue(script.contains("-webkit-backdrop-filter: blur(64px) saturate(0.78)"))
        XCTAssertTrue(script.contains("[data-mosaic-column-scrolled=\"true\"]::before"))
        XCTAssertTrue(script.contains("[data-mosaic-column-menu-visible=\"false\"]"))
        XCTAssertTrue(script.contains("[data-mosaic-needs-positioning=\"true\"]"))
        XCTAssertTrue(script.contains("transform: translate3d(0, calc(-100% - 8px), 0)"))
        XCTAssertTrue(script.contains("opacity 180ms ease-out"))
        XCTAssertTrue(script.contains("isolation: isolate !important"))
        XCTAssertTrue(script.contains("z-index: 30 !important"))
        XCTAssertTrue(script.contains("border-radius: 0 0 14px 14px !important"))
        XCTAssertTrue(script.contains("--mosaic-tab-surface: rgba(247, 248, 246, 0.94)"))
        XCTAssertTrue(script.contains("const activeShells = new Set()"))
        XCTAssertTrue(script.contains("const maximumHeight = Math.max(156, tabRect.height + 92)"))
        XCTAssertTrue(script.contains("style.position === 'sticky' || style.position === 'fixed'"))
        XCTAssertTrue(script.contains("return stickyBest || best"))
        XCTAssertTrue(script.contains("shellStyle.position === 'static'"))
        XCTAssertFalse(script.contains("[data-mosaic-top-tab-shell=\"true\"] {\n              position: relative !important"))
        XCTAssertTrue(script.contains("const isScrolled = wasScrolled ? scrollOffset > 2 : scrollOffset > 12"))
        XCTAssertTrue(script.contains("globalThis.__mosaicColumnMenuMotion"))
        XCTAssertTrue(script.contains("visible: true"))
        XCTAssertTrue(script.contains("settleUntil: Infinity"))
        XCTAssertTrue(script.contains("noteColumnMenuScrollIntent(event.deltaY)"))
        XCTAssertTrue(script.contains("event.key === 'PageDown'"))
        XCTAssertTrue(script.contains("event.key === 'PageUp'"))
        XCTAssertTrue(script.contains("document.addEventListener('keydown', handlers.keydown, true)"))
        XCTAssertTrue(WebColumnView.Coordinator.removeIntegratedColumnThemeScript.contains(
            "document.removeEventListener('keydown', handlers.keydown, true)"
        ))
        XCTAssertTrue(script.contains("setColumnMenuVisible(scrollDelta < 0)"))
        XCTAssertTrue(script.contains("columnMenuClock() <= menuState.settleUntil"))
        XCTAssertTrue(script.contains("state.settleUntil = 0"))
        XCTAssertFalse(script.contains("menuState.inputUntil"))
        XCTAssertTrue(script.contains("globalThis.__mosaicSetColumnMenuVisible = setColumnMenuVisible"))
        XCTAssertTrue(script.contains("const targetOffset = scrollTarget"))
        XCTAssertTrue(script.contains("updateTopTabScrollState(event.target)"))
        XCTAssertTrue(script.contains("globalThis.__mosaicRefreshFrame = requestAnimationFrame"))
        XCTAssertTrue(script.contains("xflowTopTabScrollCapture"))
        XCTAssertTrue(script.contains("event.preventDefault()"))
        XCTAssertTrue(script.contains("const horizontalIntent = Math.abs(event.deltaX) >= Math.abs(event.deltaY)"))
        XCTAssertTrue(script.contains("cancelTopTabGlide(tabList)"))
        XCTAssertTrue(script.contains("queueTopTabGlide"))
        XCTAssertTrue(script.contains("requestAnimationFrame(glide)"))
        XCTAssertTrue(script.contains("mosaicColumnScrolled"))
        XCTAssertTrue(script.contains("updateTopTabScrollState"))
        XCTAssertTrue(script.contains("markTopTabRails"))
        XCTAssertTrue(script.contains("[data-mosaic-volume-button=\"true\"]"))
        XCTAssertTrue(script.contains("[data-mosaic-volume-slider=\"true\"]"))
        XCTAssertTrue(script.contains("[data-mosaic-volume-popover=\"true\"]"))
        XCTAssertTrue(script.contains("markVideoVolumeControls"))
        XCTAssertTrue(script.contains("--mosaic-video-control-surface"))
        XCTAssertTrue(script.contains("::-webkit-slider-thumb"))
        XCTAssertTrue(script.contains("transform: scale(0.68)"))
        XCTAssertTrue(script.contains("transform-origin: 50% 100%"))
        XCTAssertTrue(script.contains("width: 10px"))
        XCTAssertTrue(script.contains("[data-mosaic-thread-connector=\"true\"]"))
        XCTAssertTrue(script.contains("markConversationConnectors"))
        XCTAssertTrue(script.contains("centerDelta <= 4"))
        XCTAssertTrue(script.contains("--mosaic-thread-line"))
        XCTAssertTrue(script.contains("[data-mosaic-reply-context=\"true\"] a"))
        XCTAssertTrue(script.contains("markReplyContexts"))
        XCTAssertTrue(script.contains("/^replying to(?:\\s|$)/i"))
        XCTAssertTrue(script.contains("[data-mosaic-post-indicator=\"true\"]"))
        XCTAssertTrue(script.contains("markTransientPostIndicators"))
        XCTAssertTrue(script.contains("/(^|\\s)posted$/i"))
        XCTAssertTrue(script.contains("--mosaic-transient-surface"))
        XCTAssertTrue(script.contains("-webkit-backdrop-filter: blur(30px)"))
        XCTAssertTrue(script.contains("[data-mosaic-subscribe-button=\"true\"]"))
        XCTAssertTrue(script.contains("markSubscribeButtons"))
        XCTAssertTrue(script.contains("/^subscribed?$/i"))
        XCTAssertTrue(script.contains("--mosaic-outline-button-ink"))
        XCTAssertTrue(script.contains("[data-mosaic-synthetic-label=\"true\"]"))
        XCTAssertTrue(script.contains("hasPostButton.dataset.mosaicSyntheticLabel = 'true'"))
        XCTAssertTrue(script.contains("const isReplyAction"))
        XCTAssertTrue(script.contains("/(^|\\s)reply(\\s|$)/i"))
        XCTAssertTrue(script.contains("--mosaic-reply-label-image"))
        XCTAssertTrue(script.contains("isReplyAction ? 'var(--mosaic-reply-label-image)' : 'var(--mosaic-post-label-image)'"))
        XCTAssertFalse(script.contains("if (!isReplyAction)"))
        XCTAssertTrue(script.contains("[data-testid=\"tweetButtonInline\"]:not([data-mosaic-synthetic-label=\"true\"])"))
        XCTAssertTrue(script.contains("border: 1.5px solid rgba(231, 216, 190, 0.96)"))
        XCTAssertTrue(script.contains("-webkit-text-fill-color: rgb(255, 255, 255)"))
        XCTAssertFalse(script.contains("outline: 2px solid rgba(231, 216, 190, 0.92)"))
        XCTAssertTrue(script.contains("--mosaic-post-halo-core"))
        XCTAssertTrue(script.contains("--mosaic-post-halo"))
        XCTAssertTrue(script.contains("0 0 5px var(--mosaic-post-halo-core)"))
        XCTAssertTrue(script.contains("0 0 18px var(--mosaic-post-halo)"))
        XCTAssertTrue(script.contains("0 0 6px var(--mosaic-post-halo-core-hover)"))
        XCTAssertTrue(script.contains("0 0 22px var(--mosaic-post-halo-hover)"))
        XCTAssertTrue(script.contains("[data-testid=\"tweetButtonInline\"]:disabled:hover"))
        XCTAssertTrue(script.contains("background: var(--mosaic-accent-soft) !important"))
        XCTAssertFalse(script.contains("text-shadow: 0 1px 2px rgba(54, 43, 30"))
        XCTAssertTrue(script.contains("--mosaic-post-label-image"))
        XCTAssertTrue(script.contains("background-image: var(--mosaic-composer-label-image, var(--mosaic-post-label-image))"))
        XCTAssertTrue(script.contains("[data-mosaic-composer=\"true\"]::after"))
        XCTAssertTrue(script.contains("--mosaic-post-label-left"))
        XCTAssertTrue(script.contains("const buttonRect = hasPostButton.getBoundingClientRect()"))
        XCTAssertTrue(script.contains("filter: blur(16px)"))
        XCTAssertTrue(script.contains("--mosaic-accent-button"))
        XCTAssertTrue(script.contains("-webkit-text-fill-color"))
        XCTAssertTrue(script.contains("data-mosaic-composer"))
        XCTAssertTrue(script.contains("markInlineComposers"))
        XCTAssertTrue(script.contains("ancestor.querySelector('a[href] img')"))
        XCTAssertTrue(script.contains("[role=\"textbox\"]:not([data-testid=\"tweetTextarea_0\"])"))
        XCTAssertTrue(script.contains("form[role=\"search\"] input"))
        XCTAssertTrue(script.contains("input[data-testid=\"SearchBox_Search_Input\"]:focus-visible"))
        XCTAssertTrue(script.contains("prefers-reduced-transparency"))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "ColumnAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
