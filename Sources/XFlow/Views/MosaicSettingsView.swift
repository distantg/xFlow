import SwiftUI

struct MosaicSettingsView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MosaicBackdrop()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: MosaicTheme.Spacing.panel) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Appearance")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Tune the native workspace and how X sits inside each tile.")
                        .font(.callout)
                        .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                }

                MosaicPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsLabel("Workspace", symbol: "circle.lefthalf.filled")
                        Picker("Workspace appearance", selection: appearanceBinding) {
                            Text("Dark").tag(AppAppearanceMode.dark)
                            Text("Automatic").tag(AppAppearanceMode.auto)
                            Text("Light").tag(AppAppearanceMode.light)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(3)
                        .background(MosaicInsetSurface(cornerRadius: 10))
                    }
                    .padding(16)
                }

                MosaicPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsLabel("Column appearance", symbol: "square.grid.2x2")

                        ForEach(ColumnAppearanceMode.allCases) { mode in
                            Button {
                                store.setColumnAppearanceMode(mode)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: mode.symbolName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mode.title)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(mode.summary)
                                            .font(.caption)
                                            .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                                    }

                                    Spacer()

                                    Image(systemName: store.columnAppearanceMode == mode ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(store.columnAppearanceMode == mode ? MosaicTheme.activeAccent(for: colorScheme) : MosaicTheme.secondaryText(for: colorScheme))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(MosaicButtonStyle(kind: .quiet, cornerRadius: 12))
                        }
                    }
                    .padding(16)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 430)
    }

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { store.appearanceMode },
            set: { store.setAppearanceMode($0) }
        )
    }

    private func settingsLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MosaicTheme.primaryText(for: colorScheme))
    }
}
