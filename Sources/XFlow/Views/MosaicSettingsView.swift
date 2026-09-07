import SwiftUI

struct MosaicSettingsView: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var updateManager: UpdateManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MosaicBackdrop()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: MosaicTheme.Spacing.panel) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }

                MosaicSettingsGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsLabel("Workspace", symbol: "circle.lefthalf.filled")

                        MosaicSegmentedControl(
                            AppAppearanceMode.allCases,
                            selection: appearanceBinding
                        ) { mode in
                            HStack(spacing: 6) {
                                Image(systemName: mode.symbolName)
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .frame(width: 14, height: 14)

                                Text(mode.title)
                            }
                        }
                    }
                }

                MosaicSettingsGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsLabel("Column appearance", symbol: "square.grid.2x2")

                        ForEach(ColumnAppearanceMode.allCases) { mode in
                            Button {
                                store.setColumnAppearanceMode(mode)
                            } label: {
                                HStack(spacing: 12) {
                                    if mode != .originalX {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    store.columnAppearanceMode == mode
                                                        ? MosaicTheme.accent.opacity(colorScheme == .dark ? 0.2 : 0.24)
                                                        : Color.white.opacity(colorScheme == .dark ? 0.07 : 0.14)
                                                )

                                            Image(systemName: mode.symbolName)
                                                .symbolRenderingMode(.monochrome)
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .frame(width: 32, height: 32)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mode.title)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(mode.summary)
                                            .font(.caption)
                                            .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                                    }

                                    Spacer()

                                    ZStack {
                                        Circle()
                                            .fill(
                                                store.columnAppearanceMode == mode
                                                    ? MosaicTheme.accent
                                                    : MosaicTheme.secondaryText(for: colorScheme).opacity(0.16)
                                            )

                                        if store.columnAppearanceMode == mode {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .black))
                                                .foregroundStyle(Color.black.opacity(0.72))
                                        }
                                    }
                                    .frame(width: 17, height: 17)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(
                                MosaicSettingsChoiceStyle(
                                    isSelected: store.columnAppearanceMode == mode
                                )
                            )
                            .accessibilityAddTraits(
                                store.columnAppearanceMode == mode ? .isSelected : []
                            )
                        }
                    }
                }
                MosaicSettingsGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsLabel("Updates", symbol: "arrow.down.circle")
                        Toggle("Automatically check for updates", isOn: Binding(
                            get: { updateManager.automaticallyChecksForUpdates },
                            set: { updateManager.setAutomaticChecks($0) }
                        ))
                        Toggle("Download and install updates when Mosaic quits", isOn: Binding(
                            get: { updateManager.automaticallyDownloadsUpdates },
                            set: { updateManager.setAutomaticDownloads($0) }
                        ))
                        .disabled(!updateManager.automaticallyChecksForUpdates)
                        Button("Check for Updates…") { updateManager.checkManually() }
                            .disabled(!updateManager.canCheckForUpdates)
                        Text("Checks every 12 hours. You can also install and relaunch immediately when an update is ready.")
                            .font(.caption)
                            .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 640)
    }

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { store.appearanceMode },
            set: { store.setAppearanceMode($0) }
        )
    }

    private func settingsLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(MosaicTheme.accent.opacity(colorScheme == .dark ? 0.11 : 0.16))

                Image(systemName: symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .frame(width: 26, height: 26)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(MosaicTheme.primaryText(for: colorScheme))
    }
}

private struct MosaicSettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

                shape
                    .fill(
                        reduceTransparency
                            ? AnyShapeStyle(opaqueFill)
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
                    .overlay(
                        shape.fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.018)
                                : Color.white.opacity(0.09)
                        )
                    )
            }
    }

    private var opaqueFill: Color {
        colorScheme == .dark
            ? Color(red: 0.17, green: 0.18, blue: 0.19)
            : Color(red: 0.92, green: 0.93, blue: 0.93)
    }
}

private struct MosaicSettingsChoiceStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        MosaicSettingsChoiceBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct MosaicSettingsChoiceBody: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(choiceFill)
                    .shadow(
                        color: isSelected
                            ? Color.black.opacity(colorScheme == .dark ? 0.09 : 0.035)
                            : .clear,
                        radius: isSelected ? 5 : 0,
                        x: 0,
                        y: 1
                    )
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .onHover { hovering in
                withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
                    isHovering = hovering
                }
            }
            .animation(MosaicMotion.micro(reduceMotion: reduceMotion), value: isSelected)
            .animation(MosaicMotion.micro(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var choiceFill: Color {
        if isSelected {
            return MosaicTheme.accent.opacity(
                colorScheme == .dark ? (isHovering ? 0.16 : 0.13) : (isHovering ? 0.2 : 0.16)
            )
        }
        return Color.white.opacity(
            colorScheme == .dark ? (isHovering ? 0.055 : 0.022) : (isHovering ? 0.12 : 0.065)
        )
    }
}
