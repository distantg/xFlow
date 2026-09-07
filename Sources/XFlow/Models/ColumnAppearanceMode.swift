import Foundation

enum ColumnAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case originalX
    case mosaicIntegrated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .originalX:
            return "Original X"
        case .mosaicIntegrated:
            return "Mosaic"
        }
    }

    var summary: String {
        switch self {
        case .originalX:
            return "X's familiar timeline styling inside Mosaic's native column frame."
        case .mosaicIntegrated:
            return "A unified glass-and-ink treatment that keeps X's layout and controls intact."
        }
    }

    var symbolName: String {
        switch self {
        case .originalX:
            return "xmark"
        case .mosaicIntegrated:
            return "square.grid.2x2.fill"
        }
    }
}

enum ColumnAppearancePreference {
    static let storageKey = "xflow.columnAppearanceMode.v1"

    static func load(from defaults: UserDefaults) -> ColumnAppearanceMode {
        guard let rawValue = defaults.string(forKey: storageKey),
              let mode = ColumnAppearanceMode(rawValue: rawValue) else {
            return .originalX
        }
        return mode
    }

    static func save(_ mode: ColumnAppearanceMode, to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: storageKey)
    }
}
