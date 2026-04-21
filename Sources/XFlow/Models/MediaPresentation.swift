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
}
