import AppKit
import ImageIO
import SwiftUI

struct AccountAvatarStorage {
    let directory: URL

    static let shared = AccountAvatarStorage(directory: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("Mosaic/AccountAvatars", isDirectory: true))

    func image(for accountID: UUID) -> NSImage? {
        NSImage(contentsOf: file(for: accountID))
    }

    func save(_ data: Data, for accountID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(for: accountID), options: .atomic)
    }

    func remove(_ accountID: UUID) {
        try? FileManager.default.removeItem(at: file(for: accountID))
    }

    private func file(for accountID: UUID) -> URL {
        directory.appendingPathComponent(accountID.uuidString).appendingPathExtension("png")
    }
}

@MainActor
final class AccountAvatarSession: ObservableObject {
    static let shared = AccountAvatarSession()
    @Published private(set) var revision = 0
    private(set) var signedOut: Set<String>
    private let storage: AccountAvatarStorage
    private let defaults: UserDefaults

    init(storage: AccountAvatarStorage = .shared, defaults: UserDefaults = .standard) {
        self.storage = storage
        self.defaults = defaults
        signedOut = Set(defaults.stringArray(forKey: "mosaic.avatarSignedOut") ?? [])
    }

    func setAuthenticated(_ authenticated: Bool, accountID: UUID) {
        let key = accountID.uuidString
        if authenticated {
            guard signedOut.remove(key) != nil else { return }
        } else {
            storage.remove(accountID)
            guard signedOut.insert(key).inserted else { return }
        }
        defaults.set(Array(signedOut), forKey: "mosaic.avatarSignedOut")
        revision += 1
    }
}

struct PersistentAccountAvatar<Placeholder: View>: View {
    let accountID: UUID
    let url: URL?
    let placeholder: Placeholder
    @State private var image: NSImage?
    @ObservedObject private var session = AccountAvatarSession.shared

    init(accountID: UUID, url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.accountID = accountID
        self.url = url
        self.placeholder = placeholder()
        _image = State(initialValue: AccountAvatarStorage.shared.image(for: accountID))
    }

    var body: some View {
        Group {
            if let image, !session.signedOut.contains(accountID.uuidString) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .onChange(of: session.revision) { _ in
            if session.signedOut.contains(accountID.uuidString) { image = nil }
            else if image == nil { image = AccountAvatarStorage.shared.image(for: accountID) }
        }
        .task(id: "\(url?.absoluteString ?? "")-\(session.revision)") {
            let revision = session.revision
            guard !session.signedOut.contains(accountID.uuidString), let url, TrustedURLPolicy.isTrustedProfileImageURL(url) else { return }
            do {
                guard let png = try await AccountAvatarDownload.load(from: url),
                      let refreshedImage = NSImage(data: png) else { return }
                try Task.checkCancellation()
                guard session.revision == revision,
                      !session.signedOut.contains(accountID.uuidString) else { return }
                try AccountAvatarStorage.shared.save(png, for: accountID)
                image = refreshedImage
            } catch {
                // Keep the last successful avatar during offline or failed refreshes.
            }
        }
    }
}

private enum AccountAvatarDownload {
    static func load(from url: URL) async throws -> Data? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.host?.lowercased() == "pbs.twimg.com", url.path.hasPrefix("/profile_images/") {
            components?.path = url.path.replacingOccurrences(
                of: "_(normal|bigger|mini)(?=\\.)", with: "_400x400", options: .regularExpression
            )
        } else if url.path.hasSuffix("/profile_image") {
            var items = components?.queryItems ?? []
            items.removeAll { $0.name == "size" }
            items.append(URLQueryItem(name: "size", value: "original"))
            components?.queryItems = items
        }
        if let largerURL = components?.url, largerURL != url {
            if let image = try? await thumbnail(from: largerURL) { return image }
            try Task.checkCancellation()
        }
        return try await thumbnail(from: url)
    }

    // Runs away from the main actor, including byte iteration and image decoding.
    static func thumbnail(from url: URL) async throws -> Data? {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.expectedContentLength <= 2_000_000 else { return nil }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { return nil }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 400,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:])
    }
}
