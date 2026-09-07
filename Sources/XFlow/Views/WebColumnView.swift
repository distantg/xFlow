import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

final class DeckWKWebView: WKWebView {
    var routeHorizontalScrollToParent: Bool = true
    var capturesHorizontalScrollInTopTabRail = false {
        didSet {
            guard capturesHorizontalScrollInTopTabRail else { return }
            isForwardingHorizontalSequence = false
            gestureAxisLock = .undecided
        }
    }
    private var isForwardingHorizontalSequence = false
    private var gestureAxisLock: GestureAxisLock = .undecided
    private weak var columnMenuClipView: NSClipView?
    private var columnMenuBoundsObserver: NSObjectProtocol?
    private var columnMenuKeyMonitor: Any?
    private var lastColumnMenuScrollY: CGFloat = 0
    private var columnMenuObservationReadyAt = ProcessInfo.processInfo.systemUptime + 0.24

    private enum GestureAxisLock {
        case undecided
        case horizontal
        case vertical
    }

    deinit {
        if let columnMenuBoundsObserver {
            NotificationCenter.default.removeObserver(columnMenuBoundsObserver)
        }
        if let columnMenuKeyMonitor {
            NSEvent.removeMonitor(columnMenuKeyMonitor)
        }
    }

    func installColumnMenuScrollObservation() {
        guard let nativeScrollView = subviews.compactMap({ $0 as? NSScrollView }).first else { return }
        let clipView = nativeScrollView.contentView
        guard columnMenuClipView !== clipView else { return }

        if let columnMenuBoundsObserver {
            NotificationCenter.default.removeObserver(columnMenuBoundsObserver)
        }
        columnMenuClipView = clipView
        lastColumnMenuScrollY = clipView.bounds.minY
        clipView.postsBoundsChangedNotifications = true
        columnMenuBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.columnMenuBoundsDidChange()
        }
        if columnMenuKeyMonitor == nil {
            columnMenuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleColumnMenuKey(event)
                return event
            }
        }
    }

    func resetColumnMenuScrollState(restoringPosition: Bool) {
        installColumnMenuScrollObservation()
        if let columnMenuClipView {
            lastColumnMenuScrollY = columnMenuClipView.bounds.minY
        }
        columnMenuObservationReadyAt = ProcessInfo.processInfo.systemUptime + (restoringPosition ? 3.4 : 0.24)
        evaluateJavaScript("globalThis.__mosaicSetColumnMenuVisible && globalThis.__mosaicSetColumnMenuVisible(true);")
    }

    private func columnMenuBoundsDidChange() {
        guard let columnMenuClipView else { return }
        let scrollY = columnMenuClipView.bounds.minY
        let delta = scrollY - lastColumnMenuScrollY
        lastColumnMenuScrollY = scrollY
        guard abs(delta) >= 0.5,
              ProcessInfo.processInfo.systemUptime >= columnMenuObservationReadyAt else { return }

        let shouldShow = scrollY <= 2 || delta < 0
        setColumnMenuVisible(shouldShow)
    }

    private func handleColumnMenuKey(_ event: NSEvent) {
        guard let window else { return }
        let focusedView = window.firstResponder as? NSView
        let focusIsInsideColumn = focusedView === self || focusedView?.isDescendant(of: self) == true
        let mousePoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard focusIsInsideColumn || bounds.contains(mousePoint) else { return }

        switch event.keyCode {
        case 116, 115: // Page Up, Home
            setColumnMenuVisible(true)
        case 121, 119: // Page Down, End
            setColumnMenuVisible(false)
        default:
            break
        }
    }

    private func setColumnMenuVisible(_ visible: Bool) {
        let javaScriptValue = visible ? "true" : "false"
        evaluateJavaScript(
            "globalThis.__mosaicSetColumnMenuVisible && globalThis.__mosaicSetColumnMenuVisible(\(javaScriptValue));"
        )
    }

    override func scrollWheel(with event: NSEvent) {
        let verticalScroll = abs(event.scrollingDeltaY) > max(0.35, abs(event.scrollingDeltaX))
        if verticalScroll {
            // A direct trackpad or mouse-wheel gesture should never be swallowed by
            // the short restoration grace period used when a column initializes.
            columnMenuObservationReadyAt = 0
            if !capturesHorizontalScrollInTopTabRail {
                setColumnMenuVisible(event.scrollingDeltaY > 0)
            }
        }
        if routeHorizontalScrollToParent && !capturesHorizontalScrollInTopTabRail {
            let horizontal = abs(event.scrollingDeltaX)
            let vertical = abs(event.scrollingDeltaY)

            let phase = event.phase
            let momentum = event.momentumPhase
            let hasPhasedGesture = !phase.isEmpty || !momentum.isEmpty
            let clearHorizontalIntent = horizontal > max(0.55, vertical * 0.52)
            let clearVerticalIntent = vertical > max(0.95, horizontal * 1.06)

            if hasPhasedGesture {
                if phase.contains(.began) || phase.contains(.mayBegin) {
                    if clearHorizontalIntent {
                        gestureAxisLock = .horizontal
                        isForwardingHorizontalSequence = true
                    } else if clearVerticalIntent {
                        gestureAxisLock = .vertical
                        isForwardingHorizontalSequence = false
                    } else {
                        gestureAxisLock = .undecided
                        isForwardingHorizontalSequence = false
                    }
                } else if gestureAxisLock == .undecided {
                    if clearHorizontalIntent {
                        gestureAxisLock = .horizontal
                        isForwardingHorizontalSequence = true
                    } else if clearVerticalIntent {
                        gestureAxisLock = .vertical
                        isForwardingHorizontalSequence = false
                    }
                }

                let shouldForward = gestureAxisLock == .horizontal ||
                    (isForwardingHorizontalSequence && !momentum.isEmpty)
                if shouldForward, let parentScrollView = nearestParentHorizontalScrollView() {
                    parentScrollView.scrollWheel(with: event)

                    if phase.contains(.ended) ||
                        phase.contains(.cancelled) ||
                        momentum.contains(.ended) ||
                        momentum.contains(.cancelled) {
                        isForwardingHorizontalSequence = false
                        gestureAxisLock = .undecided
                    }
                    return
                }

                if phase.contains(.ended) ||
                    phase.contains(.cancelled) {
                    if momentum.isEmpty {
                        isForwardingHorizontalSequence = false
                        gestureAxisLock = .undecided
                    }
                }
            } else {
                // Mouse wheel (no gesture phase): only forward when horizontal clearly dominates.
                if clearHorizontalIntent,
                   let parentScrollView = nearestParentHorizontalScrollView() {
                    parentScrollView.scrollWheel(with: event)
                    return
                } else {
                    isForwardingHorizontalSequence = false
                    gestureAxisLock = .undecided
                }
            }
        }
        super.scrollWheel(with: event)
    }

    private func nearestParentHorizontalScrollView() -> NSScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? NSScrollView,
               let documentView = scrollView.documentView,
               documentView.frame.width > scrollView.contentView.bounds.width + 1 {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}

