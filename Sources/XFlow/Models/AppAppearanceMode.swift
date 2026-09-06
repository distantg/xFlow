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

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .auto: return "Automatic"
        case .light: return "Light"
        }
    }

    var symbolName: String {
        switch self {
        case .dark: return "moon.fill"
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        }
    }
}
