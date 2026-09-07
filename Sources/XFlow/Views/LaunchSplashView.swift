import AppKit
import SwiftUI

/// The complete contents of the borderless launch panel.
struct LaunchSplashView: View {
    var allowsContinue = false
    var onContinue: () -> Void = {}

    private let stone = Color(red: 0.085, green: 0.08, blue: 0.07)
    private let limestone = Color(red: 0.94, green: 0.89, blue: 0.79)

    var body: some View {
        ZStack {
            stone
            if let url = Bundle.main.url(forResource: "SplashBackground", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
            LinearGradient(
                colors: [.clear, stone.opacity(0.18), stone.opacity(0.54)],
                startPoint: .leading,
                endPoint: .trailing
            )
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Text("Mosaic")
                        .font(wordmarkFont)
                        .tracking(-1.8)
                        .foregroundStyle(limestone)
                        .shadow(color: .black.opacity(0.28), radius: 12, y: 3)
                    Text(versionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(limestone.opacity(0.7))
                }
                .frame(width: 340)
                .padding(.trailing, 38)
            }
        }
        .frame(width: 820, height: 460)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(limestone.opacity(0.13), lineWidth: 0.75)
        }
        .overlay(alignment: .bottomTrailing) {
            if allowsContinue {
                Button("Still loading · Open Mosaic", action: onContinue)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(limestone.opacity(0.8))
                    .padding(24)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mosaic is opening. " + versionLabel)
    }

    private var wordmarkFont: Font {
        if let font = NSFont(name: "BigCaslon-Medium", size: 76) {
            return Font(font)
        }
        return .system(size: 76, weight: .regular, design: .serif)
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        return "Version \(version)"
    }
}
