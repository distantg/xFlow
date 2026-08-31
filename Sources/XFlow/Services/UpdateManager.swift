import AppKit
import Foundation

enum UpdateCheckConfiguration {
    static let manifestURL = URL(string: "https://raw.githubusercontent.com/distantg/xFlow/main/update-manifest.json")!
    static let automaticCheckInterval: TimeInterval = 12 * 60 * 60
    static let automaticRolloutDelay: TimeInterval = 7 * 24 * 60 * 60
    static let automaticLaunchDelay: TimeInterval = 8
}

struct UpdateManifest: Codable, Equatable {
    let latestVersion: String
    let publishedAt: Date
    let downloadURL: URL
    let releaseNotes: String
    let minimumSupportedVersion: String?
}

struct AvailableUpdate: Equatable {
    let latestVersion: String
    let publishedAt: Date
    let downloadURL: URL
    let releaseNotes: String
    let minimumSupportedVersion: String?
}

enum UpdateCheckMode {
    case manual
    case automatic
}

enum UpdateEvaluation: Equatable {
    case upToDate
    case available(AvailableUpdate)
    case deferred(AvailableUpdate)
}

protocol UpdateManifestFetching {
    func fetchManifest(from url: URL) async throws -> UpdateManifest
}

struct RemoteUpdateManifestFetcher: UpdateManifestFetching {
    func fetchManifest(from url: URL) async throws -> UpdateManifest {
        guard TrustedURLPolicy.isTrustedUpdateManifestURL(url) else {
            throw UpdateCheckError.untrustedURL
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let redirectDelegate = RejectRedirectURLSessionDelegate()
        let session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.httpStatus(httpResponse.statusCode)
        }
        guard httpResponse.url.map(TrustedURLPolicy.isTrustedUpdateManifestURL) == true else {
            throw UpdateCheckError.untrustedURL
        }
        let maximumBytes = 64 * 1024
        guard response.expectedContentLength < 0 || response.expectedContentLength <= maximumBytes else {
            throw UpdateCheckError.payloadTooLarge
        }

        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw UpdateCheckError.payloadTooLarge
            }
            data.append(byte)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(UpdateManifest.self, from: data)
        try UpdateManifestValidator.validate(manifest)
        return manifest
    }
}

enum UpdateCheckError: LocalizedError {
    case missingInstalledVersion
    case httpStatus(Int)
    case invalidManifest
    case invalidResponse
    case payloadTooLarge
    case untrustedURL

    var errorDescription: String? {
        switch self {
        case .missingInstalledVersion:
            return "The installed app version could not be read."
        case .httpStatus(let status):
            return "The update manifest returned HTTP \(status)."
        case .invalidManifest:
            return "The update manifest contains invalid or unsafe values."
        case .invalidResponse:
            return "The update server returned an invalid response."
        case .payloadTooLarge:
            return "The update manifest is unexpectedly large."
        case .untrustedURL:
            return "The update check was redirected to an untrusted location."
        }
    }
}

enum UpdateManifestValidator {
    private static let versionPattern = #"^[0-9]{1,4}(\.[0-9]{1,4}){1,3}$"#

    static func validate(_ manifest: UpdateManifest) throws {
        guard isValidVersion(manifest.latestVersion),
              manifest.minimumSupportedVersion.map(isValidVersion) ?? true,
              manifest.releaseNotes.count <= 10_000,
              TrustedURLPolicy.isTrustedGitHubReleaseURL(manifest.downloadURL),
              manifest.downloadURL.path == "/distantg/xFlow/releases/tag/v\(manifest.latestVersion)" else {
            throw UpdateCheckError.invalidManifest
        }
    }

    private static func isValidVersion(_ value: String) -> Bool {
        value.range(of: versionPattern, options: .regularExpression) != nil
    }
}

struct UpdateAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case upToDate
        case available
        case error
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let downloadURL: URL?
}

enum UpdateEvaluator {
    static func evaluate(
        manifest: UpdateManifest,
        installedVersion: String,
        now: Date,
        mode: UpdateCheckMode,
        rolloutDelay: TimeInterval
    ) -> UpdateEvaluation {
        guard SemanticVersion(manifest.latestVersion) > SemanticVersion(installedVersion) else {
            return .upToDate
        }

        let update = AvailableUpdate(
            latestVersion: manifest.latestVersion,
            publishedAt: manifest.publishedAt,
            downloadURL: manifest.downloadURL,
            releaseNotes: manifest.releaseNotes,
            minimumSupportedVersion: manifest.minimumSupportedVersion
        )

        guard mode == .automatic else {
            return .available(update)
        }

        let eligibleAt = manifest.publishedAt.addingTimeInterval(rolloutDelay)
        return now >= eligibleAt ? .available(update) : .deferred(update)
    }
}

