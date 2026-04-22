import Foundation

enum DeckColumnType: String, Codable, CaseIterable, Identifiable {
    case home
    case notifications
    case messages
    case bookmarks
    case explore
    case search
    case profile
    case list

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .home:
            return "Home"
        case .notifications:
            return "Notifications"
        case .messages:
            return "Messages"
        case .bookmarks:
            return "Bookmarks"
        case .explore:
            return "Explore"
        case .search:
            return "Search"
        case .profile:
            return "Profile"
        case .list:
            return "Lists"
        }
    }

    var summary: String {
        switch self {
        case .home:
            return "Main following timeline"
        case .notifications:
            return "Mentions and activity"
        case .messages:
            return "Direct messages"
        case .bookmarks:
            return "Saved posts"
        case .explore:
            return "Trending and discovery"
        case .search:
            return "Live search query"
        case .profile:
            return "Any account timeline"
        case .list:
            return "Custom list stream"
        }
    }

    var parameterPrompt: String? {
        switch self {
        case .search:
            return "Search query"
        case .profile:
            return "Username"
        case .list:
            return "List URL or list ID"
        default:
            return nil
        }
    }

    var parameterPlaceholder: String? {
        switch self {
        case .search:
            return "Enter search term"
        case .profile:
            return "Enter @username"
        case .list:
            return "https://x.com/i/lists/188887"
        default:
            return nil
        }
    }

    var requiresParameter: Bool {
        switch self {
        case .search, .profile, .list:
            return true
        default:
            return false
        }
    }

    func subtitle(for parameter: String?) -> String? {
        let clean = parameter?.trimmed
        switch self {
        case .search:
            return clean
        case .profile:
            guard let clean, !clean.isEmpty else { return nil }
            return "@\(clean.removingPrefix("@"))"
        case .list:
            return clean
        default:
            return nil
        }
    }

    func buildURL(parameter: String?) -> URL {
        switch self {
        case .home:
            return URL(string: "https://x.com/home")!
        case .notifications:
            return URL(string: "https://x.com/notifications")!
        case .messages:
            return URL(string: "https://x.com/messages")!
        case .bookmarks:
            return URL(string: "https://x.com/i/bookmarks")!
        case .explore:
            return URL(string: "https://x.com/explore")!
        case .search:
            return searchURL(query: parameter?.trimmed.nonEmpty)
        case .profile:
            let handle = (parameter?.trimmed.removingPrefix("@") ?? "x").nonEmpty ?? "x"
            return URL(string: "https://x.com/\(handle)")!
        case .list:
            return listURL(parameter: parameter)
        }
    }

    private func searchURL(query: String?) -> URL {
        guard let query else {
            var defaultComponents = URLComponents(string: "https://x.com/search")!
            defaultComponents.queryItems = [
                URLQueryItem(name: "q", value: ""),
                URLQueryItem(name: "src", value: "typed_query")
            ]
            return defaultComponents.url!
        }

        var components = URLComponents(string: "https://x.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "f", value: "live"),
            URLQueryItem(name: "src", value: "typed_query")
        ]
        return components.url!
    }

    private func listURL(parameter: String?) -> URL {
        guard let raw = parameter?.trimmed, !raw.isEmpty else {
            return URL(string: "https://x.com/i/lists")!
        }

        if let direct = URL(string: raw), direct.scheme != nil {
            return direct
        }

        let normalized = raw
            .removingPrefix("https://x.com/")
            .removingPrefix("x.com/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalized.hasPrefix("i/lists/") {
            return URL(string: "https://x.com/\(normalized)")!
        }

        if normalized.allSatisfy({ $0.isNumber }) {
            return URL(string: "https://x.com/i/lists/\(normalized)")!
        }

        return URL(string: "https://x.com/\(normalized)")!
    }
}

struct DeckColumn: Identifiable, Codable, Equatable {
    static let minWidth: Double = 320
    static let maxWidth: Double = 680
    static let defaultWidth: Double = 390

    let id: UUID
    var type: DeckColumnType
    var parameter: String?
    var customTitle: String?
    var width: Double
    var filter: ColumnFilter

    init(
        id: UUID = UUID(),
        type: DeckColumnType,
        parameter: String? = nil,
        customTitle: String? = nil,
        width: Double = DeckColumn.defaultWidth,
        filter: ColumnFilter = .none
    ) {
        self.id = id
        self.type = type
        self.parameter = parameter?.trimmed.nonEmpty
        self.customTitle = customTitle?.trimmed.nonEmpty
        self.width = max(Self.minWidth, min(Self.maxWidth, width))
        self.filter = filter
    }

    var title: String {
        customTitle ?? type.defaultTitle
    }

    var subtitle: String? {
        type.subtitle(for: parameter)
    }

    var url: URL {
        type.buildURL(parameter: parameter)
    }

    static let starterColumns: [DeckColumn] = [
        DeckColumn(type: .home, width: 430),
        DeckColumn(type: .notifications, width: 360),
        DeckColumn(type: .search, parameter: "swiftlang", customTitle: "Swift", width: 360)
    ]
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        trimmed.isEmpty ? nil : trimmed
    }

    func removingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }
        return String(dropFirst(prefix.count))
    }
}
