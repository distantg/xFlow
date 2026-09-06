import AppKit
import SwiftUI

enum MosaicTheme {
    enum Radius {
        static let control: CGFloat = 10
        static let tile: CGFloat = 18
        static let panel: CGFloat = 22
    }

    enum Spacing {
        static let compact: CGFloat = 6
        static let control: CGFloat = 10
        static let section: CGFloat = 16
        static let panel: CGFloat = 20
    }

    // Mosaic's active color stays rooted in the limestone tesserae from the app icon.
    static let accent = Color(red: 0.93, green: 0.87, blue: 0.76)
    static let paleGlass = Color(red: 0.92, green: 0.96, blue: 0.985)

    static func activeAccent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? accent : Color(red: 0.38, green: 0.32, blue: 0.24)
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.92) : .black.opacity(0.86)
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.62) : .black.opacity(0.58)
    }

    static func hairline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.13) : .black.opacity(0.1)
    }
}

/// A real macOS backdrop: it samples the windows and desktop below Mosaic rather
/// than drawing an imitation environment inside the app.
struct MosaicBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .followsWindowActiveState
    }
}

enum MosaicSurfaceLevel {
    case base
    case tile
    case raised
    case overlay
}

struct MosaicSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState

    let level: MosaicSurfaceLevel
    var cornerRadius: CGFloat = MosaicTheme.Radius.tile
    var isSelected = false
    var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(reduceTransparency ? opaqueFill : materialFill)
            .overlay(shape.fill(surfaceTint))
            .overlay(
                shape
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.35 : 0.8)
            )
            .shadow(
                color: depthShadow,
                radius: depthRadius,
                x: 0,
                y: level == .base ? 0 : 2
            )
            .shadow(
                color: isSelected ? MosaicTheme.activeAccent(for: colorScheme).opacity(controlActiveState == .inactive ? 0.07 : 0.16) : .clear,
                radius: isSelected ? 10 : 0,
                x: 0,
                y: 2
            )
    }

    private var materialFill: AnyShapeStyle {
        switch level {
        case .base:
            // Base chrome rides directly on the window's real behind-window blur.
            // Keeping this layer clear avoids the cloudy, stacked-material look.
            return AnyShapeStyle(Color.clear)
        case .tile:
            return AnyShapeStyle(.ultraThinMaterial)
        case .raised:
            return AnyShapeStyle(.ultraThinMaterial)
        case .overlay:
            return AnyShapeStyle(.thinMaterial)
        }
    }

    private var opaqueFill: AnyShapeStyle {
        AnyShapeStyle(
            colorScheme == .dark
                ? Color(red: 0.13, green: 0.16, blue: 0.21)
                : MosaicTheme.paleGlass
        )
    }

    private var surfaceTint: Color {
        let inactiveMultiplier = controlActiveState == .inactive ? 0.55 : 1.0
        let levelOpacity: Double
        switch level {
        case .base: levelOpacity = colorScheme == .dark ? 0.008 : 0.018
        case .tile: levelOpacity = colorScheme == .dark ? 0.018 : 0.035
        case .raised: levelOpacity = colorScheme == .dark ? 0.032 : 0.055
        case .overlay: levelOpacity = colorScheme == .dark ? 0.052 : 0.082
        }
        let stateBoost = (isHovering ? 0.026 : 0) + (isSelected ? 0.02 : 0)
        return Color.white.opacity((levelOpacity + stateBoost) * inactiveMultiplier)
    }

    private var borderColor: Color {
        if isSelected {
            return MosaicTheme.activeAccent(for: colorScheme)
                .opacity(controlActiveState == .inactive ? 0.42 : 0.76)
        }
        let opacity: Double
        switch level {
        case .base: opacity = colorScheme == .dark ? 0.045 : 0.1
        case .tile: opacity = colorScheme == .dark ? 0.06 : 0.13
        case .raised: opacity = colorScheme == .dark ? 0.11 : 0.22
        case .overlay: opacity = colorScheme == .dark ? 0.14 : 0.28
        }
        return Color.white.opacity(opacity)
    }

    private var depthShadow: Color {
        let activeMultiplier = controlActiveState == .inactive ? 0.65 : 1
        return Color.black
            .opacity(depthOpacity * activeMultiplier)
    }

    private var depthOpacity: Double {
        switch level {
        case .base: return 0
        case .tile: return colorScheme == .dark ? 0.1 : 0.04
        case .raised: return colorScheme == .dark ? 0.16 : 0.06
        case .overlay: return colorScheme == .dark ? 0.24 : 0.09
        }
    }

    private var depthRadius: CGFloat {
        switch level {
        case .base: return 0
        case .tile: return 8
        case .raised: return 11
        case .overlay: return 18
        }
    }

}

