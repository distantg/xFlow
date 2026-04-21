import SwiftUI

struct NeumorphicRoundedSurface: View {
    let cornerRadius: CGFloat
    var opacity: Double = 0.34
    var pressed: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(pressed ? max(0.24, opacity - 0.08) : opacity))
            .shadow(
                color: pressed ? Color.black.opacity(0.14) : Color.white.opacity(0.58),
                radius: pressed ? 4 : 6,
                x: pressed ? -2 : -3,
                y: pressed ? -2 : -3
            )
            .shadow(
                color: pressed ? Color.white.opacity(0.5) : Color.black.opacity(0.2),
                radius: pressed ? 4 : 8,
                x: pressed ? 2 : 5,
                y: pressed ? 2 : 5
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(pressed ? 0.3 : 0.5), lineWidth: 1)
            )
    }
}

struct NeumorphicCircleSurface: View {
    var opacity: Double = 0.34
    var pressed: Bool = false

    var body: some View {
        Circle()
            .fill(Color.white.opacity(pressed ? max(0.24, opacity - 0.08) : opacity))
            .shadow(
                color: pressed ? Color.black.opacity(0.14) : Color.white.opacity(0.58),
                radius: pressed ? 4 : 7,
                x: pressed ? -2 : -3,
                y: pressed ? -2 : -3
            )
            .shadow(
                color: pressed ? Color.white.opacity(0.5) : Color.black.opacity(0.22),
                radius: pressed ? 4 : 9,
                x: pressed ? 2 : 6,
                y: pressed ? 2 : 6
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(pressed ? 0.3 : 0.5), lineWidth: 1)
            )
    }
}

struct NeumorphicRoundedButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    var surfaceOpacity: Double = 0.34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                NeumorphicRoundedSurface(
                    cornerRadius: cornerRadius,
                    opacity: surfaceOpacity,
                    pressed: configuration.isPressed
                )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.11), value: configuration.isPressed)
    }
}

struct NeumorphicCircleButtonStyle: ButtonStyle {
    var surfaceOpacity: Double = 0.34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                NeumorphicCircleSurface(
                    opacity: surfaceOpacity,
                    pressed: configuration.isPressed
                )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.11), value: configuration.isPressed)
    }
}
