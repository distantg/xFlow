import AppKit
import Foundation
import SwiftUI
import WebKit

final class DeckWKWebView: WKWebView {
    var routeHorizontalScrollToParent: Bool = true
    private var isForwardingHorizontalSequence = false
    private var gestureAxisLock: GestureAxisLock = .undecided

    private enum GestureAxisLock {
        case undecided
        case horizontal
        case vertical
    }

    override func scrollWheel(with event: NSEvent) {
        if routeHorizontalScrollToParent {
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

struct WebColumnView: NSViewRepresentable {
    let url: URL
    let refreshKey: String
    let accountID: UUID
    let filter: ColumnFilter
    var onNavigation: ((URL?) -> Void)? = nil
    var onDetectedHandle: ((String) -> Void)? = nil
    var onDetectedProfileImage: ((URL?) -> Void)? = nil
    var onPageTitle: ((String?) -> Void)? = nil
    var onMediaRequest: ((MediaRequest) -> Void)? = nil
    var onUnreadNotificationCountChanged: ((Int, String?) -> Void)? = nil
    var enableChromeStripping: Bool = true
    var enableMediaCapture: Bool = true
    var enableHandleDetection: Bool = true
    var onPageReadyScript: String? = nil
    var routeHorizontalScrollToParent: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigation: onNavigation,
            onDetectedHandle: onDetectedHandle,
            onDetectedProfileImage: onDetectedProfileImage,
            onPageTitle: onPageTitle,
            onMediaRequest: onMediaRequest,
            onUnreadNotificationCountChanged: onUnreadNotificationCountChanged,
            enableHandleDetection: enableHandleDetection,
            onPageReadyScript: onPageReadyScript
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WebSessionPool.shared.configuration(for: accountID)
        let contentController = configuration.userContentController
        if enableMediaCapture {
            contentController.add(context.coordinator, name: Coordinator.mediaMessageName)
            contentController.addUserScript(WKUserScript(
                source: Coordinator.mediaCaptureScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }

        if onUnreadNotificationCountChanged != nil {
            contentController.add(context.coordinator, name: Coordinator.unreadCountMessageName)
            contentController.addUserScript(WKUserScript(
                source: Coordinator.unreadCountScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }

        if enableChromeStripping {
            contentController.addUserScript(WKUserScript(
                source: Coordinator.nativeColumnChromeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }

        let webView = DeckWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.routeHorizontalScrollToParent = routeHorizontalScrollToParent
        if let nativeScrollView = webView.subviews.compactMap({ $0 as? NSScrollView }).first {
            nativeScrollView.hasHorizontalScroller = false
            nativeScrollView.horizontalScrollElasticity = .none
        }

        context.coordinator.currentURL = url
        context.coordinator.refreshKey = refreshKey
        context.coordinator.filter = filter
        context.coordinator.accountID = accountID
        context.coordinator.enableHandleDetection = enableHandleDetection
        context.coordinator.onPageReadyScript = onPageReadyScript

        webView.load(URLRequest(url: url))

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigation = onNavigation
        context.coordinator.onDetectedHandle = onDetectedHandle
        context.coordinator.onDetectedProfileImage = onDetectedProfileImage
        context.coordinator.onPageTitle = onPageTitle
        context.coordinator.onMediaRequest = onMediaRequest
        context.coordinator.onUnreadNotificationCountChanged = onUnreadNotificationCountChanged
        context.coordinator.enableHandleDetection = enableHandleDetection
        context.coordinator.onPageReadyScript = onPageReadyScript
        if let webView = webView as? DeckWKWebView {
            webView.routeHorizontalScrollToParent = routeHorizontalScrollToParent
        }

        if context.coordinator.accountID != accountID {
            context.coordinator.accountID = accountID
            context.coordinator.currentURL = url
            context.coordinator.filter = filter
            webView.load(URLRequest(url: url))
            return
        }

        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            context.coordinator.filter = filter
            webView.load(URLRequest(url: url))
            return
        }

        if context.coordinator.refreshKey != refreshKey {
            context.coordinator.refreshKey = refreshKey
            context.coordinator.filter = filter
            // Always reload from the target route so columns recover from /i/flow/login redirects.
            webView.load(URLRequest(url: url))
            return
        }

        if context.coordinator.filter != filter {
            context.coordinator.filter = filter
            context.coordinator.applyFilter(to: webView)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.evaluateJavaScript("""
        (function() {
          document.querySelectorAll('video, audio').forEach(function(node) {
            try {
              node.pause && node.pause();
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
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let mediaMessageName = "xflowMediaRequest"
        static let unreadCountMessageName = "xflowUnreadCount"

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
            return /full\\s*screen|fullscreen|picture\\s*in\\s*picture|picture-in-picture|\\bpip\\b/.test(label);
          }

          function isPlaybackControlTarget(event) {
            if (event.target.closest('input[type="range"], progress')) return true;
            const controlButton = event.target.closest('button, [role="button"]');
            if (!controlButton) return false;
            const label = buttonLabel(controlButton);
            return /play|pause|mute|unmute|volume|settings|seek|scrub|speed|captions|subtitle|cc/.test(label);
          }

          document.addEventListener('click', function(event) {
            const pathname = window.location.pathname || '';

            if (pathname.startsWith('/messages')) {
              const directVideo = event.target.closest('video');
              const messageContainer = event.target.closest('[data-testid*="message"], [data-testid*="cellInnerDiv"], [role="listitem"], article, li, div');
              const videoNode = directVideo || (messageContainer ? messageContainer.querySelector('video') : null);
              const strictControl = event.target.closest('input[type="range"], progress, [aria-label*="volume" i], [aria-label*="settings" i], [aria-label*="seek" i], [aria-label*="scrub" i], [aria-label*="captions" i], [aria-label*="subtitle" i]');
              if (videoNode && !strictControl) {
                const mediaURL = videoNode.currentSrc || videoNode.src || ((videoNode.querySelector && videoNode.querySelector('source')) ? (videoNode.querySelector('source').src || '') : '');
                const timestamp = Number.isFinite(videoNode.currentTime) ? videoNode.currentTime : 0;
                const permalink = window.location.href;

                try { videoNode.pause(); } catch (_) {}
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
                const permalink = findPermalink(videoContainer) || window.location.href;
                const videoNode = videoContainer.querySelector('video');
                if (!videoNode) return;
                const mediaURL = videoNode.currentSrc || videoNode.src || '';
                const timestamp = Number.isFinite(videoNode.currentTime) ? videoNode.currentTime : 0;
                videoNode.pause();
                event.preventDefault();
                event.stopPropagation();
                send({ kind: 'video', url: permalink, mediaURL: mediaURL, currentTime: timestamp });
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

        static let nativeColumnChromeScript = """
        (function() {
          if (window.__xflowNativeChromeInstalled) return;
          window.__xflowNativeChromeInstalled = true;

          const styleID = 'xflow-native-column-style';

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
                border-right: none !important;
                width: 100% !important;
                max-width: none !important;
                background: rgba(255, 255, 255, 0.18) !important;
                backdrop-filter: blur(10px) saturate(1.12) !important;
              }
              html, body, #react-root, [data-testid="react-root"] {
                background: transparent !important;
              }
              [data-testid="primaryColumn"] section > div > div > div > div {
                border-left: none !important;
                border-right: none !important;
              }
              [data-testid="primaryColumn"] [data-testid="cellInnerDiv"] article {
                background: rgba(255, 255, 255, 0.63) !important;
                backdrop-filter: blur(8px) saturate(1.08) !important;
              }
              [data-testid="primaryColumn"] [data-testid="tweet"] {
                background: transparent !important;
              }
              [data-testid="primaryColumn"] [role="separator"] {
                opacity: 0.22 !important;
              }
              @media (prefers-color-scheme: dark) {
                html, body, #react-root, [data-testid="react-root"] {
                  background: #000 !important;
                }
                [data-testid="primaryColumn"] {
                  background: rgba(0, 0, 0, 0.72) !important;
                  color-scheme: dark !important;
                }
                [data-testid="primaryColumn"] [data-testid="cellInnerDiv"] article {
                  background: rgba(0, 0, 0, 0.84) !important;
                }
                [data-testid="primaryColumn"] [role="separator"] {
                  opacity: 0.32 !important;
                }
              }
              @media (prefers-color-scheme: light) {
                html, body, #react-root, [data-testid="react-root"] {
                  background: transparent !important;
                }
                [data-testid="primaryColumn"] {
                  background: rgba(255, 255, 255, 0.18) !important;
                  color-scheme: light !important;
                }
                [data-testid="primaryColumn"] [data-testid="cellInnerDiv"] article {
                  background: rgba(255, 255, 255, 0.63) !important;
                }
              }
            `;
            (document.head || document.documentElement).appendChild(style);
          }

          ensureStyle();
        })();
        """

        static let unreadCountScript = """
        (function() {
          if (window.__xflowUnreadCountInstalled) return;
          window.__xflowUnreadCountInstalled = true;
          const path = window.location.pathname || '';
          const isNotificationsRoute = /\\/notifications/.test(path);
          const isMessagesRoute = /\\/messages/.test(path);
          if (!isNotificationsRoute && !isMessagesRoute) return;

          function parseUnreadCount() {
            const title = document.title || '';
            const match = title.match(/^\\((\\d+)\\)/);
            if (!match) return 0;
            const parsed = Number(match[1]);
            return Number.isFinite(parsed) ? parsed : 0;
          }

          function detectActivity() {
            if (isMessagesRoute) {
              return 'new direct message';
            }
            const firstNotification = document.querySelector('[data-testid="notification"], [data-testid="cellInnerDiv"]');
            const text = ((firstNotification && firstNotification.innerText) || '').toLowerCase();
            if (!text) return 'new activity';
            if (text.includes('followed you')) return 'new follower';
            if (text.includes('replied')) return 'new reply';
            if (text.includes('mentioned')) return 'new mention';
            if (text.includes('sent you a message') || text.includes('message')) return 'new direct message';
            if (text.includes('liked')) return 'new like';
            if (text.includes('reposted')) return 'new repost';
            if (text.includes('quoted')) return 'new quote';
            return 'new activity';
          }

          function send(count, activity) {
            try {
              if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.xflowUnreadCount) return;
              window.webkit.messageHandlers.xflowUnreadCount.postMessage({ count: count, activity: activity || '' });
            } catch (_) {}
          }

          let state = { lastCount: parseUnreadCount(), warmupDone: false };

          function checkCount() {
            const currentCount = parseUnreadCount();
            const currentActivity = detectActivity();
            if (state.warmupDone && currentCount > state.lastCount) {
              send(currentCount, currentActivity);
            }
            state.lastCount = currentCount;
            state.warmupDone = true;
          }

          checkCount();
          setInterval(checkCount, 3500);
          document.addEventListener('visibilitychange', checkCount);
        })();
        """

        var currentURL: URL?
        var refreshKey: String = ""
        var filter: ColumnFilter = .none
        var accountID: UUID?
        var onNavigation: ((URL?) -> Void)?
        var onDetectedHandle: ((String) -> Void)?
        var onDetectedProfileImage: ((URL?) -> Void)?
        var onPageTitle: ((String?) -> Void)?
        var onMediaRequest: ((MediaRequest) -> Void)?
        var onUnreadNotificationCountChanged: ((Int, String?) -> Void)?
        var enableHandleDetection: Bool
        var onPageReadyScript: String?

        init(
            onNavigation: ((URL?) -> Void)?,
            onDetectedHandle: ((String) -> Void)?,
            onDetectedProfileImage: ((URL?) -> Void)?,
            onPageTitle: ((String?) -> Void)?,
            onMediaRequest: ((MediaRequest) -> Void)?,
            onUnreadNotificationCountChanged: ((Int, String?) -> Void)?,
            enableHandleDetection: Bool,
            onPageReadyScript: String?
        ) {
            self.onNavigation = onNavigation
            self.onDetectedHandle = onDetectedHandle
            self.onDetectedProfileImage = onDetectedProfileImage
            self.onPageTitle = onPageTitle
            self.onMediaRequest = onMediaRequest
            self.onUnreadNotificationCountChanged = onUnreadNotificationCountChanged
            self.enableHandleDetection = enableHandleDetection
            self.onPageReadyScript = onPageReadyScript
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onNavigation?(webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigation?(webView.url)
            onPageTitle?(webView.title)
            applyFilter(to: webView)
            if let onPageReadyScript {
                webView.evaluateJavaScript(onPageReadyScript)
            }
            if enableHandleDetection {
                detectProfileMeta(in: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let targetURL = navigationAction.request.url {
                webView.load(URLRequest(url: targetURL))
            }
            return nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == Self.mediaMessageName {
                guard let payload = message.body as? [String: Any],
                      let rawKind = payload["kind"] as? String,
                      let kind = MediaKind(rawValue: rawKind),
                      let rawURL = payload["url"] as? String,
                      let parsed = URL(string: rawURL) else {
                    return
                }

                let currentTime = (payload["currentTime"] as? NSNumber)?.doubleValue
                let mediaURL = (payload["mediaURL"] as? String).flatMap(URL.init(string:))
                onMediaRequest?(MediaRequest(kind: kind, url: parsed, currentTime: currentTime, mediaURL: mediaURL))
                return
            }

            if message.name == Self.unreadCountMessageName {
                guard let payload = message.body as? [String: Any],
                      let count = (payload["count"] as? NSNumber)?.intValue else {
                    return
                }
                let activity = (payload["activity"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                onUnreadNotificationCountChanged?(count, activity?.isEmpty == true ? nil : activity)
            }
        }

        func applyFilter(to webView: WKWebView) {
            guard filter.hasRules else {
                webView.evaluateJavaScript("window.__xflowClearFilter && window.__xflowClearFilter();")
                return
            }

            let include = encodeCSV(filter.includeKeywords)
            let exclude = encodeCSV(filter.excludeKeywords)
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

        private func encodeCSV(_ value: String?) -> String {
            guard let value, !value.isEmpty else {
                return "''"
            }

            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: " ")

            return "'\(escaped)'"
        }
    }
}
