import AppKit
import SwiftUI

struct ColumnCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let column: DeckColumn
    let columnAppearanceMode: ColumnAppearanceMode
    let globalRefreshSignal: UUID
    let activeAccountID: UUID
    let isWebViewLive: Bool
    let isMediaSuspended: Bool
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
    @State private var isHoveringColumn = false
    @State private var isHoveringMenuHandle = false
    @State private var isReorderHandleActive = false
    @State private var isMenuHandleActive = false
    @State private var isHoveringResizeEdge = false
    @State private var resizeStartWidth: Double?

    var body: some View {
        VStack(spacing: 0) {
            header

            WebColumnView(
                url: column.url,
                refreshKey: refreshKey,
                accountID: activeAccountID,
                filter: column.filter,
                columnAppearanceMode: columnAppearanceMode,
                onNavigation: onNavigation,
                onDetectedHandle: onDetectedHandle,
                onDetectedProfileImage: onDetectedProfileImage,
                onPageTitle: onPageTitle,
                onMediaRequest: onMediaRequest,
                onUnreadNotificationCountChanged: onUnreadNotificationCountChanged,
                enableHandleDetection: column.type.allowsAccountMetadataDetection,
                enableAccountTextHandleDetection: column.type == .notifications,
                isLive: isWebViewLive,
                isMediaSuspended: isMediaSuspended
            )
            .id("\(column.id.uuidString)-\(activeAccountID.uuidString)")
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .background(
            MosaicSurface(level: .tile, cornerRadius: MosaicTheme.Radius.tile)
        )
        .overlay(alignment: .trailing) {
            resizeEdge
        }
        .onHover { hovering in
            withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
                isHoveringColumn = hovering
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(column.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(labelColor.opacity(0.92))

                if let subtitle = column.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(labelColor.opacity(0.58))
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
                        if TrustedURLPolicy.isTrustedXPage(column.url) {
                            NSWorkspace.shared.open(column.url)
                        }
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
                .opacity(isHoveringColumn || isMenuHandleActive || isHoveringMenuHandle ? 1 : 0.34)
                .onHover { hovering in
                    withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
                        isHoveringMenuHandle = hovering
                    }
                }

                reorderHandle
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isHoveringHandle ? MosaicTheme.activeAccent(for: colorScheme).opacity(0.58) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .onHover { hovering in
                        withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
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
                    .opacity(isHoveringColumn || isReorderHandleActive ? 1 : 0.48)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(columnChromeBand)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MosaicTheme.hairline(for: colorScheme).opacity(0.38))
                .frame(height: 0.5)
        }
    }

    private var columnChromeBand: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.036), Color.white.opacity(0.008)]
                : [Color.white.opacity(0.2), Color.white.opacity(0.055)],
            startPoint: .top,
            endPoint: .bottom
        )
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
        .background {
            if isMenuHandleActive || isHoveringMenuHandle {
                MosaicSurface(level: .base, cornerRadius: 8, isHovering: isHoveringMenuHandle)
            }
        }
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
        .background {
            if isHoveringHandle || isReorderHandleActive {
                MosaicSurface(
                    level: .base,
                    cornerRadius: 8,
                    isSelected: isHoveringHandle || isReorderHandleActive
                )
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Label(text, systemImage: "line.3.horizontal.decrease")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MosaicTheme.activeAccent(for: colorScheme).opacity(0.78))
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
                        .fill(MosaicTheme.activeAccent(for: colorScheme).opacity(0.62))
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
