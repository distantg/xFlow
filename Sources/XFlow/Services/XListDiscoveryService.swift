import Foundation
import AppKit
import WebKit

struct XListChoice: Identifiable, Equatable {
    let name: String
    let url: URL

    var id: String { url.absoluteString }
}

enum XListDiscoveryError: LocalizedError, Equatable {
    case notAuthenticated
    case loadFailed
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to the active X account to load its Lists."
        case .loadFailed:
            return "Mosaic couldn’t load Lists from the active X account."
        case .timedOut:
            return "X took too long to return the active account’s Lists."
        case .cancelled:
            return "List loading was cancelled."
        }
    }
}

@MainActor
final class XListDiscoveryService {
    static let shared = XListDiscoveryService()

    typealias Completion = (Result<[XListChoice], XListDiscoveryError>) -> Void

    private var probes: [UUID: ListProbe] = [:]
    private var pendingCallbacks: [UUID: [Completion]] = [:]

    private init() {}

    func fetchLists(
        for accountID: UUID,
        handle: String?,
        completion: @escaping Completion
    ) {
        guard let indexURL = Self.listsIndexURL(forHandle: handle) else {
            completion(.failure(.loadFailed))
            return
        }

        if pendingCallbacks[accountID] != nil {
            pendingCallbacks[accountID, default: []].append(completion)
            return
        }

        pendingCallbacks[accountID] = [completion]

        WebSessionPool.shared.appearsAuthenticated(accountID: accountID) { [weak self] authenticated in
            guard let self, self.pendingCallbacks[accountID] != nil else { return }
            guard authenticated else {
                self.finish(accountID: accountID, result: .failure(.notAuthenticated))
                return
            }

            let probe = ListProbe(
                configuration: WebSessionPool.shared.configuration(for: accountID),
                indexURL: indexURL,
                completion: { [weak self] result in
                    self?.finish(accountID: accountID, result: result)
                }
            )
            self.probes[accountID] = probe
            probe.start()
        }
    }

    func cancel(for accountID: UUID) {
        pendingCallbacks.removeValue(forKey: accountID)
        probes.removeValue(forKey: accountID)?.cancel()
    }

    private func finish(
        accountID: UUID,
        result: Result<[XListChoice], XListDiscoveryError>
    ) {
        probes.removeValue(forKey: accountID)
        let callbacks = pendingCallbacks.removeValue(forKey: accountID) ?? []
        callbacks.forEach { $0(result) }
    }

    nonisolated static func listsIndexURL(forHandle handle: String?) -> URL? {
        guard let handle = handle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
              TrustedURLPolicy.isValidXHandle(handle) else {
            return nil
        }

        return URL(string: "https://x.com/\(handle)/lists")
    }

