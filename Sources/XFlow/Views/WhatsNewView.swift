import SwiftUI

struct WhatsNewView: View {
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("MOSAIC 2.2")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close What’s New")
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What’s new")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }

            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(MosaicTheme.accent)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hide ads")
                        .font(.system(size: 21, weight: .semibold))
                    Text("Hide marked ads and promoted posts across your timelines. Your regular posts and column filters keep working as usual.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Turn ads on or off anytime in Settings → Timelines → Hide ads.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Open Settings with ⌘, or from the Mosaic menu.")
                        .font(.callout)
                        .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                }
                .font(.system(size: 14))
            }
            .padding(20)
            .background(MosaicTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

            HStack {
                Spacer()
                if #available(macOS 14.0, *) {
                    WhatsNewSettingsButton(onClose: onClose)
                } else {
                    Button("Turn off ads") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MosaicTheme.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(32)
        .frame(width: 570)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(MosaicTheme.accent.opacity(0.18)))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
        .accessibilityElement(children: .contain)
    }
}

@available(macOS 14.0, *)
private struct WhatsNewSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    let onClose: () -> Void

    var body: some View {
        Button("Turn off ads") {
            openSettings()
            onClose()
        }
        .buttonStyle(.borderedProminent)
        .tint(MosaicTheme.accent)
        .keyboardShortcut(.defaultAction)
    }
}
