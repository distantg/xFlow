import AppKit
import SwiftUI

struct AddColumnTypeMenu<Label: View>: View {
    let onSelect: (DeckColumnType) -> Void
    private let label: Label

    @State private var isPresented = false

    init(
        onSelect: @escaping (DeckColumnType) -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.onSelect = onSelect
        self.label = label()
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            AddColumnTypePalette { option in
                isPresented = false
                DispatchQueue.main.async {
                    onSelect(option)
                }
            }
        }
    }
}

private struct AddColumnTypePalette: View {
    @Environment(\.colorScheme) private var colorScheme

    let onSelect: (DeckColumnType) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a column")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(MosaicTheme.primaryText(for: colorScheme))

                Text("Choose what belongs in your workspace.")
                    .font(.caption)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(DeckColumnType.allCases) { option in
                    AddColumnTypeOption(option: option) {
                        onSelect(option)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 370)
        .background {
            ZStack {
                MosaicBackdrop(material: .popover)
                MosaicSurface(level: .overlay, cornerRadius: 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AddColumnTypeOption: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let option: DeckColumnType
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: option.chooserSystemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MosaicTheme.activeAccent(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(
                        MosaicInsetSurface(
                            cornerRadius: 9,
                            isActive: isHovering
                        )
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.defaultTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MosaicTheme.primaryText(for: colorScheme))
                    Text(option.summary)
                        .font(.system(size: 9.5))
                        .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MosaicSurface(
                    level: .raised,
                    cornerRadius: 13,
                    isHovering: isHovering
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(option.defaultTitle)
        .accessibilityHint(option.summary)
    }
}

private extension DeckColumnType {
    var chooserSystemImage: String {
        switch self {
        case .home:
            return "house"
        case .notifications:
            return "bell"
        case .messages:
            return "envelope"
        case .bookmarks:
            return "bookmark"
        case .explore:
            return "safari"
        case .search:
            return "magnifyingglass"
        case .profile:
            return "person.crop.circle"
        case .list:
            return "list.bullet.rectangle"
        }
    }
}