final class DeckWebColumnHostView: NSView {
    private let snapshotView = NSImageView()
    private(set) var webView: DeckWKWebView?
    private var lifecycleGeneration = 0
    private var isHibernating = false
    private(set) var wantsLiveContent = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        snapshotView.imageScaling = .scaleProportionallyUpOrDown
        snapshotView.alphaValue = 0.82
        snapshotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(snapshotView)
        NSLayoutConstraint.activate([
            snapshotView.leadingAnchor.constraint(equalTo: leadingAnchor),
            snapshotView.trailingAnchor.constraint(equalTo: trailingAnchor),
            snapshotView.topAnchor.constraint(equalTo: topAnchor),
            snapshotView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func install(_ webView: DeckWKWebView) {
        lifecycleGeneration += 1
        isHibernating = false
        self.webView = webView
        snapshotView.isHidden = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func activate() {
        if !wantsLiveContent {
            lifecycleGeneration += 1
        }
        wantsLiveContent = true
        isHibernating = false
        webView?.isHidden = false
        snapshotView.isHidden = true
    }

    func park(captureState: @escaping (WKWebView, @escaping () -> Void) -> Void) {
        wantsLiveContent = false
        guard let webView else { return }
        guard !isHibernating else { return }
        isHibernating = true
        lifecycleGeneration += 1
        let generation = lifecycleGeneration

        captureState(webView) { [weak self, weak webView] in
            guard let self, let webView,
                  self.lifecycleGeneration == generation,
                  self.webView === webView,
                  !self.wantsLiveContent else { return }

            webView.takeSnapshot(with: nil) { [weak self, weak webView] image, _ in
                guard let self, let webView,
                      self.lifecycleGeneration == generation,
                      self.webView === webView,
                      !self.wantsLiveContent else { return }
                if let image {
                    self.snapshotView.image = image
                    self.snapshotView.isHidden = false
                }
                // Keep the web view and its page alive so X's virtualized timeline,
                // navigation state, and exact reading position remain untouched.
                // Hiding it lets WebKit discard compositing work while media remains
                // explicitly suspended by WebColumnView.
                webView.isHidden = true
                self.isHibernating = false
            }
        }
    }

    func removeLiveContent(teardown: (WKWebView) -> Void) {
        lifecycleGeneration += 1
        wantsLiveContent = false
        isHibernating = false
        guard let webView else { return }
        teardown(webView)
        webView.removeFromSuperview()
        self.webView = nil
    }
}

struct WebColumnView: NSViewRepresentable {
    let url: URL
    let refreshKey: String
    let accountID: UUID
    let filter: ColumnFilter
    var columnAppearanceMode: ColumnAppearanceMode = .originalX
    var onNavigation: ((URL?) -> Void)? = nil
    var onDetectedHandle: ((String) -> Void)? = nil
    var onDetectedProfileImage: ((URL?) -> Void)? = nil
    var onPageTitle: ((String?) -> Void)? = nil
    var onMediaRequest: ((MediaRequest) -> Void)? = nil
    var onUnreadNotificationCountChanged: ((Int, NotificationActivity?) -> Void)? = nil
    var onComposerPresentationReady: (() -> Void)? = nil
    var onComposerDismissed: (() -> Void)? = nil
    var enableChromeStripping: Bool = true
    var enableMediaCapture: Bool = true
    var enableHandleDetection: Bool = true
    var enableAccountTextHandleDetection: Bool = false
    var enableBroadHandleDetection: Bool = false
    var onPageReadyScript: String? = nil
    var routeHorizontalScrollToParent: Bool = true
    var isLive: Bool = true
    var isMediaSuspended: Bool = false
    var onInitialContentReady: (() -> Void)? = nil
    var onLaunchSessionResolved: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigation: onNavigation,
            onDetectedHandle: onDetectedHandle,
            onDetectedProfileImage: onDetectedProfileImage,
            onPageTitle: onPageTitle,
            onMediaRequest: onMediaRequest,
            onUnreadNotificationCountChanged: onUnreadNotificationCountChanged,
            onComposerPresentationReady: onComposerPresentationReady,
            onComposerDismissed: onComposerDismissed,
            columnAppearanceMode: columnAppearanceMode,
            enableHandleDetection: enableHandleDetection,
            enableAccountTextHandleDetection: enableAccountTextHandleDetection,
            enableBroadHandleDetection: enableBroadHandleDetection,
            onPageReadyScript: onPageReadyScript
        )
    }

    func makeNSView(context: Context) -> DeckWebColumnHostView {
        let hostView = DeckWebColumnHostView(frame: .zero)
        configureCoordinator(context.coordinator)
        if isLive {
            hostView.activate()
            hostView.install(makeWebView(coordinator: context.coordinator))
        }
        return hostView
    }

    private func makeWebView(coordinator: Coordinator) -> DeckWKWebView {
        let configuration = WebSessionPool.shared.configuration(for: accountID)
        let contentController = configuration.userContentController
        if enableMediaCapture {
            contentController.add(coordinator, name: Coordinator.mediaMessageName)
            contentController.addUserScript(WKUserScript(
                source: Coordinator.mediaCaptureScript,
                // Register media interception before X installs its window-level handlers.
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        if onUnreadNotificationCountChanged != nil {
            contentController.add(coordinator, name: Coordinator.unreadCountMessageName)
            contentController.addUserScript(WKUserScript(
                source: Coordinator.unreadCountScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }

        if onComposerPresentationReady != nil || onComposerDismissed != nil {
            contentController.add(coordinator, name: Coordinator.composerPresentationMessageName)
            contentController.addUserScript(WKUserScript(
                source: Coordinator.composerPresentationScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }

        if enableChromeStripping {
            contentController.add(coordinator, name: Coordinator.topTabScrollMessageName)
            contentController.addUserScript(WKUserScript(
                source: Coordinator.structuralColumnChromeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))

        }

        let webView = DeckWKWebView(frame: .zero, configuration: configuration)
        coordinator.deckWebView = webView
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.underPageBackgroundColor = .clear
        setWebKitBoolean(
            true,
            selectorName: "_setDrawsTransparentBackground:",
            on: webView
        )
        setWebKitBoolean(
            false,
            selectorName: "_setDrawsBackground:",
            on: webView
        )
        let opaqueSetter = NSSelectorFromString("setOpaque:")
        if webView.responds(to: opaqueSetter) {
            webView.setValue(false, forKey: "opaque")
        }
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.layer?.isOpaque = false
        webView.allowsBackForwardNavigationGestures = false
        webView.routeHorizontalScrollToParent = routeHorizontalScrollToParent
        webView.installColumnMenuScrollObservation()
        if let nativeScrollView = webView.subviews.compactMap({ $0 as? NSScrollView }).first {
            nativeScrollView.drawsBackground = false
            nativeScrollView.backgroundColor = .clear
            nativeScrollView.hasHorizontalScroller = false
            nativeScrollView.horizontalScrollElasticity = .none
        }

        coordinator.currentURL = url
        coordinator.refreshKey = refreshKey
        coordinator.filter = filter
        coordinator.accountID = accountID

        webView.load(URLRequest(url: url))
        return webView
    }

    private func setWebKitBoolean(
        _ value: Bool,
        selectorName: String,
        on webView: WKWebView
    ) {
        let selector = NSSelectorFromString(selectorName)
        guard webView.responds(to: selector),
              let implementation = webView.method(for: selector) else { return }

        typealias BooleanSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
        let setter = unsafeBitCast(implementation, to: BooleanSetter.self)
        setter(webView, selector, value)
    }

    func updateNSView(_ hostView: DeckWebColumnHostView, context: Context) {
        configureCoordinator(context.coordinator)

        if !isLive {
            if let webView = hostView.webView {
                suspendMedia(in: webView, suspended: true)
            }
            hostView.park(
                captureState: { webView, completion in
                    context.coordinator.captureRestorationState(in: webView, completion: completion)
                }
            )
            return
        }

        hostView.activate()
        let webView: DeckWKWebView
        if let existing = hostView.webView {
            webView = existing
        } else {
            webView = makeWebView(coordinator: context.coordinator)
            hostView.install(webView)
        }
        suspendMedia(in: webView, suspended: isMediaSuspended)

        update(webView: webView, coordinator: context.coordinator)
    }

    private func configureCoordinator(_ coordinator: Coordinator) {
        coordinator.onNavigation = onNavigation
        coordinator.onDetectedHandle = onDetectedHandle
        coordinator.onDetectedProfileImage = onDetectedProfileImage
        coordinator.onLaunchSessionResolved = onLaunchSessionResolved
        coordinator.onInitialContentReady = onInitialContentReady
        coordinator.onPageTitle = onPageTitle
        coordinator.onMediaRequest = onMediaRequest
        coordinator.onUnreadNotificationCountChanged = onUnreadNotificationCountChanged
        coordinator.onComposerPresentationReady = onComposerPresentationReady
        coordinator.onComposerDismissed = onComposerDismissed
        coordinator.columnAppearanceMode = columnAppearanceMode
        coordinator.enableHandleDetection = enableHandleDetection
        coordinator.enableAccountTextHandleDetection = enableAccountTextHandleDetection
        coordinator.enableBroadHandleDetection = enableBroadHandleDetection
        coordinator.onPageReadyScript = onPageReadyScript
    }

    private func update(webView: WKWebView, coordinator: Coordinator) {
        if let webView = webView as? DeckWKWebView {
            webView.routeHorizontalScrollToParent = routeHorizontalScrollToParent
        }

        if coordinator.accountID != accountID {
            coordinator.accountID = accountID
            coordinator.currentURL = url
            coordinator.filter = filter
            webView.load(URLRequest(url: url))
            return
        }

        if coordinator.appliedColumnAppearanceMode != columnAppearanceMode {
            coordinator.applyColumnAppearance(to: webView)
        }

        if coordinator.currentURL != url {
            coordinator.currentURL = url
            coordinator.filter = filter
            webView.load(URLRequest(url: url))
            return
        }

        if coordinator.refreshKey != refreshKey {
            coordinator.refreshKey = refreshKey
            coordinator.filter = filter
            // Replace the current history entry so repeated refreshes cannot retain a
            // chain of page snapshots. The target route also recovers login redirects.
            let target = JavaScriptEncoding.stringLiteral(url.absoluteString)
            webView.evaluateJavaScript("window.location.replace(\(target));") { _, error in
                if error != nil {
                    webView.load(URLRequest(url: url))
                }
            }
            return
        }

        if coordinator.filter != filter {
            coordinator.filter = filter
            coordinator.applyFilter(to: webView)
        }
    }

    private func suspendMedia(in webView: WKWebView, suspended: Bool) {
        if #available(macOS 11.3, *) {
            webView.setAllMediaPlaybackSuspended(suspended, completionHandler: nil)
        }
        webView.evaluateJavaScript(
            "window.__mosaicBackgroundSuspended = \(suspended ? "true" : "false");" +
            (suspended ? "" : "window.dispatchEvent(new Event('mosaicresume'));")
        )
    }

    static func dismantleNSView(_ nsView: DeckWebColumnHostView, coordinator: Coordinator) {
        nsView.removeLiveContent(teardown: teardownWebView)
    }

    private static func teardownWebView(_ nsView: WKWebView) {
        if #available(macOS 12.0, *) {
            nsView.closeAllMediaPresentations { }
        }
        nsView.evaluateJavaScript("""
        (function() {
          document.querySelectorAll('video, audio').forEach(function(node) {
            try {
              if (node.__xflowOriginalPause) {
                node.__xflowOriginalPause();
              } else {
                node.pause && node.pause();
              }
              node.muted = true;
            } catch (_) {}
          });
        })();
        """)
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.mediaMessageName)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.unreadCountMessageName)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.topTabScrollMessageName)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.composerPresentationMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        enum NavigationDisposition: Equatable {
            case allowInWebView
            case openExternally
            case cancel
        }

        static let mediaMessageName = "xflowMediaRequest"
        static let unreadCountMessageName = "xflowUnreadCount"
        static let topTabScrollMessageName = "xflowTopTabScrollCapture"
        static let composerPresentationMessageName = "xflowComposerPresentation"
        static let composerAttachmentContentTypes: [UTType] = [.image, .movie]

        static let composerPresentationScript = """
        (function() {
          if (window.__mosaicComposerPresentationInstalled) return;
          window.__mosaicComposerPresentationInstalled = true;

          const style = document.createElement('style');
          style.id = 'mosaic-composer-presentation-style';
          style.textContent = `
            html,
            body,
            #react-root,
            [data-testid="react-root"] {
              background: transparent !important;
              background-color: transparent !important;
              overflow: hidden !important;
            }

            body * {
              visibility: hidden !important;
            }

            [data-mosaic-compose-dialog="true"],
            [data-mosaic-compose-dialog="true"] * {
              visibility: visible !important;
            }

            [data-mosaic-compose-dialog="true"][data-mosaic-compose-mode="inline"] {
              position: fixed !important;
              top: 50% !important;
              left: 50% !important;
              width: min(760px, calc(100vw - 32px)) !important;
              max-width: 760px !important;
              transform: translate(-50%, -50%) !important;
            }
          `;
          (document.head || document.documentElement).appendChild(style);

          const installedAt = Date.now();
          let hasSeenComposer = false;
          let hasSeenDialog = false;
          let hasReportedReady = false;
          let hasReportedDismissal = false;
          let dismissalTimer = 0;

          function send(event) {
            try {
              const handler = window.webkit &&
                window.webkit.messageHandlers &&
                window.webkit.messageHandlers.xflowComposerPresentation;
              if (handler) handler.postMessage({ event });
            } catch (_) {}
          }

          function inlineComposer(editor) {
            const primaryColumn = editor.closest('[data-testid="primaryColumn"]');
            let candidate = editor.parentElement;
            while (candidate && candidate !== primaryColumn) {
              const hasPostButton = candidate.querySelector(
                '[data-testid="tweetButton"], [data-testid="tweetButtonInline"]'
              );
              const hasMediaControls = candidate.querySelector(
                '[data-testid="fileInput"], [data-testid="gifSearchButton"], [aria-label*="media" i]'
              );
              if (hasPostButton && hasMediaControls) {
                let composer = candidate;
                let ancestor = candidate.parentElement;
                for (let level = 0; ancestor && ancestor !== primaryColumn && level < 4; level += 1) {
                  if (ancestor.querySelector('a[href] img')) {
                    composer = ancestor;
                    break;
                  }
                  ancestor = ancestor.parentElement;
                }
                return composer;
              }
              candidate = candidate.parentElement;
            }
            return null;
          }

          function composerSurface() {
            const editors = Array.from(document.querySelectorAll(
              '[data-testid="tweetTextarea_0"], [contenteditable="true"][role="textbox"]'
            ));
            for (const editor of editors) {
              const dialog = editor.closest('[role="dialog"], [data-testid="sheetDialog"]');
              if (dialog) return { node: dialog, mode: 'dialog' };
            }
            // Closing X's dialog exposes the timeline editor. It must never
            // become a replacement overlay or keep the native blur alive.
            if (hasSeenDialog || !location.pathname.startsWith('/compose/post')) return null;
            const editor = editors[0];
            if (!editor) return null;
            if (Date.now() - installedAt < 900) return null;
            const inline = inlineComposer(editor);
            return inline ? { node: inline, mode: 'inline' } : null;
          }

          function reportReadyAfterPaint(dialog) {
            if (hasReportedReady) return;
            hasReportedReady = true;
            requestAnimationFrame(function() {
              requestAnimationFrame(function() {
                if (dialog.isConnected) send('ready');
              });
            });
          }

          function updatePresentation() {
            if (hasReportedDismissal) return;
            const surface = composerSurface();
            if (surface) {
              const dialog = surface.node;
              if (dismissalTimer) {
                clearTimeout(dismissalTimer);
                dismissalTimer = 0;
              }
              hasSeenComposer = true;
              if (surface.mode === 'dialog') hasSeenDialog = true;
              document.querySelectorAll('[data-mosaic-compose-dialog="true"]').forEach(function(node) {
                if (node !== dialog) delete node.dataset.mosaicComposeDialog;
              });
              dialog.dataset.mosaicComposeDialog = 'true';
              dialog.dataset.mosaicComposeMode = surface.mode;
              reportReadyAfterPaint(dialog);
              return;
            }

            document.querySelectorAll('[data-mosaic-compose-dialog="true"]').forEach(function(node) {
              delete node.dataset.mosaicComposeDialog;
              delete node.dataset.mosaicComposeMode;
            });
            if (!hasSeenComposer || hasReportedDismissal || dismissalTimer) return;
            dismissalTimer = setTimeout(function() {
              dismissalTimer = 0;
              if (composerSurface() || hasReportedDismissal) return;
              hasReportedDismissal = true;
              send('dismissed');
            }, 180);
          }

          updatePresentation();
          setTimeout(updatePresentation, 920);
          const observer = new MutationObserver(updatePresentation);
          observer.observe(document.documentElement, { childList: true, subtree: true });
          window.__mosaicComposerPresentationObserver = observer;
        })();
        """

        static let mediaCaptureScript = """
        (function() {
          if (window.__xflowMediaCaptureInstalled) return;
          window.__xflowMediaCaptureInstalled = true;

          function send(payload) {
            try {
              if (!payload || !payload.url) return;
              if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.xflowMediaRequest) return;
              window.webkit.messageHandlers.xflowMediaRequest.postMessage(payload);
            } catch (_) {}
          }

          function findPermalink(startNode) {
            const container = startNode && startNode.closest ? startNode.closest('article, div[data-testid="tweet"]') : null;
            if (!container) return '';
            const specific = container.querySelector('a[href*="/status/"][href*="/video/"], a[href*="/status/"][href*="/photo/"]');
            if (specific && specific.href) return specific.href;
            const generic = container.querySelector('a[href*="/status/"]');
            if (generic && generic.href) return generic.href;
            return '';
          }

          function buttonLabel(node) {
            if (!node) return '';
            const aria = node.getAttribute ? (node.getAttribute('aria-label') || '') : '';
            const title = node.getAttribute ? (node.getAttribute('title') || '') : '';
            const text = (node.textContent || '').trim();
            return (aria + ' ' + title + ' ' + text).toLowerCase();
          }

          function shouldOpenVideoPopupFromControl(node) {
            const label = buttonLabel(node);
            if (!label) return false;
            return /full\\s*screen|fullscreen/.test(label);
          }

          function pauseForPopup(video) {
            if (!video) return;
            try {
              video.pause();
            } catch (_) {}
          }

          function directVideoURL(video) {
            const explicitSources = [
              video && video.currentSrc,
              video && video.src,
              video && video.querySelector && video.querySelector('source') && video.querySelector('source').src
            ];
            for (const source of explicitSources) {
              if (isTrustedDirectVideoURL(source)) return source;
            }

            const resources = (performance.getEntriesByType('resource') || []).slice().reverse();
            for (const resource of resources) {
              const source = resource && resource.name;
              if (isTrustedDirectVideoURL(source)) {
                return source;
              }
            }
            return '';
          }

          function isTrustedDirectVideoURL(source) {
            try {
              const parsed = new URL(source || '');
              const path = (parsed.pathname || '').toLowerCase();
              return parsed.protocol === 'https:' && parsed.hostname === 'video.twimg.com' &&
                (path.endsWith('.mp4') || path.endsWith('.m3u8'));
            } catch (_) {
              return false;
            }
          }

          function openVideoPopup(videoContainer, videoNode) {
            const permalink = findPermalink(videoContainer) || window.location.href;
            const mediaURL = directVideoURL(videoNode);
            const timestamp = Number.isFinite(videoNode.currentTime) ? videoNode.currentTime : 0;
            pauseForPopup(videoNode);
            send({ kind: 'video', url: permalink, mediaURL: mediaURL, currentTime: timestamp });
          }

          function isPlaybackControlTarget(event) {
            if (event.target.closest('input[type="range"], progress')) return true;
            const controlButton = event.target.closest('button, [role="button"]');
            if (!controlButton) return false;
            const label = buttonLabel(controlButton);
            return /play|pause|mute|unmute|volume|settings|seek|scrub|speed|captions|subtitle|cc/.test(label);
          }

          // xFlow does not currently provide a reliable native PiP host. Disable only
          // WebKit's PiP capability and leave the standard video controls untouched.
          function disablePictureInPicture(root) {
            const scope = root && root.querySelectorAll ? root : document;
            scope.querySelectorAll('video').forEach(function(video) {
              try {
                video.disablePictureInPicture = true;
              } catch (_) {}
            });
          }

          function hidePictureInPictureControl() {
            if (document.getElementById('xflow-disable-pip-control')) return;
            const style = document.createElement('style');
            style.id = 'xflow-disable-pip-control';
            style.textContent = [
              'button[aria-label*="Picture-in-Picture" i]',
              '[role="button"][aria-label*="Picture-in-Picture" i]',
              'button[title*="Picture-in-Picture" i]',
              '[role="button"][title*="Picture-in-Picture" i]'
            ].join(',') + '{display:none !important;}';
            (document.head || document.documentElement).appendChild(style);
          }

          disablePictureInPicture(document);
          hidePictureInPictureControl();
          new MutationObserver(function(records) {
            if (window.__mosaicBackgroundSuspended) return;
            records.forEach(function(record) {
              record.addedNodes.forEach(function(node) {
                if (!node || node.nodeType !== Node.ELEMENT_NODE) return;
                if (node.tagName === 'VIDEO') {
                  try {
                    node.disablePictureInPicture = true;
                  } catch (_) {}
                }
                disablePictureInPicture(node);
              });
            });
          }).observe(document.documentElement, { childList: true, subtree: true });

          document.addEventListener('click', function(event) {
            const pathname = window.location.pathname || '';

            if (pathname.startsWith('/messages')) {
              const directVideo = event.target.closest('video');
              const messageContainer = event.target.closest('[data-testid*="message"], [data-testid*="cellInnerDiv"], [role="listitem"], article, li, div');
              const videoNode = directVideo || (messageContainer ? messageContainer.querySelector('video') : null);
              const messageControl = event.target.closest('button, [role="button"]');
              const strictControl = event.target.closest('input[type="range"], progress, [aria-label*="volume" i], [aria-label*="settings" i], [aria-label*="seek" i], [aria-label*="scrub" i], [aria-label*="captions" i], [aria-label*="subtitle" i]');
              if (videoNode && ((messageControl && isPlaybackControlTarget(event)) || strictControl)) {
                return;
              }
              if (videoNode && !strictControl) {
                if (messageControl && /picture\\s*in\\s*picture|picture-in-picture|\\bpip\\b/.test(buttonLabel(messageControl))) {
                  return;
                }
                const mediaURL = videoNode.currentSrc || videoNode.src || ((videoNode.querySelector && videoNode.querySelector('source')) ? (videoNode.querySelector('source').src || '') : '');
                const timestamp = Number.isFinite(videoNode.currentTime) ? videoNode.currentTime : 0;
                const permalink = window.location.href;

                pauseForPopup(videoNode);
                event.preventDefault();
                event.stopPropagation();
                send({ kind: 'video', url: permalink, mediaURL: mediaURL || permalink, currentTime: timestamp });
                return;
              }
            }

            const videoContainer = event.target.closest('[data-testid="videoPlayer"]');
            if (videoContainer) {
              const controlButton = event.target.closest('button, [role="button"]');
              if (controlButton && !shouldOpenVideoPopupFromControl(controlButton)) {
                return;
              }

              if (controlButton && shouldOpenVideoPopupFromControl(controlButton)) {
                const videoNode = videoContainer.querySelector('video');
                if (!videoNode) return;
                event.preventDefault();
                event.stopPropagation();
                openVideoPopup(videoContainer, videoNode);
              }
              return;
            }

            const imageContainer = event.target.closest('[data-testid="tweetPhoto"]');
            if (imageContainer) {
              const imageNode = imageContainer.querySelector('img');
              const mediaURL = imageNode ? (imageNode.currentSrc || imageNode.src) : '';
              if (!mediaURL) return;
              event.preventDefault();
              event.stopPropagation();
              send({ kind: 'image', url: mediaURL, mediaURL: mediaURL, currentTime: 0 });
              return;
            }

            const anchor = event.target.closest('a[href*="/photo/"], a[href*="/video/"]');
            if (anchor && anchor.href) {
              event.preventDefault();
              event.stopPropagation();
              send({ kind: 'link', url: anchor.href, currentTime: 0 });
            }
          }, true);
        })();
        """

        static let structuralColumnChromeScript = """
        (function() {
          if (window.__mosaicStructuralChromeInstalled) return;
          window.__mosaicStructuralChromeInstalled = true;

          const styleID = 'mosaic-column-structure-style';

          function ensureStyle() {
            if (document.getElementById(styleID)) return;
            const style = document.createElement('style');
            style.id = styleID;
            style.textContent = `
              [data-testid="sidebarColumn"] { display: none !important; }
              header[role="banner"] { display: none !important; }
              [data-testid="SideNav_NewTweet_Button"] { display: none !important; }
              [data-testid^="AppTabBar_"] { display: none !important; }
              nav[aria-label="Primary"] { display: none !important; }
              main[role="main"] {
                width: 100% !important;
                max-width: none !important;
              }
              [data-testid="primaryColumn"] {
                border-left: none !important;
                border-right: none !important;
                width: 100% !important;
                max-width: none !important;
              }
              [data-testid="primaryColumn"] section > div > div > div > div {
                border-left: none !important;
                border-right: none !important;
              }
            `;
            (document.head || document.documentElement).appendChild(style);
          }

          ensureStyle();
        })();
        """

        static let integratedColumnThemeScript = """
        (function() {
          const styleID = 'mosaic-integrated-column-style';
          let style = document.getElementById(styleID);
          if (!style) {
            style = document.createElement('style');
            style.id = styleID;
            (document.head || document.documentElement).appendChild(style);
          }

          style.textContent = `
            :root {
              --mosaic-accent: rgb(231, 216, 190);
              --mosaic-accent-ink: rgba(34, 28, 21, 0.96);
              --mosaic-accent-button: rgba(231, 216, 190, 0.94);
              --mosaic-accent-button-hover: rgba(240, 228, 207, 0.98);
              --mosaic-post-halo-core: rgba(231, 216, 190, 0.34);
              --mosaic-post-halo: rgba(231, 216, 190, 0.25);
              --mosaic-post-halo-core-hover: rgba(231, 216, 190, 0.46);
              --mosaic-post-halo-hover: rgba(231, 216, 190, 0.34);
              --mosaic-outline-button-ink: rgba(255, 255, 255, 0.98);
              --mosaic-accent-soft: rgba(231, 216, 190, 0.16);
              --mosaic-accent-line: rgba(231, 216, 190, 0.34);
              --mosaic-ink: rgba(242, 245, 249, 0.94);
              --mosaic-secondary: rgba(222, 229, 238, 0.58);
              --mosaic-surface: rgba(18, 24, 33, 0.1);
              --mosaic-surface-hover: rgba(202, 220, 235, 0.085);
              --mosaic-inset: rgba(3, 8, 15, 0.2);
              --mosaic-tab-surface: rgba(61, 61, 58, 0.94);
              --mosaic-composer-surface: rgba(231, 216, 190, 0.11);
              --mosaic-composer-focus: rgba(231, 216, 190, 0.15);
              --mosaic-composer-edge: rgba(231, 216, 190, 0.043);
              --mosaic-composer-hover: rgba(231, 216, 190, 0.11);
              --mosaic-float-surface: rgba(22, 29, 39, 0.76);
              --mosaic-transient-surface: rgba(63, 62, 57, 0.72);
              --mosaic-transient-hover: rgba(76, 73, 65, 0.78);
              --mosaic-transient-border: rgba(231, 216, 190, 0.28);
              --mosaic-transient-shadow: rgba(0, 0, 0, 0.3);
              --mosaic-media-surface: rgba(3, 8, 15, 0.18);
              --mosaic-video-control-surface: rgba(7, 10, 15, 0.78);
              --mosaic-video-control-hover: rgba(7, 10, 15, 0.9);
              --mosaic-video-control-border: rgba(255, 255, 255, 0.22);
              --mosaic-video-control-track: rgba(255, 255, 255, 0.48);
              --mosaic-post-label-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 80 36'%3E%3Ctext x='40' y='19' text-anchor='middle' dominant-baseline='middle' fill='%23ffffff' font-family='-apple-system,BlinkMacSystemFont,sans-serif' font-size='15' font-weight='700'%3EPost%3C/text%3E%3C/svg%3E");
              --mosaic-reply-label-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 80 36'%3E%3Ctext x='40' y='19' text-anchor='middle' dominant-baseline='middle' fill='%23ffffff' font-family='-apple-system,BlinkMacSystemFont,sans-serif' font-size='15' font-weight='700'%3EReply%3C/text%3E%3C/svg%3E");
              --mosaic-thread-line: rgba(231, 216, 190, 0.42);
              --mosaic-thread-halo: rgba(231, 216, 190, 0.12);
              --mosaic-hairline: rgba(226, 238, 249, 0.09);
              --mosaic-shadow: rgba(0, 0, 0, 0.2);
              color-scheme: dark;
            }

            html,
            body,
            #react-root,
            [data-testid="react-root"],
            main[role="main"],
            [data-testid="primaryColumn"],
            [data-testid="primaryColumn"] > div,
            [data-testid="primaryColumn"] > div > div {
              background-color: transparent !important;
              background-image: none !important;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
            }

            [data-testid="primaryColumn"] {
              color: var(--mosaic-ink) !important;
              background: transparent !important;
              backdrop-filter: none !important;
              box-shadow: none !important;
            }

            [data-testid="primaryColumn"] *,
            [data-testid="primaryColumn"] *::before,
            [data-testid="primaryColumn"] *::after {
              background-color: transparent !important;
            }

            [data-testid="primaryColumn"] [data-testid="cellInnerDiv"] {
              border-color: transparent !important;
              background: transparent !important;
              box-shadow: inset 0 -1px 0 var(--mosaic-hairline) !important;
            }

            [data-testid="primaryColumn"] [data-testid="cellInnerDiv"]:hover {
              background: transparent !important;
              filter: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-thread-connector="true"] {
              width: 2px !important;
              min-width: 2px !important;
              max-width: 2px !important;
              background: linear-gradient(to bottom, transparent 0%, var(--mosaic-thread-line) 12%, var(--mosaic-thread-line) 88%, transparent 100%) !important;
              border-radius: 999px !important;
              box-shadow: 0 0 8px var(--mosaic-thread-halo) !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] article,
            [data-testid="primaryColumn"] [data-testid="tweet"] {
              background: transparent !important;
            }

            [data-testid="primaryColumn"] [role="separator"] {
              background-color: var(--mosaic-hairline) !important;
              opacity: 0.24 !important;
            }

            [data-testid="primaryColumn"] a,
            [data-testid="primaryColumn"] [data-testid="tweetText"] a {
              text-decoration-thickness: 1px !important;
              text-underline-offset: 2px !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetText"] a,
            [data-testid="primaryColumn"] a[href*="/hashtag/"],
            [data-testid="primaryColumn"] a[href*="/search?q="] {
              color: var(--mosaic-accent) !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-reply-context="true"] a,
            [data-testid="primaryColumn"] [data-mosaic-reply-context="true"] a:visited {
              color: var(--mosaic-accent) !important;
              text-decoration-color: var(--mosaic-accent-line) !important;
            }

            [data-testid="primaryColumn"] [data-testid="User-Name"] {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Rounded", "SF Pro Text", sans-serif !important;
              letter-spacing: -0.01em !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetText"] {
              line-height: 1.38 !important;
              letter-spacing: -0.006em !important;
            }

            [data-testid="primaryColumn"] button,
            [data-testid="primaryColumn"] [role="button"] {
              -webkit-font-smoothing: antialiased !important;
              transition: background-color 120ms ease-out, box-shadow 120ms ease-out, filter 120ms ease-out, transform 120ms ease-out !important;
            }

            [data-testid="primaryColumn"] button:hover,
            [data-testid="primaryColumn"] [role="button"]:hover {
              filter: brightness(1.09);
            }

            [data-testid="primaryColumn"] [data-testid="tweetButton"],
            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"] {
              color: var(--mosaic-ink) !important;
              background: var(--mosaic-accent-soft) !important;
              border: 1px solid var(--mosaic-accent-line) !important;
              box-shadow: 0 5px 18px var(--mosaic-shadow) !important;
              backdrop-filter: blur(16px) saturate(1.2) !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetButton"]:hover,
            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:hover {
              background: rgba(231, 216, 190, 0.24) !important;
              transform: translateY(-1px) !important;
            }

            [data-testid="primaryColumn"] input,
            [data-testid="primaryColumn"] textarea,
            [data-testid="primaryColumn"] [role="textbox"]:not([data-testid="tweetTextarea_0"]) {
              border-radius: 12px !important;
              background-color: var(--mosaic-inset) !important;
              box-shadow: inset 0 0 0 1px var(--mosaic-hairline), 0 4px 14px rgba(0, 0, 0, 0.08) !important;
              backdrop-filter: blur(16px) saturate(1.14) !important;
            }

            [data-testid="primaryColumn"] input:focus,
            [data-testid="primaryColumn"] textarea:focus,
            [data-testid="primaryColumn"] [role="textbox"]:not([data-testid="tweetTextarea_0"]):focus {
              box-shadow: inset 0 0 0 1px var(--mosaic-accent-line), 0 0 0 3px var(--mosaic-accent-soft) !important;
            }

            /* X already renders search as one pill containing its icon and input.
               Do not turn the inner input into a second inset control. */
            [data-testid="primaryColumn"] form[role="search"] input,
            [data-testid="primaryColumn"] [role="search"] input,
            [data-testid="primaryColumn"] input[data-testid="SearchBox_Search_Input"],
            [data-testid="primaryColumn"] input[data-testid="SearchBox_Search_Input"]:focus,
            [data-testid="primaryColumn"] input[data-testid="SearchBox_Search_Input"]:focus-visible {
              border: 0 !important;
              border-radius: 0 !important;
              background: transparent !important;
              box-shadow: none !important;
              -webkit-backdrop-filter: none !important;
              backdrop-filter: none !important;
              outline: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-shell="true"] {
              isolation: isolate !important;
              z-index: 30 !important;
              border-radius: 0 0 14px 14px !important;
              overflow: hidden !important;
              opacity: 1 !important;
              transform: translate3d(0, 0, 0) !important;
              transition:
                opacity 240ms ease-out,
                transform 420ms cubic-bezier(0.22, 0.8, 0.25, 1) !important;
              background-color: transparent !important;
              background-image: none !important;
              box-shadow: none !important;
              -webkit-backdrop-filter: none !important;
              backdrop-filter: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-shell="true"][data-mosaic-needs-positioning="true"] {
              position: relative !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-shell="true"][data-mosaic-column-menu-visible="false"] {
              opacity: 0 !important;
              transform: translate3d(0, calc(-100% - 8px), 0) !important;
              /* Stay solid through the first part of travel, then fade away. */
              transition:
                opacity 180ms ease-out 100ms,
                transform 320ms cubic-bezier(0.4, 0, 0.6, 1) !important;
              pointer-events: none !important;
            }

            /* Keep the optical material on a stable compositing plane beneath
               the tab controls. The dense tint prevents independently promoted
               X text from remaining legible if WebKit skips its backdrop pass. */
            [data-testid="primaryColumn"] [data-mosaic-top-tab-shell="true"]::before {
              content: "" !important;
              position: absolute !important;
              inset: 0 !important;
              z-index: 0 !important;
              pointer-events: none !important;
              border-radius: 0 0 14px 14px !important;
              background-color: var(--mosaic-tab-surface) !important;
              box-shadow: inset 0 -1px 0 rgba(231, 216, 190, 0.12), 0 8px 20px var(--mosaic-shadow) !important;
              -webkit-backdrop-filter: blur(64px) saturate(0.78) contrast(0.92) brightness(1.02) !important;
              backdrop-filter: blur(64px) saturate(0.78) contrast(0.92) brightness(1.02) !important;
              opacity: 0 !important;
              transition: opacity 240ms ease-out !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-shell="true"][data-mosaic-column-scrolled="true"]::before {
              opacity: 1 !important;
            }

            /* Preserve X's positioned header children and their spacer geometry.
               Forcing relative positioning can put an absolute header back in
               flow and reserve its height twice above the inline composer. */
            [data-testid="primaryColumn"] [data-mosaic-top-tab-shell="true"] > * {
              z-index: 1 !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-rail="true"] {
              min-width: 0 !important;
              overflow-x: auto !important;
              overflow-y: hidden !important;
              overscroll-behavior-x: contain !important;
              scrollbar-width: none !important;
              touch-action: pan-x !important;
              scroll-behavior: auto !important;
              scroll-snap-type: none !important;
              background: transparent !important;
              box-shadow: none !important;
              -webkit-backdrop-filter: none !important;
              backdrop-filter: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-rail="true"]::-webkit-scrollbar {
              display: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-rail="true"] > [role="tab"],
            [data-testid="primaryColumn"] [data-mosaic-top-tab-rail="true"] [role="tab"] {
              flex: 0 0 auto !important;
              scroll-snap-align: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-rail="true"][data-mosaic-overflow-left="false"][data-mosaic-overflow-right="true"] {
              -webkit-mask-image: linear-gradient(to right, black 0, black calc(100% - 34px), transparent 100%);
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-rail="true"][data-mosaic-overflow-left="true"][data-mosaic-overflow-right="false"] {
              -webkit-mask-image: linear-gradient(to right, transparent 0, black 34px, black 100%);
            }

            [data-testid="primaryColumn"] [data-mosaic-top-tab-rail="true"][data-mosaic-overflow-left="true"][data-mosaic-overflow-right="true"] {
              -webkit-mask-image: linear-gradient(to right, transparent 0, black 34px, black calc(100% - 34px), transparent 100%);
            }

            /* X exposes the inline composer as generic textbox and tablist roles.
               Keep it visually distinct from search fields and navigation tabs. */
            [data-testid="primaryColumn"] [data-mosaic-composer="true"] {
              position: relative !important;
              isolation: isolate !important;
              overflow: visible !important;
              background: transparent !important;
              box-shadow: none !important;
              backdrop-filter: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-composer="true"]::before {
              content: "" !important;
              position: absolute !important;
              inset: 14px 10px !important;
              z-index: -1 !important;
              pointer-events: none !important;
              border-radius: 40px !important;
              background: radial-gradient(ellipse at 46% 48%, var(--mosaic-composer-surface) 0%, var(--mosaic-composer-edge) 50%, transparent 78%) !important;
              filter: blur(16px) !important;
              backdrop-filter: blur(12px) saturate(1.08) !important;
              transition: background 180ms ease-out, filter 180ms ease-out, backdrop-filter 180ms ease-out !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-composer="true"]:focus-within::before {
              background: radial-gradient(ellipse at 46% 48%, var(--mosaic-composer-focus) 0%, var(--mosaic-composer-edge) 54%, transparent 80%) !important;
              filter: blur(18px) !important;
              backdrop-filter: blur(16px) saturate(1.14) !important;
            }

            /* X composites disabled controls as a dimmed layer, including their
               immediate wrappers. Render the visible label on the composer's own
               plane while retaining X's untouched button for input and accessibility. */
            [data-testid="primaryColumn"] [data-mosaic-composer="true"]::after {
              content: "" !important;
              position: absolute !important;
              left: var(--mosaic-post-label-left, 0px) !important;
              top: var(--mosaic-post-label-top, 0px) !important;
              width: var(--mosaic-post-label-width, 0px) !important;
              height: var(--mosaic-post-label-height, 0px) !important;
              z-index: 5 !important;
              pointer-events: none !important;
              background-image: var(--mosaic-composer-label-image, var(--mosaic-post-label-image)) !important;
              background-position: center !important;
              background-repeat: no-repeat !important;
              background-size: 100% 100% !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-composer="true"] a[href] img {
              box-shadow: 0 0 0 2px var(--mosaic-accent-soft), 0 7px 20px var(--mosaic-shadow) !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetTextarea_0"],
            [data-testid="primaryColumn"] [data-testid="tweetTextarea_0"]:focus {
              color: var(--mosaic-ink) !important;
              background: transparent !important;
              border: 0 !important;
              border-radius: 0 !important;
              box-shadow: none !important;
              backdrop-filter: none !important;
              outline: none !important;
              caret-color: var(--mosaic-accent) !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetTextarea_0"] [data-text="true"] {
              color: var(--mosaic-ink) !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetTextarea_0"] ~ div[aria-hidden="true"],
            [data-testid="primaryColumn"] [data-testid="tweetTextarea_0"] div[aria-hidden="true"] {
              color: var(--mosaic-secondary) !important;
            }

            [data-testid="primaryColumn"] [data-testid="toolBar"],
            [data-testid="primaryColumn"] [data-testid="toolBar"] [role="tablist"],
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="toolBar"]),
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="fileInput"]),
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="gifSearchButton"]) {
              background: transparent !important;
              border: 0 !important;
              border-radius: 0 !important;
              box-shadow: none !important;
              backdrop-filter: none !important;
            }

            [data-testid="primaryColumn"] [data-testid="toolBar"] button,
            [data-testid="primaryColumn"] [data-testid="toolBar"] [role="button"],
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="fileInput"]) button,
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="fileInput"]) [role="button"] {
              color: var(--mosaic-secondary) !important;
              border-radius: 999px !important;
              box-shadow: none !important;
            }

            [data-testid="primaryColumn"] [data-testid="toolBar"] button:hover,
            [data-testid="primaryColumn"] [data-testid="toolBar"] [role="button"]:hover,
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="fileInput"]) button:hover,
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="fileInput"]) [role="button"]:hover {
              color: var(--mosaic-accent) !important;
              background: var(--mosaic-composer-hover) !important;
              filter: none !important;
              transform: none !important;
            }

            [data-testid="primaryColumn"] [data-testid="toolBar"] button:disabled:not([data-testid="tweetButtonInline"]),
            [data-testid="primaryColumn"] [data-testid="toolBar"] [aria-disabled="true"]:not([data-testid="tweetButtonInline"]),
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="fileInput"]) button:disabled:not([data-testid="tweetButtonInline"]),
            [data-testid="primaryColumn"] [role="tablist"]:has([data-testid="fileInput"]) [aria-disabled="true"]:not([data-testid="tweetButtonInline"]) {
              opacity: 0.3 !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:disabled,
            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"][aria-disabled="true"] {
              color: rgb(255, 255, 255) !important;
              -webkit-text-fill-color: rgb(255, 255, 255) !important;
              background: rgb(231, 216, 190) !important;
              border: 1.5px solid rgba(231, 216, 190, 0.96) !important;
              outline: none !important;
              box-shadow: 0 0 5px var(--mosaic-post-halo-core), 0 0 18px var(--mosaic-post-halo), 0 6px 18px var(--mosaic-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.2) !important;
              text-shadow: none !important;
              font-weight: 700 !important;
              filter: none !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:disabled:hover,
            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"][aria-disabled="true"]:hover {
              background: var(--mosaic-accent-soft) !important;
              box-shadow: 0 0 6px var(--mosaic-post-halo-core-hover), 0 0 22px var(--mosaic-post-halo-hover), 0 7px 20px var(--mosaic-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.24) !important;
              filter: none !important;
              transform: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-synthetic-label="true"]:disabled *,
            [data-testid="primaryColumn"] [data-mosaic-synthetic-label="true"][aria-disabled="true"] * {
              color: rgb(255, 255, 255) !important;
              -webkit-text-fill-color: rgb(255, 255, 255) !important;
              text-shadow: none !important;
              font-weight: 700 !important;
              filter: none !important;
              opacity: 0 !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-synthetic-label="true"] > * {
              opacity: 0 !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:not([data-mosaic-synthetic-label="true"]) > * {
              color: inherit !important;
              -webkit-text-fill-color: inherit !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:not(:disabled):not([aria-disabled="true"]),
            [data-testid="primaryColumn"] :is(button, [role="button"]):is([data-testid$="-follow"], [data-testid$="-unfollow"]):not(:disabled):not([aria-disabled="true"]) {
              color: rgba(255, 255, 255, 0.98) !important;
              background-color: var(--mosaic-accent-button) !important;
              border: 1.5px solid rgba(231, 216, 190, 0.96) !important;
              box-shadow: 0 0 5px var(--mosaic-post-halo-core), 0 0 18px var(--mosaic-post-halo), 0 7px 20px var(--mosaic-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.22) !important;
              text-shadow: none !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:not(:disabled):not([aria-disabled="true"]) *,
            [data-testid="primaryColumn"] :is(button, [role="button"]):is([data-testid$="-follow"], [data-testid$="-unfollow"]):not(:disabled):not([aria-disabled="true"]) * {
              color: rgba(255, 255, 255, 0.98) !important;
              -webkit-text-fill-color: rgba(255, 255, 255, 0.98) !important;
              text-shadow: none !important;
            }

            [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:not(:disabled):not([aria-disabled="true"]):hover,
            [data-testid="primaryColumn"] :is(button, [role="button"]):is([data-testid$="-follow"], [data-testid$="-unfollow"]):not(:disabled):not([aria-disabled="true"]):hover {
              color: rgba(255, 255, 255, 0.98) !important;
              background-color: var(--mosaic-accent-button-hover) !important;
              box-shadow: 0 0 6px var(--mosaic-post-halo-core-hover), 0 0 22px var(--mosaic-post-halo-hover), 0 8px 22px var(--mosaic-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.25) !important;
              transform: translateY(-1px) !important;
            }

            /* Follow IDs change to -unfollow after following; retain X's own
               text, confirmation flow, and disabled state throughout. */
            [data-testid="primaryColumn"] :is(button, [role="button"]):is([data-testid$="-follow"], [data-testid$="-unfollow"]) {
              border-radius: 999px !important;
              font-weight: 700 !important;
            }

            [data-testid="primaryColumn"] :is(button, [role="button"]):is([data-testid$="-follow"], [data-testid$="-unfollow"]):disabled,
            [data-testid="primaryColumn"] :is(button, [role="button"]):is([data-testid$="-follow"], [data-testid$="-unfollow"])[aria-disabled="true"] {
              color: var(--mosaic-outline-button-ink) !important;
              background: var(--mosaic-accent-soft) !important;
              border: 1.5px solid var(--mosaic-accent-line) !important;
              opacity: 0.5 !important;
            }

            [data-testid="primaryColumn"] :is(button, [role="button"]):is([data-testid$="-follow"], [data-testid$="-unfollow"]):focus-visible {
              outline: 2px solid var(--mosaic-accent-line) !important;
              outline-offset: 3px !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-subscribe-button="true"] {
              color: var(--mosaic-outline-button-ink) !important;
              -webkit-text-fill-color: var(--mosaic-outline-button-ink) !important;
              background: var(--mosaic-accent-soft) !important;
              border: 1.5px solid rgba(231, 216, 190, 0.96) !important;
              border-radius: 999px !important;
              box-shadow: 0 0 6px var(--mosaic-post-halo-core-hover), 0 0 22px var(--mosaic-post-halo-hover), 0 7px 20px var(--mosaic-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.16) !important;
              text-shadow: none !important;
              filter: none !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-subscribe-button="true"] *,
            [data-testid="primaryColumn"] [data-mosaic-subscribe-button="true"]:hover * {
              color: var(--mosaic-outline-button-ink) !important;
              -webkit-text-fill-color: var(--mosaic-outline-button-ink) !important;
              background: transparent !important;
              text-shadow: none !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-subscribe-button="true"]:hover {
              background: rgba(231, 216, 190, 0.22) !important;
              box-shadow: 0 0 7px var(--mosaic-post-halo-core-hover), 0 0 25px var(--mosaic-post-halo-hover), 0 8px 22px var(--mosaic-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.2) !important;
              transform: translateY(-1px) !important;
            }

            [data-testid="primaryColumn"] [role="tab"][aria-selected="true"] {
              position: relative !important;
              font-weight: 700 !important;
              color: var(--mosaic-accent) !important;
            }

            [data-testid="primaryColumn"] [role="tab"][aria-selected="true"]::after {
              content: "";
              position: absolute;
              left: 28%;
              right: 28%;
              bottom: 2px;
              height: 3px;
              border-radius: 999px;
              background: var(--mosaic-accent);
              box-shadow: 0 0 10px var(--mosaic-accent-soft);
              pointer-events: none;
            }

            [data-testid="primaryColumn"] article [role="group"] button,
            [data-testid="primaryColumn"] article [role="group"] [role="button"] {
              border-radius: 999px !important;
            }

            [data-testid="primaryColumn"] article [role="group"] button:hover,
            [data-testid="primaryColumn"] article [role="group"] [role="button"]:hover {
              background-color: var(--mosaic-surface-hover) !important;
              box-shadow: 0 5px 14px rgba(0, 0, 0, 0.08) !important;
              transform: none !important;
            }

            /* X applies small translate/scale changes to the post-header action
               glyphs on hover. Keep this pair optically fixed while allowing
               the hover color to respond. */
            [data-testid="primaryColumn"] button[aria-label*="Grok" i],
            [data-testid="primaryColumn"] [role="button"][aria-label*="Grok" i],
            [data-testid="primaryColumn"] [data-testid="caret"] {
              flex: 0 0 auto !important;
              transform: none !important;
              translate: none !important;
              scale: 1 !important;
              will-change: auto !important;
              transition: color 120ms ease-out, background-color 120ms ease-out, filter 120ms ease-out !important;
            }

            [data-testid="primaryColumn"] button[aria-label*="Grok" i] *,
            [data-testid="primaryColumn"] [role="button"][aria-label*="Grok" i] *,
            [data-testid="primaryColumn"] [data-testid="caret"] * {
              transform: none !important;
              translate: none !important;
              scale: 1 !important;
            }

            [data-testid="primaryColumn"] [data-testid="card.wrapper"],
            [data-testid="primaryColumn"] [data-testid="tweetPhoto"],
            [data-testid="primaryColumn"] video {
              border-radius: 14px !important;
              background-color: var(--mosaic-media-surface) !important;
              box-shadow: inset 0 0 0 1px var(--mosaic-hairline), 0 8px 24px rgba(0, 0, 0, 0.1) !important;
            }

            [data-testid="primaryColumn"] [data-testid="card.wrapper"] {
              border-color: transparent !important;
              overflow: hidden !important;
            }

            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-button="true"] {
              color: rgba(255, 255, 255, 0.98) !important;
              background-color: var(--mosaic-video-control-surface) !important;
              border: 1px solid var(--mosaic-video-control-border) !important;
              border-radius: 999px !important;
              box-shadow: 0 4px 14px rgba(0, 0, 0, 0.34), inset 0 1px 0 rgba(255, 255, 255, 0.14) !important;
              -webkit-backdrop-filter: blur(14px) saturate(1.18) !important;
              backdrop-filter: blur(14px) saturate(1.18) !important;
              filter: none !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-button="true"]:hover {
              background-color: var(--mosaic-video-control-hover) !important;
              filter: none !important;
            }

            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-button="true"] *,
            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-button="true"] svg,
            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-button="true"] path {
              color: rgba(255, 255, 255, 0.98) !important;
              fill: currentColor !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-popover="true"] {
              background-color: var(--mosaic-video-control-surface) !important;
              border: 1px solid var(--mosaic-video-control-border) !important;
              border-radius: 999px !important;
              box-shadow: 0 5px 16px rgba(0, 0, 0, 0.34), inset 0 1px 0 rgba(255, 255, 255, 0.12) !important;
              -webkit-backdrop-filter: blur(12px) saturate(1.16) !important;
              backdrop-filter: blur(12px) saturate(1.16) !important;
              transform: scale(0.68) !important;
              transform-origin: 50% 100% !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-slider="true"] {
              color: rgba(255, 255, 255, 0.98) !important;
              accent-color: rgba(255, 255, 255, 0.98) !important;
              background-color: var(--mosaic-video-control-track) !important;
              border-radius: 999px !important;
              box-shadow: 0 1px 4px rgba(0, 0, 0, 0.42) !important;
              filter: none !important;
              opacity: 1 !important;
            }

            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-slider="true"]::-webkit-slider-runnable-track {
              height: 3px !important;
              background: var(--mosaic-video-control-track) !important;
              border-radius: 999px !important;
            }

            [data-testid="primaryColumn"] [data-testid="videoPlayer"] [data-mosaic-volume-slider="true"]::-webkit-slider-thumb {
              -webkit-appearance: none !important;
              width: 10px !important;
              height: 10px !important;
              margin-top: -3.5px !important;
              background: rgba(255, 255, 255, 0.98) !important;
              border: 1px solid rgba(0, 0, 0, 0.2) !important;
              border-radius: 999px !important;
              box-shadow: 0 1px 4px rgba(0, 0, 0, 0.36) !important;
            }

            [role="menu"],
            [data-testid="Dropdown"],
            [data-testid="HoverCard"] {
              background: var(--mosaic-float-surface) !important;
              border: 1px solid var(--mosaic-hairline) !important;
              border-radius: 15px !important;
              box-shadow: 0 18px 48px var(--mosaic-shadow) !important;
              backdrop-filter: blur(28px) saturate(1.24) !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-post-indicator="true"] {
              color: var(--mosaic-ink) !important;
              background: var(--mosaic-transient-surface) !important;
              border: 1px solid var(--mosaic-transient-border) !important;
              border-radius: 999px !important;
              box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.1), 0 10px 28px var(--mosaic-transient-shadow) !important;
              -webkit-backdrop-filter: blur(30px) saturate(1.22) !important;
              backdrop-filter: blur(30px) saturate(1.22) !important;
              overflow: hidden !important;
              filter: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-post-indicator="true"]:hover {
              background: var(--mosaic-transient-hover) !important;
              border-color: var(--mosaic-accent-line) !important;
              filter: none !important;
            }

            [data-testid="primaryColumn"] [data-mosaic-post-indicator="true"] * {
              background-color: transparent !important;
            }

            [data-testid="primaryColumn"] a:focus-visible,
            [data-testid="primaryColumn"] button:focus-visible,
            [data-testid="primaryColumn"] [role="button"]:focus-visible,
            [data-testid="primaryColumn"] input:focus-visible,
            [data-testid="primaryColumn"] textarea:focus-visible {
              outline: 2px solid var(--mosaic-accent-line) !important;
              outline-offset: 2px !important;
            }

            ::selection {
              background: rgba(231, 216, 190, 0.3) !important;
            }

            ::-webkit-scrollbar { width: 10px; height: 10px; }
            ::-webkit-scrollbar-track { background: transparent; }
            ::-webkit-scrollbar-thumb {
              background: rgba(210, 225, 238, 0.16);
              border: 3px solid transparent;
              border-radius: 999px;
              background-clip: padding-box;
            }
            ::-webkit-scrollbar-thumb:hover {
              background: rgba(231, 216, 190, 0.42);
              border: 3px solid transparent;
              background-clip: padding-box;
            }

            @media (prefers-color-scheme: light) {
              :root {
                --mosaic-accent: rgb(113, 94, 65);
                --mosaic-accent-ink: rgba(255, 252, 247, 0.96);
                --mosaic-post-halo-core: rgba(190, 139, 67, 0.28);
                --mosaic-post-halo: rgba(207, 162, 91, 0.20);
                --mosaic-post-halo-core-hover: rgba(190, 139, 67, 0.38);
                --mosaic-post-halo-hover: rgba(207, 162, 91, 0.28);
                --mosaic-accent-button: rgba(113, 94, 65, 0.92);
                --mosaic-accent-button-hover: rgba(96, 78, 54, 0.98);
                --mosaic-accent-soft: rgba(113, 94, 65, 0.12);
                --mosaic-accent-line: rgba(113, 94, 65, 0.28);
                --mosaic-outline-button-ink: rgba(58, 46, 32, 0.94);
                --mosaic-ink: rgba(18, 24, 31, 0.9);
                --mosaic-secondary: rgba(30, 40, 52, 0.56);
                --mosaic-surface: rgba(244, 249, 252, 0.08);
                --mosaic-surface-hover: rgba(255, 255, 252, 0.34);
                --mosaic-inset: rgba(117, 148, 170, 0.11);
                --mosaic-tab-surface: rgba(247, 248, 246, 0.94);
                --mosaic-composer-surface: rgba(113, 94, 65, 0.028);
                --mosaic-composer-focus: rgba(113, 94, 65, 0.043);
                --mosaic-composer-edge: rgba(113, 94, 65, 0.01);
                --mosaic-composer-hover: rgba(113, 94, 65, 0.09);
                --mosaic-float-surface: rgba(244, 249, 251, 0.78);
                --mosaic-transient-surface: rgba(250, 250, 247, 0.78);
                --mosaic-transient-hover: rgba(255, 255, 252, 0.88);
                --mosaic-transient-border: rgba(113, 94, 65, 0.2);
                --mosaic-transient-shadow: rgba(31, 53, 67, 0.18);
                --mosaic-media-surface: rgba(226, 237, 244, 0.14);
                --mosaic-thread-line: rgba(113, 94, 65, 0.34);
                --mosaic-thread-halo: rgba(113, 94, 65, 0.1);
                --mosaic-hairline: rgba(35, 67, 88, 0.085);
                --mosaic-shadow: rgba(31, 53, 67, 0.12);
                color-scheme: light;
              }

              [data-testid="primaryColumn"] [data-testid="tweetButton"]:hover,
              [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:hover {
                background: rgba(113, 94, 65, 0.18) !important;
              }

              [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:disabled,
              [data-testid="primaryColumn"] [data-testid="tweetButtonInline"][aria-disabled="true"] {
                color: rgb(255, 255, 255) !important;
                -webkit-text-fill-color: rgb(255, 255, 255) !important;
                background-color: rgba(113, 94, 65, 0.24) !important;
                border-color: rgba(113, 94, 65, 0.92) !important;
              }

              [data-testid="primaryColumn"] [data-testid="tweetButtonInline"]:disabled *,
              [data-testid="primaryColumn"] [data-testid="tweetButtonInline"][aria-disabled="true"] * {
                color: rgb(255, 255, 255) !important;
                -webkit-text-fill-color: rgb(255, 255, 255) !important;
              }
            }

            @media (prefers-reduced-transparency: reduce) {
              :root {
                --mosaic-surface: rgba(24, 30, 40, 0.94);
                --mosaic-surface-hover: rgba(43, 52, 64, 0.96);
                --mosaic-inset: rgba(8, 13, 20, 0.94);
                --mosaic-tab-surface: rgba(27, 34, 44, 0.97);
                --mosaic-float-surface: rgba(27, 34, 44, 0.98);
                --mosaic-transient-surface: rgba(43, 46, 45, 0.98);
                --mosaic-transient-hover: rgba(52, 54, 51, 0.99);
              }

              [data-testid="primaryColumn"],
              [data-testid="primaryColumn"] [data-mosaic-top-tab-shell="true"]::before,
              [data-testid="primaryColumn"] [data-mosaic-post-indicator="true"],
              [data-testid="primaryColumn"] [data-mosaic-composer="true"]::before,
              [role="menu"],
              [data-testid="Dropdown"],
              [data-testid="HoverCard"] {
                backdrop-filter: none !important;
              }
            }

            @media (prefers-reduced-motion: reduce) {
              [data-testid="primaryColumn"] * { transition-duration: 0.001ms !important; transition-delay: 0ms !important; }
            }
          `;

          function markInlineComposers() {
            if (typeof document.querySelectorAll !== 'function') return;
            document.querySelectorAll('[data-mosaic-synthetic-label="true"]').forEach(button => {
              delete button.dataset.mosaicSyntheticLabel;
            });
            document.querySelectorAll('[data-mosaic-composer="true"]').forEach(composer => {
              delete composer.dataset.mosaicComposer;
              composer.style.removeProperty('--mosaic-post-label-left');
              composer.style.removeProperty('--mosaic-post-label-top');
              composer.style.removeProperty('--mosaic-post-label-width');
              composer.style.removeProperty('--mosaic-post-label-height');
              composer.style.removeProperty('--mosaic-composer-label-image');
            });
            document.querySelectorAll('[data-testid="tweetTextarea_0"]').forEach(editor => {
              const primaryColumn = editor.closest('[data-testid="primaryColumn"]');
              let candidate = editor.parentElement;
              while (candidate && candidate !== primaryColumn) {
                const hasPostButton = candidate.querySelector('[data-testid="tweetButtonInline"]');
                const hasMediaControls = candidate.querySelector('[data-testid="fileInput"], [data-testid="gifSearchButton"]');
                if (hasPostButton && hasMediaControls) {
                  let composer = candidate;
                  let ancestor = candidate.parentElement;
                  for (let level = 0; ancestor && ancestor !== primaryColumn && level < 4; level += 1) {
                    if (ancestor.querySelector('a[href] img')) {
                      composer = ancestor;
                      break;
                    }
                    ancestor = ancestor.parentElement;
                  }
                  composer.dataset.mosaicComposer = 'true';
                  const actionLabel = [
                    hasPostButton.getAttribute('aria-label') || '',
                    hasPostButton.innerText || hasPostButton.textContent || ''
                  ].join(' ').trim();
                  const isReplyAction = /(^|\\s)reply(\\s|$)/i.test(actionLabel);
                  hasPostButton.dataset.mosaicSyntheticLabel = 'true';
                  composer.style.setProperty(
                    '--mosaic-composer-label-image',
                    isReplyAction ? 'var(--mosaic-reply-label-image)' : 'var(--mosaic-post-label-image)'
                  );
                  const composerRect = composer.getBoundingClientRect();
                  const buttonRect = hasPostButton.getBoundingClientRect();
                  composer.style.setProperty('--mosaic-post-label-left', `${buttonRect.left - composerRect.left}px`);
                  composer.style.setProperty('--mosaic-post-label-top', `${buttonRect.top - composerRect.top}px`);
                  composer.style.setProperty('--mosaic-post-label-width', `${buttonRect.width}px`);
                  composer.style.setProperty('--mosaic-post-label-height', `${buttonRect.height}px`);
                  break;
                }
                candidate = candidate.parentElement;
              }
            });
          }

          function isTopNavigationTabList(tabList) {
            if (!tabList || !tabList.closest || !tabList.querySelectorAll) return false;
            if (!tabList.closest('[data-testid="primaryColumn"]')) return false;
            if (tabList.closest('article, [data-testid="cellInnerDiv"], [data-testid="tweet"], [data-testid="toolBar"], [data-mosaic-composer="true"]')) return false;
            if (tabList.querySelectorAll('[role="tab"]').length < 2) return false;
            if (tabList.querySelector('[data-testid="fileInput"], [data-testid="gifSearchButton"]')) return false;
            return true;
          }

          function updateTopTabOverflow(tabList) {
            if (!tabList || !tabList.dataset) return false;
            const maxScroll = Math.max(0, tabList.scrollWidth - tabList.clientWidth);
            tabList.dataset.mosaicOverflowLeft = tabList.scrollLeft > 2 ? 'true' : 'false';
            tabList.dataset.mosaicOverflowRight = tabList.scrollLeft < maxScroll - 2 ? 'true' : 'false';
            return maxScroll > 2;
          }

          function findTopTabShell(tabList) {
            const primaryColumn = tabList.closest('[data-testid="primaryColumn"]');
            if (!primaryColumn || !tabList.getBoundingClientRect) return tabList.parentElement || tabList;
            const tabRect = tabList.getBoundingClientRect();
            /* Some column menus include a title or search row above their tabs.
               Keep those rows on the same material surface instead of stopping
               at the first tab-sized wrapper and exposing timeline content. */
            const maximumHeight = Math.max(156, tabRect.height + 92);
            let best = tabList.parentElement || tabList;
            let bestWidth = tabRect.width;
            let stickyBest = null;
            let candidate = best;
            for (let level = 0; candidate && candidate !== primaryColumn && level < 8; level += 1) {
              const rect = candidate.getBoundingClientRect();
              if (rect.height > maximumHeight) break;
              if (rect.width >= bestWidth - 1) {
                best = candidate;
                bestWidth = rect.width;
                const style = typeof getComputedStyle === 'function' ? getComputedStyle(candidate) : null;
                if (style && (style.position === 'sticky' || style.position === 'fixed')) {
                  stickyBest = candidate;
                }
              }
              candidate = candidate.parentElement;
            }
            return stickyBest || best;
          }

          function markTopTabRails() {
            if (typeof document.querySelectorAll !== 'function') return;
            const activeRails = new Set();
            const activeShells = new Set();
            document.querySelectorAll('[role="tablist"]').forEach(tabList => {
              if (!isTopNavigationTabList(tabList)) return;
              activeRails.add(tabList);
              tabList.dataset.mosaicTopTabRail = 'true';
              const shell = findTopTabShell(tabList);
              activeShells.add(shell);
              shell.dataset.mosaicTopTabShell = 'true';
              delete shell.dataset.mosaicNeedsPositioning;
              const shellStyle = typeof getComputedStyle === 'function' ? getComputedStyle(shell) : null;
              shell.dataset.mosaicNeedsPositioning = !shellStyle || shellStyle.position === 'static' ? 'true' : 'false';
              const menuState = globalThis.__mosaicColumnMenuMotion;
              shell.dataset.mosaicColumnMenuVisible = !menuState || menuState.visible !== false ? 'true' : 'false';
              updateTopTabOverflow(tabList);
            });
            document.querySelectorAll('[data-mosaic-top-tab-rail="true"]').forEach(rail => {
              if (activeRails.has(rail)) return;
              delete rail.dataset.mosaicTopTabRail;
              delete rail.dataset.mosaicOverflowLeft;
              delete rail.dataset.mosaicOverflowRight;
            });
            document.querySelectorAll('[data-mosaic-top-tab-shell="true"]').forEach(shell => {
              if (activeShells.has(shell)) return;
              delete shell.dataset.mosaicTopTabShell;
              delete shell.dataset.mosaicColumnScrolled;
              delete shell.dataset.mosaicColumnMenuVisible;
              delete shell.dataset.mosaicNeedsPositioning;
            });
            updateTopTabScrollState();
          }

          function currentColumnScrollOffset(scrollTarget) {
            const scrollingElement = document.scrollingElement || document.documentElement;
            const targetOffset = scrollTarget &&
              scrollTarget !== document &&
              scrollTarget !== window
                ? Number(scrollTarget.scrollTop) || 0
                : 0;
            return Math.max(
              typeof window !== 'undefined' ? Number(window.scrollY) || 0 : 0,
              Number(scrollingElement && scrollingElement.scrollTop) || 0,
              targetOffset
            );
          }

          function columnMenuClock() {
            if (typeof performance !== 'undefined' && typeof performance.now === 'function') {
              return performance.now();
            }
            return Date.now();
          }

          function columnMenuMotionState() {
            if (!globalThis.__mosaicColumnMenuMotion) {
              const initializedAt = columnMenuClock();
              globalThis.__mosaicColumnMenuMotion = {
                lastOffset: currentColumnScrollOffset(),
                visible: true,
                /* X can restore a saved scroll position in several delayed
                   layout passes. Keep that restoration from impersonating a
                   user gesture; wheel and keyboard intent clear this grace
                   immediately. */
                settleUntil: initializedAt + 3600
              };
            }
            return globalThis.__mosaicColumnMenuMotion;
          }

          function setColumnMenuVisible(visible) {
            const state = columnMenuMotionState();
            state.visible = Boolean(visible);
            if (typeof document.querySelectorAll !== 'function') return;
            document.querySelectorAll('[data-mosaic-top-tab-shell="true"]').forEach(shell => {
              shell.dataset.mosaicColumnMenuVisible = state.visible ? 'true' : 'false';
            });
          }

          globalThis.__mosaicSetColumnMenuVisible = setColumnMenuVisible;

          function noteColumnMenuScrollIntent(deltaY) {
            if (!Number.isFinite(deltaY) || Math.abs(deltaY) < 0.5) return;
            const state = columnMenuMotionState();
            state.settleUntil = 0;
            if (deltaY < 0) {
              setColumnMenuVisible(true);
            } else if (currentColumnScrollOffset() > 2) {
              setColumnMenuVisible(false);
            }
          }

          function updateTopTabScrollState(scrollTarget) {
            if (typeof document.querySelectorAll !== 'function') return;
            const scrollOffset = currentColumnScrollOffset(scrollTarget);
            const wasScrolled = globalThis.__mosaicColumnScrolled === true;
            const isScrolled = wasScrolled ? scrollOffset > 2 : scrollOffset > 12;
            globalThis.__mosaicColumnScrolled = isScrolled;
            const menuState = columnMenuMotionState();
            const scrollDelta = scrollOffset - menuState.lastOffset;
            menuState.lastOffset = scrollOffset;
            if (scrollOffset <= 2) {
              setColumnMenuVisible(true);
            } else if (columnMenuClock() <= menuState.settleUntil) {
              setColumnMenuVisible(true);
            } else if (Math.abs(scrollDelta) >= 0.5) {
              setColumnMenuVisible(scrollDelta < 0);
            }
            const shells = Array.from(document.querySelectorAll('[data-mosaic-top-tab-shell="true"]'));
            shells.forEach(shell => {
              shell.dataset.mosaicColumnScrolled = isScrolled ? 'true' : 'false';
              shell.dataset.mosaicColumnMenuVisible = menuState.visible ? 'true' : 'false';
            });
          }

          function accessibleControlLabel(node) {
            if (!node || !node.getAttribute) return '';
            return [
              node.getAttribute('aria-label') || '',
              node.getAttribute('title') || '',
              node.getAttribute('data-testid') || ''
            ].join(' ').toLowerCase();
          }

          function markVideoVolumeControls() {
            if (typeof document.querySelectorAll !== 'function') return;
            document.querySelectorAll('[data-testid="videoPlayer"]').forEach(player => {
              const controls = Array.from(player.querySelectorAll('button, [role="button"], [role="slider"], input[type="range"]'));
              const volumeButtons = controls.filter(control => /mute|unmute|volume/.test(accessibleControlLabel(control)) && control.getAttribute('role') !== 'slider' && control.tagName !== 'INPUT');
              volumeButtons.forEach(button => {
                button.dataset.mosaicVolumeButton = 'true';
              });

              const explicitSliders = controls.filter(control => {
                const isSlider = control.getAttribute('role') === 'slider' || control.tagName === 'INPUT';
                return isSlider && /volume|mute|unmute/.test(accessibleControlLabel(control));
              });

              volumeButtons.forEach(button => {
                let candidate = button.parentElement;
                for (let level = 0; candidate && candidate !== player && level < 4; level += 1) {
                  const nearbySlider = candidate.querySelector('[role="slider"], input[type="range"]');
                  const rect = candidate.getBoundingClientRect ? candidate.getBoundingClientRect() : null;
                  if (nearbySlider && (!rect || (rect.width <= 150 && rect.height <= 220))) {
                    explicitSliders.push(nearbySlider);
                    break;
                  }
                  candidate = candidate.parentElement;
                }
              });

              explicitSliders.forEach(slider => {
                slider.dataset.mosaicVolumeSlider = 'true';
                let popover = slider.parentElement;
                let bestPopover = null;
                for (let level = 0; popover && popover !== player && level < 3; level += 1) {
                  const rect = popover.getBoundingClientRect ? popover.getBoundingClientRect() : null;
                  if (!rect || (rect.width <= 150 && rect.height <= 220)) {
                    bestPopover = popover;
                  } else {
                    break;
                  }
                  popover = popover.parentElement;
                }
                if (bestPopover) bestPopover.dataset.mosaicVolumePopover = 'true';
              });
            });
          }

          function markConversationConnectors() {
            if (typeof document.querySelectorAll !== 'function') return;
            document.querySelectorAll('[data-mosaic-thread-connector="true"]').forEach(node => {
              delete node.dataset.mosaicThreadConnector;
            });

            document.querySelectorAll('[data-testid="tweet"]').forEach(tweet => {
              const avatar = tweet.querySelector('[data-testid="Tweet-User-Avatar"]') || tweet.querySelector('a[href] img');
              if (!avatar || !avatar.getBoundingClientRect) return;
              const avatarRect = avatar.getBoundingClientRect();
              const candidates = new Set();
              let scope = avatar.parentElement;
              for (let level = 0; scope && scope !== tweet && level < 5; level += 1) {
                scope.querySelectorAll('div').forEach(node => candidates.add(node));
                scope = scope.parentElement;
              }

              candidates.forEach(node => {
                if (!node.getBoundingClientRect || node.contains(avatar) || (node.textContent || '').trim()) return;
                const rect = node.getBoundingClientRect();
                const centerDelta = Math.abs((rect.left + rect.width / 2) - (avatarRect.left + avatarRect.width / 2));
                const isThreadStroke = rect.width >= 1 && rect.width <= 5 && rect.height >= 12 && centerDelta <= 4;
                const isOutsideAvatar = rect.bottom <= avatarRect.top + 3 || rect.top >= avatarRect.bottom - 3;
                if (isThreadStroke && isOutsideAvatar) node.dataset.mosaicThreadConnector = 'true';
              });
            });
          }

          function markReplyContexts() {
            if (typeof document.querySelectorAll !== 'function') return;
            document.querySelectorAll('[data-mosaic-reply-context="true"]').forEach(node => {
              delete node.dataset.mosaicReplyContext;
            });

            document.querySelectorAll('[data-testid="tweet"]').forEach(tweet => {
              tweet.querySelectorAll('div[dir="ltr"], span[dir="ltr"]').forEach(node => {
                if (node.closest('[data-testid="tweetText"]')) return;
                const text = (node.textContent || '').trim();
                if (!/^replying to(?:\\s|$)/i.test(text)) return;
                const mentionLinks = Array.from(node.querySelectorAll('a[href]')).filter(link => {
                  const label = (link.textContent || '').trim();
                  return label.startsWith('@');
                });
                if (mentionLinks.length > 0) node.dataset.mosaicReplyContext = 'true';
              });
            });
          }

          function markTransientPostIndicators() {
            if (typeof document.querySelectorAll !== 'function') return;
            document.querySelectorAll('[data-mosaic-post-indicator="true"]').forEach(node => {
              delete node.dataset.mosaicPostIndicator;
            });

            document.querySelectorAll('[data-testid="primaryColumn"] button, [data-testid="primaryColumn"] [role="button"]').forEach(control => {
              if (control.closest('article, [data-testid="tweet"], [data-testid="cellInnerDiv"], [data-mosaic-composer="true"], [data-mosaic-top-tab-shell="true"]')) return;
              const text = ((control.innerText || control.textContent) || '').trim().replace(/\\s+/g, ' ');
              if (!/(^|\\s)posted$/i.test(text) || !control.querySelector('img')) return;
              const rect = control.getBoundingClientRect ? control.getBoundingClientRect() : null;
              if (rect && (rect.width < 80 || rect.width > 430 || rect.height < 32 || rect.height > 112)) return;
              control.dataset.mosaicPostIndicator = 'true';
            });
          }

          function markSubscribeButtons() {
            if (typeof document.querySelectorAll !== 'function') return;
            document.querySelectorAll('[data-mosaic-subscribe-button="true"]').forEach(control => {
              delete control.dataset.mosaicSubscribeButton;
            });

            document.querySelectorAll('[data-testid="primaryColumn"] button, [data-testid="primaryColumn"] [role="button"]').forEach(control => {
              if (control.closest('[data-mosaic-composer="true"], [data-mosaic-top-tab-shell="true"]')) return;
              const text = ((control.innerText || control.textContent) || '').trim().replace(/\\s+/g, ' ');
              if (!/^subscribed?$/i.test(text)) return;
              if (control.querySelector('button, [role="button"]')) return;
              const rect = control.getBoundingClientRect ? control.getBoundingClientRect() : null;
              if (rect && (rect.width < 64 || rect.width > 240 || rect.height < 24 || rect.height > 72)) return;
              control.dataset.mosaicSubscribeButton = 'true';
            });
          }

          function postTopTabCapture(active) {
            try {
              const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.xflowTopTabScrollCapture;
              if (handler) handler.postMessage(Boolean(active));
            } catch (_) {}
          }

          const topTabMotion = new WeakMap();

          function cancelTopTabGlide(tabList) {
            const motion = topTabMotion.get(tabList);
            if (!motion) return;
            if (motion.frame) cancelAnimationFrame(motion.frame);
            motion.velocity = 0;
            motion.frame = 0;
            motion.lastTime = 0;
          }

          function queueTopTabGlide(tabList, delta) {
            const maximum = Math.max(0, tabList.scrollWidth - tabList.clientWidth);
            let motion = topTabMotion.get(tabList);
            if (!motion) {
              motion = { velocity: 0, frame: 0, lastTime: 0 };
              topTabMotion.set(tabList, motion);
            }
            const impulse = Math.max(-120, Math.min(120, delta));
            motion.velocity = Math.max(-38, Math.min(38, motion.velocity + impulse * 0.22));
            if (motion.frame) return;
            motion.lastTime = performance.now();

            function glide(timestamp) {
              const elapsed = Math.min(32, Math.max(8, timestamp - motion.lastTime));
              const frameScale = elapsed / 16.667;
              motion.lastTime = timestamp;
              const previous = tabList.scrollLeft;
              const next = Math.max(0, Math.min(maximum, previous + motion.velocity * frameScale));
              tabList.scrollLeft = next;
              updateTopTabOverflow(tabList);

              const hitBoundary = (next <= 0 && motion.velocity < 0) ||
                (next >= maximum && motion.velocity > 0);
              motion.velocity *= Math.pow(0.84, frameScale);
              if (Math.abs(motion.velocity) < 0.12 || hitBoundary) {
                motion.velocity = 0;
                motion.frame = 0;
                return;
              }
              motion.frame = requestAnimationFrame(glide);
            }

            motion.frame = requestAnimationFrame(glide);
          }

          function installTopTabInteraction() {
            if (globalThis.__mosaicTopTabHandlers || typeof document.addEventListener !== 'function') return;
            const handlers = {
              pointerover(event) {
                const tabList = event.target && event.target.closest && event.target.closest('[data-mosaic-top-tab-rail="true"]');
                if (tabList) postTopTabCapture(updateTopTabOverflow(tabList));
              },
              pointerout(event) {
                const tabList = event.target && event.target.closest && event.target.closest('[data-mosaic-top-tab-rail="true"]');
                if (tabList && (!event.relatedTarget || !tabList.contains(event.relatedTarget))) postTopTabCapture(false);
              },
              wheel(event) {
                const tabList = event.target && event.target.closest && event.target.closest('[data-mosaic-top-tab-rail="true"]');
                if (!tabList || !updateTopTabOverflow(tabList)) {
                  noteColumnMenuScrollIntent(event.deltaY);
                  return;
                }
                postTopTabCapture(true);
                const horizontalIntent = Math.abs(event.deltaX) >= Math.abs(event.deltaY);
                if (horizontalIntent) {
                  cancelTopTabGlide(tabList);
                  event.stopPropagation();
                  requestAnimationFrame(() => updateTopTabOverflow(tabList));
                  return;
                }
                const delta = event.deltaY;
                if (!Number.isFinite(delta) || Math.abs(delta) < 0.01) return;
                event.preventDefault();
                event.stopPropagation();
                const deltaScale = event.deltaMode === 1 ? 18 : (event.deltaMode === 2 ? tabList.clientWidth * 0.82 : 1);
                queueTopTabGlide(tabList, delta * deltaScale);
              },
              keydown(event) {
                const target = event.target;
                const isEditable = target && (
                  target.isContentEditable ||
                  target.tagName === 'INPUT' ||
                  target.tagName === 'TEXTAREA' ||
                  target.tagName === 'SELECT'
                );
                if (isEditable) return;

                const state = columnMenuMotionState();
                if (event.key === 'PageUp' || event.key === 'Home' || event.key === 'ArrowUp' ||
                    (event.key === ' ' && event.shiftKey)) {
                  state.settleUntil = 0;
                  setColumnMenuVisible(true);
                } else if (event.key === 'PageDown' || event.key === 'End' || event.key === 'ArrowDown' ||
                           (event.key === ' ' && !event.shiftKey)) {
                  state.settleUntil = 0;
                  setColumnMenuVisible(false);
                }
              },
              scroll(event) {
                const tabList = event.target && event.target.closest && event.target.closest('[data-mosaic-top-tab-rail="true"]');
                if (tabList) updateTopTabOverflow(tabList);
                updateTopTabScrollState(event.target);
              }
            };
            document.addEventListener('pointerover', handlers.pointerover, true);
            document.addEventListener('pointerout', handlers.pointerout, true);
            document.addEventListener('wheel', handlers.wheel, { capture: true, passive: false });
            document.addEventListener('keydown', handlers.keydown, true);
            document.addEventListener('scroll', handlers.scroll, true);
            globalThis.__mosaicTopTabHandlers = handlers;
          }

          markInlineComposers();
          markTopTabRails();
          markVideoVolumeControls();
          markConversationConnectors();
          markReplyContexts();
          markTransientPostIndicators();
          markSubscribeButtons();
          installTopTabInteraction();
          setColumnMenuVisible(true);
          if (!globalThis.__mosaicComposerObserver && typeof MutationObserver !== 'undefined' && document.body) {
            globalThis.__mosaicComposerObserver = new MutationObserver(() => {
              if (globalThis.__mosaicRefreshFrame) return;
              globalThis.__mosaicRefreshFrame = requestAnimationFrame(() => {
                globalThis.__mosaicRefreshFrame = 0;
                markInlineComposers();
                markTopTabRails();
                markVideoVolumeControls();
                markConversationConnectors();
                markReplyContexts();
                markTransientPostIndicators();
                markSubscribeButtons();
              });
            });
            globalThis.__mosaicComposerObserver.observe(document.body, { childList: true, subtree: true });
          }
          document.documentElement.dataset.mosaicAppearance = 'integrated';
          return 'mosaic-integrated';
        })();
        """

        static let removeIntegratedColumnThemeScript = """
        (function() {
          const style = document.getElementById('mosaic-integrated-column-style');
          if (style) style.remove();
          if (globalThis.__mosaicComposerObserver) {
            globalThis.__mosaicComposerObserver.disconnect();
            delete globalThis.__mosaicComposerObserver;
          }
          if (globalThis.__mosaicRefreshFrame) {
            cancelAnimationFrame(globalThis.__mosaicRefreshFrame);
            delete globalThis.__mosaicRefreshFrame;
          }
          delete globalThis.__mosaicColumnScrolled;
          delete globalThis.__mosaicColumnMenuMotion;
          delete globalThis.__mosaicSetColumnMenuVisible;
          if (globalThis.__mosaicTopTabHandlers && typeof document.removeEventListener === 'function') {
            const handlers = globalThis.__mosaicTopTabHandlers;
            document.removeEventListener('pointerover', handlers.pointerover, true);
            document.removeEventListener('pointerout', handlers.pointerout, true);
            document.removeEventListener('wheel', handlers.wheel, true);
            document.removeEventListener('keydown', handlers.keydown, true);
            document.removeEventListener('scroll', handlers.scroll, true);
            delete globalThis.__mosaicTopTabHandlers;
          }
          try {
            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.xflowTopTabScrollCapture;
            if (handler) handler.postMessage(false);
          } catch (_) {}
          if (typeof document.querySelectorAll === 'function') {
            document.querySelectorAll('[data-mosaic-composer="true"]').forEach(node => {
              delete node.dataset.mosaicComposer;
              node.style.removeProperty('--mosaic-post-label-left');
              node.style.removeProperty('--mosaic-post-label-top');
              node.style.removeProperty('--mosaic-post-label-width');
              node.style.removeProperty('--mosaic-post-label-height');
              node.style.removeProperty('--mosaic-composer-label-image');
            });
            document.querySelectorAll('[data-mosaic-synthetic-label="true"]').forEach(node => {
              delete node.dataset.mosaicSyntheticLabel;
            });
            document.querySelectorAll('[data-mosaic-top-tab-rail="true"]').forEach(node => {
              delete node.dataset.mosaicTopTabRail;
              delete node.dataset.mosaicOverflowLeft;
              delete node.dataset.mosaicOverflowRight;
            });
            document.querySelectorAll('[data-mosaic-top-tab-shell="true"]').forEach(node => {
              delete node.dataset.mosaicTopTabShell;
              delete node.dataset.mosaicColumnScrolled;
              delete node.dataset.mosaicColumnMenuVisible;
              delete node.dataset.mosaicNeedsPositioning;
            });
            document.querySelectorAll('[data-mosaic-volume-button="true"]').forEach(node => {
              delete node.dataset.mosaicVolumeButton;
            });
            document.querySelectorAll('[data-mosaic-volume-slider="true"]').forEach(node => {
              delete node.dataset.mosaicVolumeSlider;
            });
            document.querySelectorAll('[data-mosaic-volume-popover="true"]').forEach(node => {
              delete node.dataset.mosaicVolumePopover;
            });
            document.querySelectorAll('[data-mosaic-thread-connector="true"]').forEach(node => {
              delete node.dataset.mosaicThreadConnector;
            });
            document.querySelectorAll('[data-mosaic-reply-context="true"]').forEach(node => {
              delete node.dataset.mosaicReplyContext;
            });
            document.querySelectorAll('[data-mosaic-post-indicator="true"]').forEach(node => {
              delete node.dataset.mosaicPostIndicator;
            });
            document.querySelectorAll('[data-mosaic-subscribe-button="true"]').forEach(node => {
              delete node.dataset.mosaicSubscribeButton;
            });
          }
          if (document.documentElement) delete document.documentElement.dataset.mosaicAppearance;
          return 'original-x';
        })();
        """

        static func columnAppearanceScript(for mode: ColumnAppearanceMode) -> String {
            switch mode {
            case .originalX:
                return removeIntegratedColumnThemeScript
            case .mosaicIntegrated:
                return integratedColumnThemeScript
            }
        }

        static let unreadCountScript = NotificationActivityScript.source

        var currentURL: URL?
        var refreshKey: String = ""
        var filter: ColumnFilter = .none
        var accountID: UUID?
        var onNavigation: ((URL?) -> Void)?
        var onDetectedHandle: ((String) -> Void)?
        var onDetectedProfileImage: ((URL?) -> Void)?
        var onLaunchSessionResolved: ((Bool) -> Void)?
        private var launchSessionFinished = false
        private var loginPageBeganAt: TimeInterval?
        var onInitialContentReady: (() -> Void)?
        private var hasReportedInitialContent = false
        var onPageTitle: ((String?) -> Void)?
        var onMediaRequest: ((MediaRequest) -> Void)?
        var onUnreadNotificationCountChanged: ((Int, NotificationActivity?) -> Void)?
        var onComposerPresentationReady: (() -> Void)?
        var onComposerDismissed: (() -> Void)?
        weak var deckWebView: DeckWKWebView?
        var columnAppearanceMode: ColumnAppearanceMode
        var appliedColumnAppearanceMode: ColumnAppearanceMode?
        var enableHandleDetection: Bool
        var enableAccountTextHandleDetection: Bool
        var enableBroadHandleDetection: Bool
        var onPageReadyScript: String?
        private var restorationState: (scrollY: Double, anchorPath: String?, anchorOffset: Double)?

        init(
            onNavigation: ((URL?) -> Void)?,
            onDetectedHandle: ((String) -> Void)?,
            onDetectedProfileImage: ((URL?) -> Void)?,
            onPageTitle: ((String?) -> Void)?,
            onMediaRequest: ((MediaRequest) -> Void)?,
            onUnreadNotificationCountChanged: ((Int, NotificationActivity?) -> Void)?,
            onComposerPresentationReady: (() -> Void)?,
            onComposerDismissed: (() -> Void)?,
            columnAppearanceMode: ColumnAppearanceMode,
            enableHandleDetection: Bool,
            enableAccountTextHandleDetection: Bool,
            enableBroadHandleDetection: Bool,
            onPageReadyScript: String?
        ) {
            self.onNavigation = onNavigation
            self.onDetectedHandle = onDetectedHandle
            self.onDetectedProfileImage = onDetectedProfileImage
            self.onPageTitle = onPageTitle
            self.onMediaRequest = onMediaRequest
            self.onUnreadNotificationCountChanged = onUnreadNotificationCountChanged
            self.onComposerPresentationReady = onComposerPresentationReady
            self.onComposerDismissed = onComposerDismissed
            self.columnAppearanceMode = columnAppearanceMode
            self.enableHandleDetection = enableHandleDetection
            self.enableAccountTextHandleDetection = enableAccountTextHandleDetection
            self.enableBroadHandleDetection = enableBroadHandleDetection
            self.onPageReadyScript = onPageReadyScript
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onNavigation?(webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigation?(webView.url)
            onPageTitle?(webView.title)
            deckWebView?.resetColumnMenuScrollState(restoringPosition: restorationState != nil)
            applyFilter(to: webView)
            applyColumnAppearance(to: webView)
            restoreCapturedPosition(in: webView)
            if let onPageReadyScript {
                webView.evaluateJavaScript(onPageReadyScript)
            }
            if enableHandleDetection {
                detectProfileMeta(in: webView)
            }
            checkInitialContent(in: webView)
            checkLaunchSession(in: webView)
        }

        static let launchSessionStateScript = """
        (() => {
          if (document.readyState !== 'complete') return 'waiting';
          const login = document.querySelector('input[autocomplete="username"], input[autocomplete="current-password"], [data-testid="LoginForm_Login_Button"]');
          if (login) return 'login';
          const account = document.querySelector('[data-testid="SideNav_AccountSwitcher_Button"]');
          const primary = document.querySelector('[data-testid="primaryColumn"]');
          if (account && primary && !document.querySelector('[role="dialog"]')) return 'authenticated';
          return 'waiting';
        })()
        """

        private func checkLaunchSession(in webView: WKWebView) {
            guard !launchSessionFinished, onLaunchSessionResolved != nil else { return }
            webView.evaluateJavaScript(Self.launchSessionStateScript) { [weak self, weak webView] value, _ in
                guard let self, let webView, !self.launchSessionFinished,
                      self.onLaunchSessionResolved != nil, let accountID = self.accountID else { return }
                let state = webView.isLoading ? "waiting" : (value as? String ?? "waiting")
                if state == "login" {
                    if self.loginPageBeganAt == nil { self.loginPageBeganAt = ProcessInfo.processInfo.systemUptime }
                } else {
                    self.loginPageBeganAt = nil
                }
                if state == "authenticated" {
                    WebSessionPool.shared.appearsAuthenticated(accountID: accountID) { [weak self, weak webView] authenticated in
                        guard let self, let webView, !self.launchSessionFinished else { return }
                        if authenticated && !webView.isLoading {
                            self.launchSessionFinished = true
                            self.onLaunchSessionResolved?(true)
                        } else {
                            self.scheduleLaunchSessionCheck(in: webView)
                        }
                    }
                } else if let beganAt = self.loginPageBeganAt,
                          ProcessInfo.processInfo.systemUptime - beganAt >= 2 {
                    // A stable credential form needs the user. Transient SSO/login
                    // screens get two seconds to redirect before making that decision.
                    self.launchSessionFinished = true
                    self.onLaunchSessionResolved?(false)
                } else {
                    self.scheduleLaunchSessionCheck(in: webView)
                }
            }
        }

        private func scheduleLaunchSessionCheck(in webView: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak webView] in
                if let webView { self?.checkLaunchSession(in: webView) }
            }
        }

        static let initialContentReadyScript = """
        (() => {
          const primary = document.querySelector('[data-testid="primaryColumn"]');
          if (document.readyState !== 'complete' || !primary) return false;
          const content = primary.querySelector('article, [data-testid="notification"], [data-testid="cellInnerDiv"], [data-testid="emptyState"], [data-testid="UserProfileHeader_Items"], [role="alert"]');
          if (!content) return false;
          const images = Array.from(primary.querySelectorAll('img')).filter(image => {
            const rect = image.getBoundingClientRect();
            return rect.bottom > 0 && rect.top < innerHeight;
          });
          return images.every(image => image.complete);
        })()
        """

        private func checkInitialContent(in webView: WKWebView) {
            guard !hasReportedInitialContent, onInitialContentReady != nil else { return }
            webView.evaluateJavaScript(Self.initialContentReadyScript) { [weak self, weak webView] result, _ in
                guard let self, let webView, self.onInitialContentReady != nil else { return }
                if result as? Bool == true, !webView.isLoading {
                    // Allow the ready DOM and its theme a rendering turn before revealing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak webView] in
                        guard let self, let webView, !webView.isLoading else { return }
                        self.hasReportedInitialContent = true
                        self.onInitialContentReady?()
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak webView] in
                        if let webView { self?.checkInitialContent(in: webView) }
                    }
                }
            }
        }

        func applyColumnAppearance(to webView: WKWebView) {
            let mode = columnAppearanceMode
            webView.evaluateJavaScript(Self.columnAppearanceScript(for: mode)) { [weak self] _, _ in
                self?.appliedColumnAppearanceMode = mode
            }
        }

        func captureRestorationState(in webView: WKWebView, completion: @escaping () -> Void) {
            let script = """
            (function() {
              const scrolling = document.scrollingElement || document.documentElement;
              const scrollY = Number(scrolling ? scrolling.scrollTop : window.scrollY) || 0;
              const articles = Array.from(document.querySelectorAll('article'));
              const visible = articles.find(function(article) {
                const rect = article.getBoundingClientRect();
                return rect.bottom > 0 && rect.top < window.innerHeight;
              });
              const link = visible && visible.querySelector('a[href*="/status/"]');
              let anchorPath = '';
              if (link && link.href) {
                try { anchorPath = new URL(link.href).pathname || ''; } catch (_) {}
              }
              const anchorOffset = visible ? visible.getBoundingClientRect().top : 0;
              return JSON.stringify({ scrollY, anchorPath, anchorOffset });
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                defer { completion() }
                guard let self,
                      let payload = result as? String,
                      let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                let rawAnchorPath = json["anchorPath"] as? String
                self.restorationState = (
                    scrollY: (json["scrollY"] as? NSNumber)?.doubleValue ?? 0,
                    anchorPath: rawAnchorPath.flatMap { $0.isEmpty ? nil : $0 },
                    anchorOffset: (json["anchorOffset"] as? NSNumber)?.doubleValue ?? 0
                )
            }
        }

        private func restoreCapturedPosition(in webView: WKWebView) {
            guard let restorationState else { return }
            self.restorationState = nil

            let anchorPath = JavaScriptEncoding.stringLiteral(restorationState.anchorPath)
            let scrollY = restorationState.scrollY.isFinite ? restorationState.scrollY : 0
            let anchorOffset = restorationState.anchorOffset.isFinite ? restorationState.anchorOffset : 0
            let script = """
            (function() {
              const targetPath = \(anchorPath);
              const fallbackY = \(scrollY);
              const targetOffset = \(anchorOffset);
              let attempts = 0;
              function restore() {
                if (targetPath) {
                  const links = Array.from(document.querySelectorAll('a[href*="/status/"]'));
                  const link = links.find(function(candidate) {
                    try { return new URL(candidate.href).pathname === targetPath; } catch (_) { return false; }
                  });
                  const article = link && link.closest('article');
                  if (article) {
                    article.scrollIntoView({ block: 'start' });
                    window.scrollBy(0, -targetOffset);
                    return;
                  }
                }
                if (attempts++ < 20) {
                  setTimeout(restore, 150);
                } else {
                  window.scrollTo(0, fallbackY);
                }
              }
              setTimeout(restore, 150);
            })();
            """
            webView.evaluateJavaScript(script)
        }

        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping ([URL]?) -> Void
        ) {
            guard Self.isTrustedFrame(frame) else {
                completionHandler(nil)
                return
            }

            let panel = NSOpenPanel()
            panel.message = "Choose a photo or video to attach"
            panel.prompt = "Choose"
            panel.allowedContentTypes = Self.composerAttachmentContentTypes
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.canCreateDirectories = false
            panel.resolvesAliases = true

            // Keep WebKit's required completion handler on this stack until the
            // native chooser closes. Releasing it early causes WebKit to abort.
            let response = panel.runModal()
            completionHandler(response == .OK ? panel.urls : nil)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               Self.isTrustedFrame(navigationAction.sourceFrame),
               let targetURL = navigationAction.request.url {
                switch Self.navigationDisposition(
                    for: targetURL,
                    isMainFrame: true,
                    navigationType: navigationAction.navigationType
                ) {
                case .openExternally:
                    NSWorkspace.shared.open(targetURL)
                case .allowInWebView:
                    webView.load(URLRequest(url: targetURL))
                case .cancel:
                    break
                }
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            switch Self.navigationDisposition(
                for: targetURL,
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                navigationType: navigationAction.navigationType
            ) {
            case .openExternally:
                if Self.isTrustedFrame(navigationAction.sourceFrame) {
                    NSWorkspace.shared.open(targetURL)
                }
                decisionHandler(.cancel)
            case .allowInWebView:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            }
        }

        static func navigationDisposition(
            for url: URL,
            isMainFrame: Bool,
            navigationType: WKNavigationType
        ) -> NavigationDisposition {
            if !isMainFrame {
                return TrustedURLPolicy.isSafeSubframeURL(url) ? .allowInWebView : .cancel
            }

            if TrustedURLPolicy.isTrustedXPage(url) {
                return .allowInWebView
            }

            if url.scheme?.lowercased() == "about", url.absoluteString == "about:blank" {
                return .allowInWebView
            }

            guard navigationType == .linkActivated,
                  TrustedURLPolicy.isTrustedExternalWebURL(url) else {
                return .cancel
            }
            return .openExternally
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard Self.isTrustedScriptMessage(message) else {
                return
            }

            if message.name == Self.mediaMessageName {
                guard let payload = message.body as? [String: Any],
                      let rawKind = payload["kind"] as? String else {
                    return
                }

                guard let kind = MediaKind(rawValue: rawKind),
                      let rawURL = payload["url"] as? String,
                      let parsed = URL(string: rawURL) else {
                    return
                }

                let currentTime = (payload["currentTime"] as? NSNumber)?.doubleValue
                let mediaURL = (payload["mediaURL"] as? String).flatMap(URL.init(string:))
                guard let request = MediaRequest.validatedBridgeRequest(
                    kind: kind,
                    url: parsed,
                    currentTime: currentTime,
                    mediaURL: mediaURL
                ) else {
                    return
                }
                onMediaRequest?(request)
                return
            }

            if message.name == Self.topTabScrollMessageName {
                let isCapturing = (message.body as? NSNumber)?.boolValue ?? (message.body as? Bool) ?? false
                deckWebView?.capturesHorizontalScrollInTopTabRail = isCapturing
                return
            }

            if message.name == Self.composerPresentationMessageName {
                guard let payload = message.body as? [String: Any],
                      let event = payload["event"] as? String else { return }
                switch event {
                case "ready":
                    onComposerPresentationReady?()
                case "dismissed":
                    onComposerDismissed?()
                default:
                    break
                }
                return
            }

            if message.name == Self.unreadCountMessageName {
                guard let payload = message.body as? [String: Any],
                      let count = (payload["count"] as? NSNumber)?.intValue,
                      (0...100_000).contains(count) else {
                    return
                }
                if payload["baseline"] as? Bool == true {
                    if let accountID {
                        XFlowNotificationCenter.shared.observeUnreadBaseline(count: count, accountID: accountID)
                    }
                    return
                }
                let activity = (payload["activity"] as? [String: Any]).flatMap(NotificationActivity.init(payload:))
                onUnreadNotificationCountChanged?(count, activity)
            }
        }

        private static func isTrustedScriptMessage(_ message: WKScriptMessage) -> Bool {
            isTrustedFrame(message.frameInfo)
        }

        private static func isTrustedFrame(_ frame: WKFrameInfo) -> Bool {
            let origin = frame.securityOrigin
            return frame.isMainFrame && TrustedURLPolicy.isTrustedXOrigin(
                scheme: origin.protocol,
                host: origin.host,
                port: origin.port
            )
        }

        func applyFilter(to webView: WKWebView) {
            guard filter.hasRules else {
                webView.evaluateJavaScript("window.__xflowClearFilter && window.__xflowClearFilter();")
                return
            }

            let include = JavaScriptEncoding.stringLiteral(filter.includeKeywords)
            let exclude = JavaScriptEncoding.stringLiteral(filter.excludeKeywords)
            let hideReplies = filter.hideReplies ? "true" : "false"
            let hideReposts = filter.hideReposts ? "true" : "false"

            let script = """
            (function() {
              const include = \(include);
              const exclude = \(exclude);
              const hideReplies = \(hideReplies);
              const hideReposts = \(hideReposts);

              function tokenize(csv) {
                if (!csv) return [];
                return csv.toLowerCase().split(',').map(s => s.trim()).filter(Boolean);
              }

              const includeTokens = tokenize(include);
              const excludeTokens = tokenize(exclude);

              function shouldHide(article) {
                const text = (article.innerText || '').toLowerCase();

                if (hideReplies && text.includes('replying to')) return true;
                if (hideReposts && (text.includes(' reposted') || text.includes(' repost\\n') || text.includes('reposted'))) return true;

                if (includeTokens.length > 0 && !includeTokens.some(t => text.includes(t))) return true;
                if (excludeTokens.length > 0 && excludeTokens.some(t => text.includes(t))) return true;

                return false;
              }

              function apply() {
                if (document.hidden || window.__mosaicBackgroundSuspended) return;
                const articles = document.querySelectorAll('article');
                articles.forEach(article => {
                  if (shouldHide(article)) {
                    article.style.display = 'none';
                  } else {
                    article.style.removeProperty('display');
                  }
                });
              }

              function clear() {
                const articles = document.querySelectorAll('article');
                articles.forEach(article => article.style.removeProperty('display'));
              }

              window.__xflowClearFilter = clear;

              apply();

              if (window.__xflowFilterInterval) {
                clearInterval(window.__xflowFilterInterval);
              }
              window.__xflowFilterInterval = setInterval(apply, 1800);
              document.addEventListener('visibilitychange', function() {
                if (!document.hidden) apply();
              });
              window.addEventListener('mosaicresume', apply);
            })();
            """

            webView.evaluateJavaScript(script)
        }

        private func detectProfileMeta(in webView: WKWebView) {
            let script = """
            (function() {
              const reserved = new Set(['home','notifications','messages','explore','search','i','compose','settings','premium','grok','tos','privacy','about','intent','share']);

              function normalize(path) {
                if (!path || !path.startsWith('/')) return null;
                const candidate = path.slice(1).split('/')[0].toLowerCase();
                if (!candidate || reserved.has(candidate)) return null;
                if (!/^[a-z0-9_]{1,15}$/.test(candidate)) return null;
                return candidate;
              }

              function extractHandleFromText(text) {
                if (!text) return '';
                const match = text.match(/@([a-z0-9_]{1,15})/i);
                return match ? (match[1] || '').toLowerCase() : '';
              }

              function decodeProfileURL(raw) {
                if (!raw) return '';
                return raw
                  .replace(/\\\\u002F/g, '/')
                  .replace(/\\\\\\//g, '/');
              }

              function collect() {
                let avatarCandidate = '';
                let handleCandidate = '';

                const switcher = document.querySelector('button[data-testid="SideNav_AccountSwitcher_Button"], button[aria-label*="@"]');
                if (switcher) {
                  const switcherHandle = extractHandleFromText(
                    (switcher.innerText || '') + ' ' + (switcher.getAttribute('aria-label') || '')
                  );
                  if (switcherHandle) handleCandidate = switcherHandle;
                  const switcherImg = switcher.querySelector('img');
                  if (switcherImg && switcherImg.src) avatarCandidate = switcherImg.src;
                }

                if (!avatarCandidate) {
                  const navAvatar = document.querySelector('nav[aria-label="Primary"] img[src*="profile_images"], img[src*="profile_images"]');
                  if (navAvatar && navAvatar.src) avatarCandidate = navAvatar.src;
                }

                const directProfile = document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
                if (directProfile) {
                  const found = normalize(directProfile.getAttribute('href') || '');
                  const profileImg = directProfile.querySelector('img');
                  if (!avatarCandidate && profileImg && profileImg.src) avatarCandidate = profileImg.src;
                  if (found) handleCandidate = found;
                }

                if (!handleCandidate) {
                  const navLinks = Array.from(document.querySelectorAll('nav a[href^="/"]'));
                  for (const link of navLinks) {
                    const hrefHandle = normalize(link.getAttribute('href') || '');
                    const textHandle = extractHandleFromText(
                      (link.textContent || '') + ' ' + (link.getAttribute('aria-label') || '')
                    );
                    if (hrefHandle || textHandle) {
                      handleCandidate = (hrefHandle || textHandle || '').toLowerCase();
                      const linkImg = link.querySelector('img');
                      if (!avatarCandidate && linkImg && linkImg.src) avatarCandidate = linkImg.src;
                      break;
                    }
                  }
                }

                if (!avatarCandidate) {
                  const metaAvatar = document.querySelector('meta[property="og:image"]');
                  if (metaAvatar && metaAvatar.content) avatarCandidate = metaAvatar.content;
                }

                if (!handleCandidate) {
                  const locationMatch = normalize(window.location.pathname || '');
                  if (locationMatch) handleCandidate = locationMatch;
                }

                if (!handleCandidate) {
                  const allLinks = Array.from(document.querySelectorAll('a[href^="/"]'));
                  for (const link of allLinks) {
                    const found = normalize(link.getAttribute('href') || '');
                    if (!found) continue;
                    const text = (link.textContent || '').trim().toLowerCase();
                    const aria = (link.getAttribute('aria-label') || '').trim().toLowerCase();
                    if (text.startsWith('@') || aria.includes('profile')) {
                      handleCandidate = found;
                      break;
                    }
                  }
                }

                if (!handleCandidate) {
                  const fromTitle = extractHandleFromText(document.title || '');
                  if (fromTitle) handleCandidate = fromTitle;
                }

                if (!handleCandidate || !avatarCandidate) {
                  const html = document.documentElement ? (document.documentElement.innerHTML || '') : '';
                  if (!handleCandidate) {
                    const screenMatch = html.match(/"screen_name":"([a-zA-Z0-9_]{1,15})"/);
                    if (screenMatch && screenMatch[1]) {
                      handleCandidate = screenMatch[1].toLowerCase();
                    }
                  }
                  if (!avatarCandidate) {
                    const avatarMatch = html.match(/"profile_image_url_https":"([^"]+)"/);
                    if (avatarMatch && avatarMatch[1]) {
                      avatarCandidate = decodeProfileURL(avatarMatch[1]);
                    }
                  }
                }

                return { handle: handleCandidate || '', avatar: avatarCandidate || '' };
              }

              return new Promise(function(resolve) {
                let attempts = 0;
                function tick() {
                  const result = collect();
                  if ((result.handle && result.handle.length > 0) || (result.avatar && result.avatar.length > 0) || attempts >= 18) {
                    resolve(JSON.stringify(result));
                    return;
                  }
                  attempts += 1;
                  setTimeout(tick, 120);
                }
                tick();
              });
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self,
                      let payload = result as? String,
                      let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                if let handle = json["handle"] as? String,
                   !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.onDetectedHandle?(handle)
                }

                if let avatarRaw = json["avatar"] as? String, !avatarRaw.isEmpty {
                    self.onDetectedProfileImage?(URL(string: avatarRaw))
                }
            }
        }

    }
}
