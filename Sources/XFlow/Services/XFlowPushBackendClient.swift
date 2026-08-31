import Foundation

struct XFlowPushBackendClient {
    private let defaults = UserDefaults.standard
    private let endpointDefaultsKey = "xflow.pushBackendURL"
    private let legacyEndpointDefaultsKey = "xdeck.pushBackendURL"

    func syncDeviceMapping(deviceToken: String, accounts: [DeckAccount], activeAccountID: UUID) {
        guard let endpoint = endpointURL(),
              Self.isValidDeviceToken(deviceToken),
              let authorizationToken = backendAuthorizationToken() else {
            return
        }

        let payload = DeviceSyncPayload(
            bundleID: Bundle.main.bundleIdentifier ?? "com.distantg.xflow",
            platform: "macos",
            deviceToken: deviceToken,
            activeAccountID: activeAccountID.uuidString,
            accounts: accounts.map { .init(id: $0.id.uuidString) }
        )
        Task.detached(priority: .utility) {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONEncoder().encode(payload)

                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpShouldSetCookies = false
                configuration.httpCookieStorage = nil
                configuration.urlCredentialStorage = nil
                configuration.urlCache = nil
                configuration.timeoutIntervalForRequest = 10
                configuration.timeoutIntervalForResource = 15
                let redirectDelegate = RejectRedirectURLSessionDelegate()
                let session = URLSession(
                    configuration: configuration,
                    delegate: redirectDelegate,
                    delegateQueue: nil
                )
                defer { session.finishTasksAndInvalidate() }

                let (bytes, response) = try await session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      httpResponse.url == endpoint,
                      response.expectedContentLength < 0 || response.expectedContentLength <= 64 * 1024 else {
                    throw URLError(.badServerResponse)
                }

                var byteCount = 0
                for try await _ in bytes {
                    byteCount += 1
                    guard byteCount <= 64 * 1024 else {
                        throw URLError(.dataLengthExceedsMaximum)
                    }
                }
            } catch {
                NSLog("xFlow push sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func endpointURL() -> URL? {
        if let fromEnvironment = ProcessInfo.processInfo.environment["XFLOW_PUSH_BACKEND_URL"],
           let parsed = Self.validatedEndpointURL(fromEnvironment) {
            return parsed
        }

        if let fromDefaults = defaults.string(forKey: endpointDefaultsKey)
            ?? defaults.string(forKey: legacyEndpointDefaultsKey),
           let parsed = Self.validatedEndpointURL(fromDefaults) {
            return parsed
        }

        return nil
    }

    private func backendAuthorizationToken() -> String? {
        guard let raw = ProcessInfo.processInfo.environment["XFLOW_PUSH_BACKEND_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              (32...512).contains(raw.count),
              !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        return raw
    }

    static func validatedEndpointURL(_ rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        let standardPort = url.port == nil ||
            (scheme == "https" && url.port == 443) ||
            (scheme == "http" && url.port == 80) ||
            (scheme == "http" && Self.isLoopbackHost(host))
        guard standardPort else {
            return nil
        }

        if scheme == "https" {
            return url
        }
        if scheme == "http", Self.isLoopbackHost(host) {
            return url
        }
        return nil
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func isValidDeviceToken(_ token: String) -> Bool {
        guard (64...200).contains(token.count), token.count.isMultiple(of: 2) else {
            return false
        }
        return token.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
    }
}

private struct DeviceSyncPayload: Encodable {
    struct Account: Encodable {
        let id: String
    }

    let bundleID: String
    let platform: String
    let deviceToken: String
    let activeAccountID: String
    let accounts: [Account]
}
