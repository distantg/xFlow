import AppKit
import SwiftUI

struct ColumnCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let column: DeckColumn
    let globalRefreshSignal: UUID
    let activeAccountID: UUID
    let onRemove: () -> Void
    let onDuplicate: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onWiden: () -> Void
    let onNarrow: () -> Void
    let onConfigure: () -> Void
    let onCompose: () -> Void
    let onResizeToWidth: (Double) -> Void
    let onReorderDragStart: () -> Void
    let onReorderDragChanged: (CGFloat) -> Void
    let onReorderDragEnded: () -> Void
    let onNavigation: (URL?) -> Void
    let onDetectedHandle: (String) -> Void
    let onDetectedProfileImage: (URL?) -> Void
    let onPageTitle: (String?) -> Void
    let onMediaRequest: (MediaRequest) -> Void
    let onUnreadNotificationCountChanged: ((Int, String?) -> Void)?

    @State private var localRefreshSignal = UUID()
    @State private var isHoveringHandle = false
    @State private var isReorderHandleActive = false
    @State private var isMenuHandleActive = false
    @State private var isHoveringResizeEdge = false
    @State private var resizeStartWidth: Double?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.12))

            WebColumnView(
                url: column.url,
                refreshKey: refreshKey,
                accountID: activeAccountID,
                filter: column.filter,
                onNavigation: onNavigation,
                onDetectedHandle: onDetectedHandle,
                onDetectedProfileImage: onDetectedProfileImage,
                onPageTitle: onPageTitle,
                onMediaRequest: onMediaRequest,
                onUnreadNotificationCountChanged: onUnreadNotificationCountChanged,
                enableHandleDetection: column.type.allowsAccountMetadataDetection,
                enableAccountTextHandleDetection: column.type == .notifications
            )
            .id("\(column.id.uuidString)-\(activeAccountID.uuidString)")
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.09),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .overlay(alignment: .trailing) {
            resizeEdge
        }
        .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 10)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(column.title)
                    .font(.headline)
                    .foregroundStyle(labelColor.opacity(0.86))

                if let subtitle = column.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(labelColor.opacity(0.68))
                }

                if column.filter.hasRules {
                    tag("Filtered")
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Menu {
                    Button("Refresh Column") {
                        localRefreshSignal = UUID()
                    }

                    Button("Open in Browser") {
                        NSWorkspace.shared.open(column.url)
                    }

                    Button("Compose") {
                        onCompose()
                    }

                    Button("Column Settings") {
                        onConfigure()
                    }

                    Button("Duplicate Column") {
                        onDuplicate()
                    }

                    Divider()

                    Button("Move Left") {
                        onMoveLeft()
                    }

                    Button("Move Right") {
                        onMoveRight()
                    }

                    Divider()

                    Button("Widen") {
                        onWiden()
                    }

                    Button("Narrow") {
                        onNarrow()
                    }

                    Divider()

                    Button("Remove Column", role: .destructive) {
                        onRemove()
                    }
                } label: {
                    menuTriggerIcon
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { _ in
                            if !isMenuHandleActive {
                                withAnimation(.easeInOut(duration: 0.08)) {
                                    isMenuHandleActive = true
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                isMenuHandleActive = false
                            }
                        }
                )
                .help("Column options")

                reorderHandle
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isHoveringHandle ? Color.cyan.opacity(0.55) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isHoveringHandle = hovering
                        }
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .global)
                            .onChanged { value in
                                if !isReorderHandleActive {
                                    withAnimation(.easeInOut(duration: 0.09)) {
                                        isReorderHandleActive = true
                                    }
                                }
                                onReorderDragStart()
                                onReorderDragChanged(value.location.x - value.startLocation.x)
                            }
                            .onEnded { _ in
                                withAnimation(.easeInOut(duration: 0.11)) {
                                    isReorderHandleActive = false
                                }
                                onReorderDragEnded()
                            }
                    )
                    .help("Drag to reorder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var menuTriggerIcon: some View {
        ZStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(labelColor.opacity(0.85))
                    .frame(width: 4, height: 4)
                Circle()
                    .fill(labelColor.opacity(0.85))
                    .frame(width: 4, height: 4)
                Circle()
                    .fill(labelColor.opacity(0.85))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: 24, height: 24)
        .background(
            NeumorphicRoundedSurface(
                cornerRadius: 8,
                opacity: 0.32,
                pressed: isMenuHandleActive
            )
        )
    }

    private var reorderHandle: some View {
        HStack(spacing: 3) {
            Capsule(style: .continuous)
                .fill(labelColor.opacity(0.8))
                .frame(width: 2, height: 12)
            Capsule(style: .continuous)
                .fill(labelColor.opacity(0.8))
                .frame(width: 2, height: 12)
            Capsule(style: .continuous)
                .fill(labelColor.opacity(0.8))
                .frame(width: 2, height: 12)
        }
        .frame(width: 24, height: 24)
            .background(
                NeumorphicRoundedSurface(
                    cornerRadius: 8,
                    opacity: 0.32,
                    pressed: isReorderHandleActive
                )
            )
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .foregroundStyle(labelColor.opacity(0.84))
    }

    private var refreshKey: String {
        "\(globalRefreshSignal.uuidString)-\(localRefreshSignal.uuidString)"
    }

    private var resizeEdge: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                if isHoveringResizeEdge || resizeStartWidth != nil {
                    Rectangle()
                        .fill(labelColor.opacity(0.38))
                        .frame(width: 2)
                        .padding(.vertical, 10)
                }
            }
            .onHover { hovering in
                guard hovering != isHoveringResizeEdge else {
                    return
                }

                isHoveringResizeEdge = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if resizeStartWidth == nil {
                            resizeStartWidth = column.width
                        }
                        let baseWidth = resizeStartWidth ?? column.width
                        let delta = Double(value.location.x - value.startLocation.x)
                        onResizeToWidth(baseWidth + delta)
                    }
                    .onEnded { _ in
                        resizeStartWidth = nil
                    }
            )
            .onDisappear {
                if isHoveringResizeEdge {
                    isHoveringResizeEdge = false
                    NSCursor.pop()
                }
            }
            .help("Drag to resize")
    }

    private var labelColor: Color {
        colorScheme == .dark ? .white : .black
    }
}
