import Foundation
import WebKit

struct DeckAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var fallbackName: String
    var handle: String?
    var profileImageURL: String?
    var requiresLogin: Bool

    init(
        id: UUID = UUID(),
        fallbackName: String,
        handle: String? = nil,
        profileImageURL: String? = nil,
        requiresLogin: Bool = true
    ) {
        self.id = id
        self.fallbackName = fallbackName
        let normalizedHandle = handle?.normalizedHandle
        self.handle = normalizedHandle.flatMap {
            TrustedURLPolicy.isValidXHandle($0) ? $0 : nil
        }
        self.profileImageURL = profileImageURL.flatMap(Self.validatedProfileImageString)
        self.requiresLogin = requiresLogin
    }

    var name: String {
        if let handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return fallbackName
    }

    var shortLabel: String {
        if let handle, !handle.isEmpty {
            return "@\(handle.prefix(2).uppercased())"
        }

        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }
        if !initials.isEmpty {
            return String(initials)
        }
        return String(name.prefix(2)).uppercased()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fallbackName
        case handle
        case profileImageURL
        case requiresLogin
        case legacyName = "name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fallbackName = try container.decodeIfPresent(String.self, forKey: .fallbackName)
            ?? container.decodeIfPresent(String.self, forKey: .legacyName)
            ?? "Account"
        let decodedHandle = try container.decodeIfPresent(String.self, forKey: .handle)?.normalizedHandle
        handle = decodedHandle.flatMap { TrustedURLPolicy.isValidXHandle($0) ? $0 : nil }
        profileImageURL = try container
            .decodeIfPresent(String.self, forKey: .profileImageURL)
            .flatMap(Self.validatedProfileImageString)
        requiresLogin = try container.decodeIfPresent(Bool.self, forKey: .requiresLogin) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fallbackName, forKey: .fallbackName)
        try container.encodeIfPresent(handle?.normalizedHandle, forKey: .handle)
        try container.encodeIfPresent(profileImageURL, forKey: .profileImageURL)
        try container.encode(requiresLogin, forKey: .requiresLogin)
    }

    private static func validatedProfileImageString(_ rawValue: String) -> String? {
        guard let url = URL(string: rawValue),
              TrustedURLPolicy.isTrustedProfileImageURL(url) else {
            return nil
        }
        return url.absoluteString
    }
}

private extension String {
    var normalizedHandle: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .removingPrefix("@")
            .lowercased()
    }

    func removingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }
        return String(dropFirst(prefix.count))
    }
}

@MainActor
final class WebSessionPool {
    static let shared = WebSessionPool()

    private var stores: [UUID: WKWebsiteDataStore] = [:]
    private var profileProbes: [UUID: ProfileMetaProbe] = [:]
    private var pendingProfileMetaCallbacks: [UUID: [(AccountProfileMeta?) -> Void]] = [:]
    private let pendingStorePurgeKey = "xflow.pendingWebsiteDataStorePurges.v1"

    private init() {
        retryPendingStorePurges()
    }