    nonisolated static let extractionScript = """
    (function() {
      const choices = new Map();

      function cleanLines(value) {
        return String(value || '')
          .split(/\\n+/)
          .map(line => line.replace(/\\s+/g, ' ').trim())
          .filter(Boolean);
      }

      function displayName(anchor, path) {
        const cell = anchor.closest('[data-testid="cellInnerDiv"]') || anchor;
        const candidates = [
          anchor.getAttribute('aria-label'),
          anchor.getAttribute('title'),
          anchor.innerText,
          cell.innerText
        ];

        for (const candidate of candidates) {
          const line = cleanLines(candidate).find(value => {
            const lower = value.toLowerCase();
            return !value.startsWith('@') &&
              !/^\\d[\\d,.]*\\s+(members?|followers?)$/i.test(value) &&
              lower !== 'pinned lists' && lower !== 'your lists' &&
              lower !== 'lists' && lower !== 'show more';
          });
          if (line) return line.slice(0, 120);
        }

        const identifier = path.split('/').filter(Boolean).pop() || '';
        return identifier ? `List ${identifier}` : 'X List';
      }

      const yourListsHeadings = Array.from(
        document.querySelectorAll('[role="heading"],h1,h2,h3')
      ).filter(heading => cleanLines(heading.innerText).join(' ').toLowerCase() === 'your lists');
      const yourListsHeading = yourListsHeadings[yourListsHeadings.length - 1];

      document.querySelectorAll('a[href]').forEach(anchor => {
        if (!yourListsHeading) return;
        const relation = yourListsHeading.compareDocumentPosition(anchor);
        if (!(relation & Node.DOCUMENT_POSITION_FOLLOWING)) return;

        let parsed;
        try {
          parsed = new URL(anchor.getAttribute('href') || '', window.location.href);
        } catch (_) {
          return;
        }

        const host = parsed.hostname.toLowerCase();
        if (parsed.protocol !== 'https:' || (host !== 'x.com' && host !== 'www.x.com')) return;

        const path = parsed.pathname.replace(/\\/+$/, '');
        const canonical = /^\\/i\\/lists\\/[A-Za-z0-9_-]{1,100}$/.test(path);
        const legacy = /^\\/[A-Za-z0-9_]{1,15}\\/lists\\/[A-Za-z0-9_-]{1,100}$/.test(path);
        if (!canonical && !legacy) return;

        const identifier = path.split('/').filter(Boolean).pop().toLowerCase();
        if (['create', 'suggested', 'members', 'followers'].includes(identifier)) return;

        const url = `https://x.com${path}`;
        if (!choices.has(url)) {
          choices.set(url, { name: displayName(anchor, path), url });
        }
      });

      function reactListPath(cell) {
        const fiberKey = Object.keys(cell).find(key => key.indexOf('__reactFiber$') === 0);
        let fiber = fiberKey ? cell[fiberKey] : null;

        for (let index = 0; fiber && index < 8; index += 1, fiber = fiber.return) {
          const props = fiber.memoizedProps;
          const link = props && props.link;
          const pathname = typeof link === 'string' ? link : link && link.pathname;
          if (typeof pathname === 'string' && /^\\/i\\/lists\\/\\d{8,30}$/.test(pathname)) {
            return pathname;
          }
        }
        return '';
      }

      document.querySelectorAll('[data-testid="listCell"][role="link"]').forEach(cell => {
        if (!yourListsHeading) return;
        const relation = yourListsHeading.compareDocumentPosition(cell);
        if (!(relation & Node.DOCUMENT_POSITION_FOLLOWING)) return;

        const path = reactListPath(cell);
        if (!path) return;

        const url = `https://x.com${path}`;
        if (!choices.has(url)) {
          choices.set(url, { name: displayName(cell, path), url });
        }
      });

      const root = document.scrollingElement || document.documentElement;
      if (root) {
        const viewport = Math.max(Number(window.innerHeight) || 0, 640);
        const maximum = Math.max(0, (root.scrollHeight || 0) - (root.clientHeight || viewport));
        root.scrollTop = Math.min(maximum, root.scrollTop + Math.round(viewport * 0.82));
      }

      return JSON.stringify(Array.from(choices.values()));
    })();
    """

    nonisolated static func parseListPayload(_ payload: String) -> [XListChoice]? {
        guard let data = payload.data(using: .utf8), data.count <= 512 * 1024,
              let rawChoices = try? JSONDecoder().decode([RawListChoice].self, from: data) else {
            return nil
        }

        var seenPaths = Set<String>()
        var choices: [XListChoice] = []

        for rawChoice in rawChoices.prefix(200) {
            guard let candidate = URL(string: rawChoice.url),
                  TrustedURLPolicy.isTrustedXListURL(candidate) else {
                continue
            }

            let segments = candidate.path.split(separator: "/", omittingEmptySubsequences: true)
            guard segments.count == 3 else {
                continue
            }
            let identifier = segments[2].lowercased()
            guard !["create", "suggested", "members", "followers"].contains(identifier) else {
                continue
            }

            var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            components?.host = "x.com"
            components?.port = nil
            components?.user = nil
            components?.password = nil
            components?.query = nil
            components?.fragment = nil

            guard let canonicalURL = components?.url else {
                continue
            }

            let pathKey = canonicalURL.path.lowercased()
            guard seenPaths.insert(pathKey).inserted else {
                continue
            }

            let cleanedName = rawChoice.name
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
            let fallbackID = canonicalURL.path.split(separator: "/").last.map(String.init) ?? ""
            let displayName = String((cleanedName ?? "List \(fallbackID)").prefix(120))

            choices.append(XListChoice(name: displayName, url: canonicalURL))
        }

        return choices
    }