struct MosaicInsetSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = MosaicTheme.Radius.control
    var isActive = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(reduceTransparency ? opaqueFill : AnyShapeStyle(.ultraThinMaterial))
            .overlay(shape.fill(insetFill))
            .overlay(
                shape.strokeBorder(
                    isActive
                        ? MosaicTheme.activeAccent(for: colorScheme).opacity(0.48)
                        : MosaicTheme.hairline(for: colorScheme).opacity(0.72),
                    lineWidth: isActive ? 1 : 0.65
                )
            )
    }

    private var opaqueFill: AnyShapeStyle {
        AnyShapeStyle(
            colorScheme == .dark
                ? Color(red: 0.10, green: 0.13, blue: 0.18)
                : Color(red: 0.86, green: 0.92, blue: 0.96)
        )
    }

    private var insetFill: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.07)
            : Color.white.opacity(0.055)
    }
}

/// A single-layer glass control with the elongated pill geometry used by
/// Mosaic's other primary controls. This avoids the doubled AppKit outline
/// produced by embedding a native segmented picker inside an inset surface.
struct MosaicSegmentedControl<Value: Hashable, SegmentLabel: View>: View {
    let values: [Value]
    @Binding var selection: Value
    var height: CGFloat = 34
    private let segmentLabel: (Value) -> SegmentLabel

    init(
        _ values: [Value],
        selection: Binding<Value>,
        height: CGFloat = 34,
        @ViewBuilder label: @escaping (Value) -> SegmentLabel
    ) {
        self.values = values
        _selection = selection
        self.height = height
        segmentLabel = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    segmentLabel(value)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MosaicSegmentButtonStyle(isSelected: selection == value))
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3)
        .background(MosaicSegmentTrack())
    }
}

private struct MosaicSegmentTrack: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Capsule(style: .continuous)
            .fill(reduceTransparency ? AnyShapeStyle(opaqueFill) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.black.opacity(0.055)
                            : Color.white.opacity(0.08)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        MosaicTheme.hairline(for: colorScheme).opacity(0.36),
                        lineWidth: 0.5
                    )
            )
    }

    private var opaqueFill: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.16, blue: 0.17)
            : Color(red: 0.91, green: 0.92, blue: 0.92)
    }
}

private struct MosaicSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        MosaicSegmentButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct MosaicSegmentButtonBody: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(
                isSelected
                    ? MosaicTheme.primaryText(for: colorScheme)
                    : MosaicTheme.secondaryText(for: colorScheme)
            )
            .background(
                Capsule(style: .continuous)
                    .fill(segmentFill)
                    .shadow(
                        color: isSelected
                            ? Color.black.opacity(colorScheme == .dark ? 0.14 : 0.055)
                            : .clear,
                        radius: isSelected ? 4 : 0,
                        x: 0,
                        y: 1
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? MosaicTheme.activeAccent(for: colorScheme).opacity(0.72)
                            : .clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
            .onHover { hovering in
                withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
                    isHovering = hovering
                }
            }
            .animation(MosaicMotion.micro(reduceMotion: reduceMotion), value: isSelected)
            .animation(MosaicMotion.micro(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var segmentFill: Color {
        if isSelected {
            return MosaicTheme.accent.opacity(colorScheme == .dark ? 0.19 : 0.24)
        }
        if isHovering {
            return Color.white.opacity(colorScheme == .dark ? 0.045 : 0.12)
        }
        return .clear
    }
}

struct MosaicTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MosaicInsetSurface(cornerRadius: MosaicTheme.Radius.control))
    }
}

