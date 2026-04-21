import Foundation

enum XSidebarAction: String, CaseIterable, Identifiable {
    case home
    case search
    case notifications
    case messages
    case grok
    case premium
    case bookmarks
    case creatorStudio
    case articles
    case profile
    case more
    case compose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .search:
            return "Search"
        case .notifications:
            return "Notifications"
        case .messages:
            return "Direct Messages"
        case .grok:
            return "Grok"
        case .premium:
            return "Premium"
        case .bookmarks:
            return "Bookmarks"
        case .creatorStudio:
            return "Lists"
        case .articles:
            return "Articles"
        case .profile:
            return "Profile"
        case .more:
            return "More"
        case .compose:
            return "Compose"
        }
    }

    var symbolName: String {
        switch self {
        case .home:
            return "house"
        case .search:
            return "magnifyingglass"
        case .notifications:
            return "bell"
        case .messages:
            return "envelope"
        case .grok:
            return "sparkles"
        case .premium:
            return "checkmark.seal"
        case .bookmarks:
            return "bookmark"
        case .creatorStudio:
            return "pencil.and.list.clipboard"
        case .articles:
            return "doc.text"
        case .profile:
            return "person"
        case .more:
            return "ellipsis.circle"
        case .compose:
            return "square.and.pencil"
        }
    }

    func url(forHandle handle: String?) -> URL? {
        switch self {
        case .home:
            return URL(string: "https://x.com/home")
        case .search:
            return URL(string: "https://x.com/explore")
        case .notifications:
            return URL(string: "https://x.com/notifications")
        case .messages:
            return URL(string: "https://x.com/messages")
        case .grok:
            return URL(string: "https://x.com/i/grok")
        case .premium:
            return URL(string: "https://x.com/settings/premium")
        case .bookmarks:
            return URL(string: "https://x.com/i/bookmarks")
        case .creatorStudio:
            return URL(string: "https://x.com/i/lists")
        case .articles:
            return URL(string: "https://help.x.com/en/using-x/articles")
        case .profile:
            let cleaned = (handle ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "@", with: "")
            return URL(string: cleaned.isEmpty ? "https://x.com/i/profile" : "https://x.com/\(cleaned)")
        case .more:
            return URL(string: "https://x.com/settings")
        case .compose:
            return URL(string: "https://x.com/compose/post")
        }
    }
}

struct QuickPanelDestination: Identifiable {
    let id = UUID()
    let action: XSidebarAction
    let url: URL
}
