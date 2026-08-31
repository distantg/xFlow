import Foundation

enum MediaKind: String {
    case image
    case video
    case link
}

struct MediaRequest: Identifiable {
    let id = UUID()
    let kind: MediaKind
    let url: URL
    let currentTime: Double?
    let mediaURL: URL?

    init(kind: MediaKind, url: URL, currentTime: Double?, mediaURL: URL?) {
        self.kind = kind
        self.url = url
        self.currentTime = currentTime

        if kind == .image {
            self.mediaURL = XMediaURLResolver.originalImageURL(from: mediaURL ?? url)
        } else {
            self.mediaURL = mediaURL
        }
    }

    static func validatedBridgeRequest(
        kind: MediaKind,
        url: URL,
        currentTime: Double?,
        mediaURL: URL?
    ) -> MediaRequest? {
        let safeTime = currentTime.flatMap { value -> Double? in
            guard value.isFinite, value >= 0, value <= 24 * 60 * 60 else {
                return nil
            }
            return value
        }

        switch kind {
        case .image:
            guard TrustedURLPolicy.isTrustedImageMediaURL(url) else {
                return nil
            }
            let candidate = mediaURL ?? url
            guard TrustedURLPolicy.isTrustedImageMediaURL(candidate) else {
                return nil
            }
            return MediaRequest(kind: kind, url: url, currentTime: safeTime, mediaURL: candidate)

        case .video:
            guard TrustedURLPolicy.isTrustedXPage(url) else {
                return nil
            }
            let trustedMediaURL = mediaURL.flatMap {
                TrustedURLPolicy.isTrustedVideoMediaURL($0) ? $0 : nil
            }
            return MediaRequest(kind: kind, url: url, currentTime: safeTime, mediaURL: trustedMediaURL)

        case .link:
            guard TrustedURLPolicy.isTrustedXPage(url) else {
                return nil
            }
            return MediaRequest(kind: kind, url: url, currentTime: safeTime, mediaURL: nil)
        }
    }
}

enum XMediaURLResolver {
    static func originalImageURL(from url: URL) -> URL {
        guard TrustedURLPolicy.isTrustedImageMediaURL(url),
              url.path.hasPrefix("/media/"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        var replacedName = false
        queryItems = queryItems.compactMap { item in
            guard item.name.lowercased() == "name" else {
                return item
            }
            guard !replacedName else {
                return nil
            }
            replacedName = true
            return URLQueryItem(name: "name", value: "orig")
        }

        if !replacedName {
            queryItems.append(URLQueryItem(name: "name", value: "orig"))
        }

        components.queryItems = queryItems
        return components.url ?? url
    }
}