enum MosaicButtonKind {
    case standard
    case prominent
    case quiet
    case destructive
}

struct MosaicButtonStyle: ButtonStyle {
    var kind: MosaicButtonKind = .standard
    var cornerRadius: CGFloat = MosaicTheme.Radius.control
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        MosaicButtonBody(
            configuration: configuration,
            kind: kind,
            cornerRadius: cornerRadius,
            compact: compact
        )
    }
}

struct MosaicIconButtonStyle: ButtonStyle {
    var size: CGFloat = 36
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        MosaicIconButtonBody(
            configuration: configuration,
            size: size,
            prominent: prominent
        )
    }
}

private struct MosaicButtonBody: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let kind: MosaicButtonKind
    let cornerRadius: CGFloat
    let compact: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 9 : 13)
            .padding(.vertical, compact ? 6 : 8)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .onHover { hovering in
                withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
                    isHovering = hovering
                }
            }
            .animation(MosaicMotion.micro(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    @ViewBuilder
    private var background: some View {
        if configuration.isPressed {
            MosaicInsetSurface(cornerRadius: cornerRadius, isActive: kind == .prominent)
        } else if kind == .destructive {
            MosaicSurface(level: .raised, cornerRadius: cornerRadius, isHovering: isHovering)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.red.opacity(isHovering ? 0.2 : 0.13))
                )
        } else if kind == .quiet && !isHovering {
            Color.clear
        } else {
            MosaicSurface(
                level: kind == .quiet ? .tile : .raised,
                cornerRadius: cornerRadius,
                isSelected: kind == .prominent || isFocused,
                isHovering: isHovering
            )
            .overlay {
                if kind == .prominent {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(MosaicTheme.accent.opacity(0.13))
                }
            }
        }
    }

    private var foreground: Color {
        if kind == .destructive {
            return colorScheme == .dark ? .red.opacity(0.94) : .red.opacity(0.82)
        }
        if kind == .prominent {
            return colorScheme == .dark ? .white.opacity(0.97) : .black.opacity(0.82)
        }
        return MosaicTheme.primaryText(for: colorScheme)
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private struct MosaicIconButtonBody: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let prominent: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .frame(width: size, height: size)
            .background {
                if configuration.isPressed {
                    MosaicInsetSurface(
                        cornerRadius: prominent ? size / 2 : MosaicTheme.Radius.control,
                        isActive: prominent
                    )
                } else if prominent {
                    MosaicSurface(
                        level: .raised,
                        cornerRadius: size / 2,
                        isSelected: true,
                        isHovering: isHovering
                    )
                } else if isHovering || isFocused {
                    MosaicSurface(
                        level: .base,
                        cornerRadius: MosaicTheme.Radius.control,
                        isSelected: isFocused,
                        isHovering: isHovering
                    )
                } else {
                    Color.clear
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.955 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .onHover { hovering in
                withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
                    isHovering = hovering
                }
            }
            .animation(MosaicMotion.micro(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

enum MosaicMotion {
    static func micro(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.13)
    }

    static func structural(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.88)
    }

    static func expressive(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.4, dampingFraction: 0.9)
    }
}

struct MosaicPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                MosaicSurface(level: .raised, cornerRadius: MosaicTheme.Radius.panel)
            )
            .clipShape(RoundedRectangle(cornerRadius: MosaicTheme.Radius.panel, style: .continuous))
    }
}

struct MosaicEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let symbol: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(MosaicTheme.accent.opacity(0.11))
                    )
                    .frame(width: 58, height: 58)

                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(MosaicTheme.primaryText(for: colorScheme))
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(MosaicTheme.primaryText(for: colorScheme))

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(actionTitle, action: action)
                .buttonStyle(MosaicButtonStyle(kind: .prominent))
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .background(MosaicSurface(level: .raised, cornerRadius: MosaicTheme.Radius.panel))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(didAppear || reduceMotion ? 1 : 0.97)
        .opacity(didAppear ? 1 : 0)
        .onAppear {
            withAnimation(MosaicMotion.expressive(reduceMotion: reduceMotion)) {
                didAppear = true
            }
        }
    }
}