struct SemanticVersion: Comparable, Equatable {
    private let parts: [Int]

    init(_ rawValue: String) {
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        parts = cleaned
            .split(whereSeparator: { !$0.isNumber })
            .map { Int($0) ?? 0 }
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: SemanticVersion, _ rhs: SemanticVersion) -> Int {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }
        return 0
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var isChecking = false
    @Published var alert: UpdateAlert?

    private let manifestURL: URL
    private let automaticInterval: TimeInterval
    private let rolloutDelay: TimeInterval
    private let fetcher: UpdateManifestFetching
    private let defaults: UserDefaults
    private var automaticTask: Task<Void, Never>?

    private let lastAutomaticNotificationKey = "xflow.updates.lastAutomaticNotificationVersion.v1"

    init(
        manifestURL: URL = UpdateCheckConfiguration.manifestURL,
        automaticInterval: TimeInterval = UpdateCheckConfiguration.automaticCheckInterval,
        rolloutDelay: TimeInterval = UpdateCheckConfiguration.automaticRolloutDelay,
        fetcher: UpdateManifestFetching = RemoteUpdateManifestFetcher(),
        defaults: UserDefaults = .standard
    ) {
        self.manifestURL = manifestURL
        self.automaticInterval = automaticInterval
        self.rolloutDelay = rolloutDelay
        self.fetcher = fetcher
        self.defaults = defaults
    }

    deinit {
        automaticTask?.cancel()
    }

    func startAutomaticChecks() {
        guard automaticTask == nil else {
            return
        }

        automaticTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(UpdateCheckConfiguration.automaticLaunchDelay * 1_000_000_000))

            while !Task.isCancelled {
                await self?.runAutomaticCheck()
                try? await Task.sleep(nanoseconds: UInt64((self?.automaticInterval ?? 0) * 1_000_000_000))
            }
        }
    }

    func checkManually() async {
        guard !isChecking else {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let result = try await check(mode: .manual)
            switch result {
            case .upToDate:
                alert = UpdateAlert(
                    kind: .upToDate,
                    title: "You're up to date",
                    message: "xFlow \(installedVersion) is the latest available version.",
                    downloadURL: nil
                )
            case .available(let update), .deferred(let update):
                alert = UpdateAlert(
                    kind: .available,
                    title: "xFlow \(update.latestVersion) is available",
                    message: update.releaseNotes.isEmpty ? "A new version is ready on GitHub." : update.releaseNotes,
                    downloadURL: update.downloadURL
                )
            }
        } catch {
            alert = UpdateAlert(
                kind: .error,
                title: "Update check failed",
                message: error.localizedDescription,
                downloadURL: nil
            )
        }
    }

    func openDownloadPage(_ url: URL) {
        guard TrustedURLPolicy.isTrustedGitHubReleaseURL(url) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func runAutomaticCheck() async {
        do {
            let result = try await check(mode: .automatic)
            guard case .available(let update) = result else {
                return
            }

            let lastNotified = defaults.string(forKey: lastAutomaticNotificationKey)
            guard lastNotified != update.latestVersion else {
                return
            }

            defaults.set(update.latestVersion, forKey: lastAutomaticNotificationKey)
            alert = UpdateAlert(
                kind: .available,
                title: "xFlow \(update.latestVersion) is available",
                message: update.releaseNotes.isEmpty ? "A new version is ready on GitHub." : update.releaseNotes,
                downloadURL: update.downloadURL
            )
        } catch {
            // Automatic checks should stay quiet unless an update is actually available.
        }
    }

    private func check(mode: UpdateCheckMode) async throws -> UpdateEvaluation {
        guard !installedVersion.isEmpty else {
            throw UpdateCheckError.missingInstalledVersion
        }

        let manifest = try await fetcher.fetchManifest(from: manifestURL)
        return UpdateEvaluator.evaluate(
            manifest: manifest,
            installedVersion: installedVersion,
            now: Date(),
            mode: mode,
            rolloutDelay: rolloutDelay
        )
    }

    private var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }
}
