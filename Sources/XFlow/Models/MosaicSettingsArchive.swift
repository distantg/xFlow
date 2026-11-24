import Foundation

/// A portable workspace description. Authentication and device-specific data
/// deliberately have no representation in this format.
struct MosaicSettingsArchive: Codable, Equatable {
    static let currentVersion = 1
    static let maximumFileSize = 5 * 1_024 * 1_024

    let format: String
    let version: Int
    let exportedAt: Date
    let activeAccountID: UUID
    let preferences: Preferences
    let accounts: [Account]

    struct Preferences: Codable, Equatable {
        let appearanceMode: AppAppearanceMode
        let columnAppearanceMode: ColumnAppearanceMode
        let hideAds: Bool
        let automaticallyChecksForUpdates: Bool
        let automaticallyDownloadsUpdates: Bool
    }

    struct Account: Codable, Equatable {
        let id: UUID
        let fallbackName: String
        let handle: String?
        let columns: [DeckColumn]
    }

    init(
        format: String = "mosaic-settings",
        version: Int = Self.currentVersion,
        exportedAt: Date = Date(),
        activeAccountID: UUID,
        preferences: Preferences,
        accounts: [Account]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.activeAccountID = activeAccountID
        self.preferences = preferences
        self.accounts = accounts
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileSize else { throw ArchiveError.fileTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileSize else { throw ArchiveError.fileTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            // Read the version first, so a newer format with different fields
            // produces an actionable update message instead of a decoding error.
            let header = try decoder.decode(Header.self, from: data)
            try validateHeader(format: header.format, version: header.version)
            let archive = try decoder.decode(Self.self, from: data)
            try archive.validate()
            return archive
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw ArchiveError.invalidFile
        }
    }

    func validate() throws {
        try Self.validateHeader(format: format, version: version)
        guard !accounts.isEmpty, accounts.count <= 100 else {
            throw ArchiveError.invalidAccounts
        }
        var accountIDs = Set<UUID>()
        for account in accounts {
            guard accountIDs.insert(account.id).inserted else {
                throw ArchiveError.duplicateAccounts
            }
            guard !account.fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  account.fallbackName.utf8.count <= 512 else {
                throw ArchiveError.invalidAccounts
            }
            if let handle = account.handle {
                guard handle == handle.trimmingCharacters(in: .whitespacesAndNewlines),
                      !handle.contains("@"), TrustedURLPolicy.isValidXHandle(handle) else {
                    throw ArchiveError.invalidAccounts
                }
            }
            guard account.columns.count <= 200 else { throw ArchiveError.invalidColumns }
            var columnIDs = Set<UUID>()
            for column in account.columns {
                guard columnIDs.insert(column.id).inserted,
                      column.width.isFinite,
                      (DeckColumn.minWidth...DeckColumn.maxWidth).contains(column.width),
                      (column.customTitle?.utf8.count ?? 0) <= 512,
                      (column.parameter?.utf8.count ?? 0) <= 16_384,
                      (column.filter.includeKeywords?.utf8.count ?? 0) <= 16_384,
                      (column.filter.excludeKeywords?.utf8.count ?? 0) <= 16_384 else {
                    throw ArchiveError.invalidColumns
                }
            }
        }
        guard accountIDs.contains(activeAccountID) else { throw ArchiveError.invalidAccounts }
    }

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    private static func validateHeader(format: String, version: Int) throws {
        guard format == "mosaic-settings" else { throw ArchiveError.invalidFile }
        guard version == currentVersion else { throw ArchiveError.unsupportedVersion(version) }
    }

    enum ArchiveError: LocalizedError, Equatable {
        case fileTooLarge
        case invalidFile
        case unsupportedVersion(Int)
        case invalidAccounts
        case duplicateAccounts
        case invalidColumns

        var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return "This settings file is too large. Mosaic supports files up to 5 MB."
            case .invalidFile:
                return "This is not a valid Mosaic settings file. Choose a file exported from Mosaic."
            case .unsupportedVersion(let version) where version > MosaicSettingsArchive.currentVersion:
                return "This settings file was created by a newer version of Mosaic. Update Mosaic and try again."
            case .unsupportedVersion:
                return "This settings file uses an unsupported format version. Export it again from an updated copy of Mosaic."
            case .invalidAccounts:
                return "This settings file contains invalid account information. Export a new copy from Mosaic."
            case .duplicateAccounts:
                return "This settings file contains duplicate account identifiers. Export a new copy from Mosaic."
            case .invalidColumns:
                return "This settings file contains invalid column settings. Export a new copy from Mosaic."
            }
        }
    }
}
