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
}

enum XMediaURLResolver {
    static func originalImageURL(from url: URL) -> URL {
        guard url.host?.lowercased() == "pbs.twimg.com",
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