    func configuration(for accountID: UUID) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore(for: accountID)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        return configuration
    }

    func appearsAuthenticated(accountID: UUID, completion: @escaping (Bool) -> Void) {
        dataStore(for: accountID).httpCookieStore.getAllCookies { cookies in
            // auth_token is the reliable signal for an authenticated X web session.
            let isAuthenticated = cookies.contains { cookie in
                cookie.name.lowercased() == "auth_token" &&
                    Self.isCookieApplicableToXHome(cookie)
            }

            DispatchQueue.main.async {
                completion(isAuthenticated)
            }
        }
    }

    func fetchProfileMeta(accountID: UUID, completion: @escaping (AccountProfileMeta?) -> Void) {
        if pendingProfileMetaCallbacks[accountID] != nil {
            pendingProfileMetaCallbacks[accountID, default: []].append(completion)
            return
        }

        pendingProfileMetaCallbacks[accountID] = [completion]

        appearsAuthenticated(accountID: accountID) { [weak self] authenticated in
            guard let self else { return }
            guard authenticated else {
                self.finishProfileMetaFetch(for: accountID, meta: nil)
                return
            }

            self.fetchProfileMetaFromHTML(accountID: accountID) { [weak self] htmlMeta in
                guard let self else { return }
                if let htmlMeta, !htmlMeta.isEmpty {
                    self.finishProfileMetaFetch(for: accountID, meta: htmlMeta)
                    return
                }

                let probe = ProfileMetaProbe(
                    configuration: self.configuration(for: accountID),
                    completion: { [weak self] meta in
                        guard let self else { return }
                        self.finishProfileMetaFetch(for: accountID, meta: meta)
                    }
                )

                self.profileProbes[accountID] = probe
                probe.start()
            }
        }
    }

    func purgeAccount(_ accountID: UUID) {
        profileProbes.removeValue(forKey: accountID)?.cancel()
        pendingProfileMetaCallbacks.removeValue(forKey: accountID)
        let store = stores.removeValue(forKey: accountID)

        store?.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { }

        if #available(macOS 14.0, *) {
            // SwiftUI releases the account's visible web views on the next render pass.
            markStorePurgePending(accountID)
            schedulePersistentStoreRemoval(accountID, delay: 1)
        }
    }

    private func retryPendingStorePurges() {
        guard #available(macOS 14.0, *) else {
            return
        }

        let identifiers = UserDefaults.standard
            .stringArray(forKey: pendingStorePurgeKey)?
            .compactMap(UUID.init(uuidString:)) ?? []
        identifiers.forEach { schedulePersistentStoreRemoval($0, delay: 0.25) }
    }

    private func markStorePurgePending(_ accountID: UUID) {
        var identifiers = Set(UserDefaults.standard.stringArray(forKey: pendingStorePurgeKey) ?? [])
        identifiers.insert(accountID.uuidString)
        UserDefaults.standard.set(identifiers.sorted(), forKey: pendingStorePurgeKey)
    }

    private func clearPendingStorePurge(_ accountID: UUID) {
        var identifiers = Set(UserDefaults.standard.stringArray(forKey: pendingStorePurgeKey) ?? [])
        identifiers.remove(accountID.uuidString)
        if identifiers.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingStorePurgeKey)
        } else {
            UserDefaults.standard.set(identifiers.sorted(), forKey: pendingStorePurgeKey)
        }
    }

    @available(macOS 14.0, *)
    private func schedulePersistentStoreRemoval(
        _ accountID: UUID,
        delay: TimeInterval,
        attempt: Int = 0
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            WKWebsiteDataStore.remove(forIdentifier: accountID) { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if error == nil {
                        self.clearPendingStorePurge(accountID)
                    } else if attempt < 3 {
                        self.schedulePersistentStoreRemoval(
                            accountID,
                            delay: pow(2, Double(attempt)),
                            attempt: attempt + 1
                        )
                    }
                }
            }
        }
    }

    private func dataStore(for accountID: UUID) -> WKWebsiteDataStore {
        if let existing = stores[accountID] {
            return existing
        }

        let created: WKWebsiteDataStore
        if #available(macOS 14.0, *) {
            created = WKWebsiteDataStore(forIdentifier: accountID)
        } else {
            created = WKWebsiteDataStore.nonPersistent()
        }

        stores[accountID] = created
        return created
    }

    private func fetchProfileMetaFromHTML(
        accountID: UUID,
        completion: @escaping (AccountProfileMeta?) -> Void
    ) {
        let cookieStore = dataStore(for: accountID).httpCookieStore
        cookieStore.getAllCookies { cookies in
            let xCookies = cookies.filter { Self.isCookieApplicableToXHome($0) }

            guard !xCookies.isEmpty else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            var request = URLRequest(url: URL(string: "https://x.com/home")!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 5
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

            for (key, value) in HTTPCookie.requestHeaderFields(with: xCookies) {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 6

            let redirectDelegate = RejectRedirectURLSessionDelegate()
            let session = URLSession(
                configuration: configuration,
                delegate: redirectDelegate,
                delegateQueue: nil
            )

            session.dataTask(with: request) { data, response, _ in
                defer { session.finishTasksAndInvalidate() }

                let responseIsTrusted = (response as? HTTPURLResponse).map { response in
                    (200...299).contains(response.statusCode) &&
                        response.url.map(TrustedURLPolicy.isTrustedXPage) == true
                } ?? false

                let parsed: AccountProfileMeta?
                if responseIsTrusted,
                   let data,
                   data.count <= 2 * 1024 * 1024,
                   let html = String(data: data, encoding: .utf8) {
                    parsed = Self.parseProfileMetaFromHTML(html)
                } else {
                    parsed = nil
                }

                DispatchQueue.main.async {
                    completion(parsed)
                }
            }.resume()
        }
    }

    private func finishProfileMetaFetch(for accountID: UUID, meta: AccountProfileMeta?) {
        profileProbes.removeValue(forKey: accountID)
        let callbacks = pendingProfileMetaCallbacks.removeValue(forKey: accountID) ?? []
        callbacks.forEach { $0(meta) }
    }

    struct AccountProfileMeta {
        let handle: String?
        let profileImageURL: URL?

        var isEmpty: Bool {
            (handle?.isEmpty != false) && profileImageURL == nil
        }
    }

    nonisolated private static func parseProfileMetaFromHTML(_ html: String) -> AccountProfileMeta? {
        let handlePatterns = [
            #""screen_name":"([A-Za-z0-9_]{1,15})""#,
            #""screenName":"([A-Za-z0-9_]{1,15})""#,
            #""profile_screen_name":"([A-Za-z0-9_]{1,15})""#
        ]

        let avatarPatterns = [
            #""profile_image_url_https":"([^"]+)""#,
            #""avatar_image_url":"([^"]+)""#,
            #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#
        ]

        let handle = handlePatterns
            .compactMap { firstRegexCapture(in: html, pattern: $0) }
            .map { $0.normalizedHandle }
            .first(where: TrustedURLPolicy.isValidXHandle)

        let rawAvatar = avatarPatterns
            .compactMap { firstRegexCapture(in: html, pattern: $0) }
            .first
            ?? firstRegexCapture(
                in: html,
                pattern: #"(https:\\/\\/pbs\.twimg\.com\\/profile_images\\/[^"\\]+)"#
            )

        let decodedAvatar = rawAvatar
            .flatMap { decodeEscapedWebValue($0) }
            .flatMap { value -> String? in
                if value.hasPrefix("//") {
                    return "https:\(value)"
                }
                if value.hasPrefix("http://") || value.hasPrefix("https://") {
                    return value
                }
                return nil
            }

        let avatarURL = decodedAvatar
            .flatMap(URL.init(string:))
            .flatMap { TrustedURLPolicy.isTrustedProfileImageURL($0) ? $0 : nil }

        if handle == nil && avatarURL == nil {
            return nil
        }

        return AccountProfileMeta(handle: handle, profileImageURL: avatarURL)
    }

    nonisolated private static func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[valueRange])
    }

    nonisolated private static func decodeEscapedWebValue(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    nonisolated static func isCookieApplicableToXHome(
        _ cookie: HTTPCookie,
        now: Date = Date()
    ) -> Bool {
        guard cookie.isSecure,
              cookie.expiresDate.map({ $0 > now }) ?? true else {
            return false
        }

        var domain = cookie.domain.lowercased()
        while domain.hasPrefix(".") {
            domain.removeFirst()
        }
        guard domain == "x.com" else {
            return false
        }

        let requestPath = "/home"
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        if cookiePath == "/" || requestPath == cookiePath {
            return true
        }
        guard requestPath.hasPrefix(cookiePath) else {
            return false
        }
        if cookiePath.hasSuffix("/") {
            return true
        }
        let boundary = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
        return boundary < requestPath.endIndex && requestPath[boundary] == "/"
    }

    private final class ProfileMetaProbe: NSObject, WKNavigationDelegate {
        private static let extractionScript = """
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

            const profileLink = document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
            if (profileLink) {
              const found = normalize(profileLink.getAttribute('href') || '');
              const profileImage = profileLink.querySelector('img');
              if (!avatarCandidate && profileImage && profileImage.src) avatarCandidate = profileImage.src;
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

            if (!handleCandidate) {
              const profileLocation = normalize(window.location.pathname || '');
              if (profileLocation) handleCandidate = profileLocation;
            }

            if (!handleCandidate) {
              const allAnchors = Array.from(document.querySelectorAll('a[href^="/"]'));
              for (const anchor of allAnchors) {
                const found = normalize(anchor.getAttribute('href') || '');
                if (!found) continue;
                const text = (anchor.textContent || '').trim().toLowerCase();
                const aria = (anchor.getAttribute('aria-label') || '').trim().toLowerCase();
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

            if (!avatarCandidate) {
              const ogImage = document.querySelector('meta[property="og:image"]');
              if (ogImage && ogImage.content) avatarCandidate = ogImage.content;
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
              if ((result.handle && result.handle.length > 0) || (result.avatar && result.avatar.length > 0) || attempts >= 25) {
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

        private let webView: WKWebView
        private let completion: (AccountProfileMeta?) -> Void
        private var isFinished = false
        private var timeoutWorkItem: DispatchWorkItem?

        init(configuration: WKWebViewConfiguration, completion: @escaping (AccountProfileMeta?) -> Void) {
            self.webView = WKWebView(frame: .zero, configuration: configuration)
            self.completion = completion
            super.init()
            webView.navigationDelegate = self
        }

        func start() {
            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(with: nil)
            }
            timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5, execute: timeout)
            webView.load(URLRequest(url: URL(string: "https://x.com/home")!))
        }

        func cancel() {
            finish(with: nil)
        }

        nonisolated func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor [weak self] in
                self?.finish(with: nil)
            }
        }

        nonisolated func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor [weak self] in
                self?.finish(with: nil)
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

            let isAllowed = TrustedURLPolicy.isTrustedXPage(url) || url.absoluteString == "about:blank"
            decisionHandler(isAllowed ? .allow : .cancel)
        }

        @MainActor
        private func handleDidFinish(_ webView: WKWebView) {
            guard webView.url.map(TrustedURLPolicy.isTrustedXPage) == true else {
                finish(with: nil)
                return
            }

            webView.evaluateJavaScript(Self.extractionScript) { [weak self] result, _ in
                guard let self else { return }
                guard let payload = result as? String,
                      let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.finish(with: nil)
                    return
                }

                let normalizedHandle = (json["handle"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .normalizedHandle
                let handle = normalizedHandle.flatMap {
                    TrustedURLPolicy.isValidXHandle($0) ? $0 : nil
                }

                let avatarRaw = (json["avatar"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let avatarURL = avatarRaw
                    .flatMap { $0.isEmpty ? nil : URL(string: $0) }
                    .flatMap { TrustedURLPolicy.isTrustedProfileImageURL($0) ? $0 : nil }

                if (handle == nil || handle?.isEmpty == true) && avatarURL == nil {
                    self.finish(with: nil)
                    return
                }

                self.finish(with: AccountProfileMeta(
                    handle: (handle?.isEmpty == true ? nil : handle),
                    profileImageURL: avatarURL
                ))
            }
        }

        private func finish(with meta: AccountProfileMeta?) {
            guard !isFinished else {
                return
            }
            isFinished = true
            timeoutWorkItem?.cancel()
            webView.stopLoading()
            webView.navigationDelegate = nil
            completion(meta)
        }
    }
}
