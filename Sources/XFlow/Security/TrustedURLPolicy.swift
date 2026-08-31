import Foundation

enum TrustedURLPolicy {
    private static let xWebHosts: Set<String> = ["x.com", "www.x.com"]
    private static let updateManifestHost = "raw.githubusercontent.com"
    private static let releaseHost = "github.com"

    static func isTrustedXPage(_ url: URL) -> Bool {
        guard isHTTPSURLWithoutCredentials(url),
              let host = normalizedHost(of: url) else {
            return false
        }
        return xWebHosts.contains(host)
    }

    static func isTrustedXOrigin(scheme: String, host: String, port: Int) -> Bool {
        guard scheme.lowercased() == "https",
              xWebHosts.contains(host.lowercased()) else {
            return false
        }
        return port == 0 || port == 443
    }

    static func isTrustedImageMediaURL(_ url: URL) -> Bool {
        guard isHTTPSURLWithoutCredentials(url),
              normalizedHost(of: url) == "pbs.twimg.com" else {
            return false
        }
        return url.path.hasPrefix("/media/")
    }

    static func isTrustedProfileImageURL(_ url: URL) -> Bool {
        guard isHTTPSURLWithoutCredentials(url),
              let host = normalizedHost(of: url) else {
            return false
        }

        if host == "pbs.twimg.com" {
            return url.path.hasPrefix("/profile_images/")
        }

        return xWebHosts.contains(host) && url.path.hasSuffix("/profile_image")
    }

    static func isTrustedVideoMediaURL(_ url: URL) -> Bool {
        guard isHTTPSURLWithoutCredentials(url),
              normalizedHost(of: url) == "video.twimg.com" else {
            return false
        }
        return !url.path.isEmpty
    }

    static func isTrustedExternalWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.user == nil,
              url.password == nil,
              let host = normalizedHost(of: url),
              !host.isEmpty else {
            return false
        }
        return !xWebHosts.contains(host)
    }

    static func isSafeSubframeURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        switch scheme {
        case "https":
            return isHTTPSURLWithoutCredentials(url) && normalizedHost(of: url) != nil
        case "about":
            return url.absoluteString == "about:blank"
        case "blob":
            // WebKit binds blob URLs to their creator's security origin.
            return true
        default:
            return false
        }
    }

    static func isTrustedUpdateManifestURL(_ url: URL) -> Bool {
        guard isHTTPSURLWithoutCredentials(url),
              normalizedHost(of: url) == updateManifestHost else {
            return false
        }
        return url.path == "/distantg/xFlow/main/update-manifest.json"
    }

    static func isTrustedGitHubReleaseURL(_ url: URL) -> Bool {
        guard isHTTPSURLWithoutCredentials(url),
              normalizedHost(of: url) == releaseHost else {
            return false
        }

        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 5,
              components[0].lowercased() == "distantg",
              components[1].lowercased() == "xflow",
              components[2].lowercased() == "releases" else {
            return false
        }

        return components[3].lowercased() == "tag" || components[3].lowercased() == "download"
    }

    static func isValidXHandle(_ value: String) -> Bool {
        let candidate = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        guard (1...15).contains(candidate.count) else {
            return false
        }
        return candidate.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
                .contains($0)
        }
    }

    static func isTrustedXListURL(_ url: URL) -> Bool {
        guard isTrustedXPage(url) else {
            return false
        }

        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if segments.count == 3,
           segments[0].lowercased() == "i",
           segments[1].lowercased() == "lists" {
            return isValidListIdentifier(segments[2])
        }

        if segments.count == 3,
           isValidXHandle(segments[0]),
           segments[1].lowercased() == "lists" {
            return isValidListIdentifier(segments[2])
        }

        return segments.count == 2 &&
            segments[0].lowercased() == "i" &&
            segments[1].lowercased() == "lists"
    }

    private static func isValidListIdentifier(_ value: String) -> Bool {
        guard (1...100).contains(value.count) else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
                .contains($0)
        }
    }

    private static func isHTTPSURLWithoutCredentials(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil else {
            return false
        }
        return url.port == nil || url.port == 443
    }

    private static func normalizedHost(of url: URL) -> String? {
        url.host?.lowercased()
    }
}

final class RejectRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum JavaScriptEncoding {
    static func stringLiteral(_ value: String?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }
}

enum HTMLEncoding {
    static func attributeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
