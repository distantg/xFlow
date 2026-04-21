import SwiftUI

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case dark
    case auto
    case light

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .dark:
            return .dark
        case .auto:
            return nil
        case .light:
            return .light
        }
    }
}
