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
        }
        .task(id: "\(url?.absoluteString ?? "")-\(session.revision)") {
            let revision = session.revision
            guard !session.signedOut.contains(accountID.uuidString), let url, TrustedURLPolicy.isTrustedProfileImageURL(url) else { return }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(from: url)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      response.expectedContentLength <= 2_000_000 else { return }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 2_000_000 else { return }
                    data.append(byte)
                }
                try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 128,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary),
                      let png = NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:]) else { return }
                guard session.revision == revision,
                      !session.signedOut.contains(accountID.uuidString) else { return }
                try AccountAvatarStorage.shared.save(png, for: accountID)
                image = NSImage(cgImage: thumbnail, size: .zero)
            } catch {
                // Keep the last successful avatar during offline or failed refreshes.
            }
        }
    }
}