    private struct RawListChoice: Decodable {
        let name: String
        let url: String
    }

    private final class ListProbe: NSObject, WKNavigationDelegate {
        private let webView: WKWebView
        private let hostWindow: NSWindow
        private let indexURL: URL
        private let completion: Completion
        private var isFinished = false
        private var hasStartedExtraction = false
        private var timeoutWorkItem: DispatchWorkItem?
        private var collectionAttempt = 0
        private var unchangedPasses = 0
        private var choicesByID: [String: XListChoice] = [:]
        private var orderedChoiceIDs: [String] = []

        init(
            configuration: WKWebViewConfiguration,
            indexURL: URL,
            completion: @escaping Completion
        ) {
            webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 900, height: 900),
                configuration: configuration
            )
            hostWindow = NSWindow(
                contentRect: CGRect(x: -10_000, y: -10_000, width: 900, height: 900),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            self.indexURL = indexURL
            self.completion = completion
            super.init()
            webView.navigationDelegate = self
            hostWindow.contentView = webView
            hostWindow.isReleasedWhenClosed = false
            hostWindow.ignoresMouseEvents = true
            hostWindow.collectionBehavior = [.transient, .ignoresCycle]
        }

        func start() {
            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(with: .failure(.timedOut))
            }
            timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)

            hostWindow.orderBack(nil)
            var request = URLRequest(url: indexURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 11
            webView.load(request)
        }

        func cancel() {
            finish(with: .failure(.cancelled))
        }

        nonisolated func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor [weak self] in
                self?.finish(with: .failure(.loadFailed))
            }
        }

        nonisolated func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor [weak self] in
                self?.finish(with: .failure(.loadFailed))
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.handleDidFinish(webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame?.isMainFrame == false {
                decisionHandler(TrustedURLPolicy.isSafeSubframeURL(url) ? .allow : .cancel)
                return
            }

            let allowed = TrustedURLPolicy.isTrustedXPage(url) || url.absoluteString == "about:blank"
            decisionHandler(allowed ? .allow : .cancel)
        }

        private func handleDidFinish(_ webView: WKWebView) {
            guard !hasStartedExtraction else { return }

            guard let url = webView.url, TrustedURLPolicy.isTrustedXPage(url) else {
                finish(with: .failure(.loadFailed))
                return
            }

            if url.path.hasPrefix("/i/flow/login") || url.path.hasPrefix("/login") {
                finish(with: .failure(.notAuthenticated))
                return
            }

            hasStartedExtraction = true
            collectLists()
        }

        private func collectLists() {
            guard !isFinished else { return }

            webView.evaluateJavaScript(XListDiscoveryService.extractionScript) { [weak self] result, _ in
                guard let self, !self.isFinished else { return }
                guard let payload = result as? String,
                      let batch = XListDiscoveryService.parseListPayload(payload) else {
                    self.finish(with: .failure(.loadFailed))
                    return
                }

                let previousCount = self.choicesByID.count
                for choice in batch {
                    if self.choicesByID[choice.id] == nil {
                        self.orderedChoiceIDs.append(choice.id)
                    }
                    self.choicesByID[choice.id] = choice
                }

                self.collectionAttempt += 1
                self.unchangedPasses = self.choicesByID.count == previousCount
                    ? self.unchangedPasses + 1
                    : 0

                if self.collectionAttempt >= 30 ||
                    (!self.choicesByID.isEmpty &&
                     self.collectionAttempt >= 12 &&
                     self.unchangedPasses >= 4) {
                    let choices = self.orderedChoiceIDs.compactMap { self.choicesByID[$0] }
                    self.finish(with: .success(choices))
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                    self?.collectLists()
                }
            }
        }

        private func finish(with result: Result<[XListChoice], XListDiscoveryError>) {
            guard !isFinished else { return }
            isFinished = true
            timeoutWorkItem?.cancel()
            webView.stopLoading()
            webView.navigationDelegate = nil
            hostWindow.orderOut(nil)
            hostWindow.contentView = nil
            completion(result)
        }
    }
}
