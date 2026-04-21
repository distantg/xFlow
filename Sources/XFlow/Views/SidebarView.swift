import SwiftUI

struct SidebarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let accounts: [DeckAccount]
    let activeAccountID: UUID
    let appearanceMode: AppAppearanceMode
    let onSwitchAccount: (UUID) -> Void
    let onAddAccount: () -> Void
    let onRemoveAccount: (UUID) -> Void
    let onQuickAction: (XSidebarAction) -> Void
    let onAppearanceModeChange: (AppAppearanceMode) -> Void
    let isCheckingForUpdates: Bool
    let onCheckUpdates: () -> Void

    @State private var menuScrollOffset: CGFloat = 0
    @State private var menuScrollRange: CGFloat = 0

    @State private var isAccountPanelExpanded = false
    @State private var pendingRemovalAccountID: UUID?

    private let quickActions: [XSidebarAction] = [
        .home,
        .search,
        .notifications,
        .messages,
        .grok,
        .premium,
        .bookmarks,
        .creatorStudio,
        .articles,
        .profile,
        .more
    ]

    var body: some View {
        VStack(spacing: 12) {
            accountSwitcherArea
                .zIndex(300)

            Divider()
                .overlay(separatorColor)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    Button {
                        onQuickAction(.compose)
                    } label: {
                        ZStack {
                            Image(systemName: XSidebarAction.compose.symbolName)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(labelColor.opacity(0.9))
                        }
                        .frame(width: 62, height: 62)
                    }
                    .buttonStyle(NeumorphicCircleButtonStyle(surfaceOpacity: composeSurfaceOpacity))
                    .help(XSidebarAction.compose.title)

                    ForEach(quickActions) { action in
                        Button {
                            onQuickAction(action)
                        } label: {
                            sidebarIcon(action.symbolName)
                        }
                        .buttonStyle(NeumorphicRoundedButtonStyle(cornerRadius: 12, surfaceOpacity: surfaceOpacity))
                        .help(action.title)
                    }

                    Spacer(minLength: 10)

                    AppearanceModeSlider(
                        mode: appearanceMode,
                        foreground: labelColor,
                        colorScheme: colorScheme,
                        onSelect: onAppearanceModeChange
                    )
                    .frame(width: 66, height: 32)
                    .help("Appearance")

                    Button {
                        onCheckUpdates()
                    } label: {
                        if isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 24, height: 24)
                        } else {
                            sidebarIcon("arrow.down.circle")
                        }
                    }
                    .disabled(isCheckingForUpdates)
                    .buttonStyle(NeumorphicRoundedButtonStyle(cornerRadius: 12, surfaceOpacity: surfaceOpacity))
                    .help("Check for updates")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .background(
                SidebarScrollMetricsReader(
                    offsetY: $menuScrollOffset,
                    maxOffsetY: $menuScrollRange
                )
            )
            .overlay(alignment: .top) {
                if showsTopScrollHint {
                    scrollHintGlyph("chevron.up")
                        .padding(.top, 6)
                        .zIndex(50)
                }
            }
            .overlay(alignment: .bottom) {
                if showsBottomScrollHint {
                    scrollHintGlyph("chevron.down")
                        .padding(.bottom, 6)
                        .zIndex(50)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 40)
        .padding(.bottom, 14)
        .frame(width: 96)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.1 : 0.18),
                            Color.white.opacity(colorScheme == .dark ? 0.02 : 0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .ignoresSafeArea(.container, edges: .top)
        .zIndex(200)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: isAccountPanelExpanded)
        .animation(.easeInOut(duration: 0.18), value: pendingRemovalAccountID)
    }

    private var accountSwitcherArea: some View {
        ZStack(alignment: .top) {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    isAccountPanelExpanded.toggle()
                    if !isAccountPanelExpanded {
                        pendingRemovalAccountID = nil
                    }
                }
            } label: {
                accountAvatar(for: activeAccount, size: 54, isActive: true)
            }
            .buttonStyle(.plain)
            .help("Accounts")

            if isAccountPanelExpanded {
                accountPanel
                    .offset(x: 68, y: 62)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                    .zIndex(500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(accounts) { account in
                HStack(spacing: 10) {
                    Button {
                        onSwitchAccount(account.id)
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            isAccountPanelExpanded = false
                            pendingRemovalAccountID = nil
                        }
                    } label: {
                        accountAvatar(for: account, size: 42, isActive: account.id == activeAccountID)
                    }
                    .buttonStyle(.plain)
                    .help(account.name)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountDisplayLabel(for: account))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(labelColor.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if pendingRemovalAccountID == account.id {
                        Button("Remove Account") {
                            onRemoveAccount(account.id)
                            withAnimation(.easeInOut(duration: 0.16)) {
                                pendingRemovalAccountID = nil
                                if account.id == activeAccountID {
                                    isAccountPanelExpanded = false
                                }
                            }
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.red.opacity(colorScheme == .dark ? 0.34 : 0.22))
                        )
                        .foregroundStyle(labelColor.opacity(0.96))
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                pendingRemovalAccountID = account.id
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.96))
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle()
                                        .fill(Color.red.opacity(colorScheme == .dark ? 0.76 : 0.62))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.52), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(accounts.count <= 1)
                        .opacity(accounts.count <= 1 ? 0.35 : 1)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    onAddAccount()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        isAccountPanelExpanded = false
                        pendingRemovalAccountID = nil
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(labelColor.opacity(0.9))
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.26))
                                .shadow(color: highlightShadow.opacity(0.8), radius: 4, x: -2, y: -2)
                                .shadow(color: depthShadow, radius: 5, x: 3, y: 3)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.3 : 0.45), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Add Account")

                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .padding(.leading, 31)
        .padding(.trailing, 10)
        .frame(width: 238, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08))

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.44), lineWidth: 1)
            }
        )
        .shadow(color: depthShadow.opacity(0.95), radius: 12, x: 0, y: 8)
    }

    private func accountAvatar(for account: DeckAccount?, size: CGFloat, isActive: Bool) -> some View {
        ZStack {
            if let url = account.flatMap(accountAvatarURL(for:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(isActive ? labelColor.opacity(0.95) : borderColor, lineWidth: isActive ? 2 : 1)
        )
        .shadow(color: depthShadow.opacity(0.9), radius: 5, x: 0, y: 2)
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(placeholderFill)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(labelColor.opacity(0.78))
            )
    }

    private func accountAvatarURL(for account: DeckAccount) -> URL? {
        if let raw = account.profileImageURL,
           let parsed = normalizedProfileImageURL(from: raw) {
            return parsed
        }
        if let handle = account.handle, !handle.isEmpty {
            return URL(string: "https://x.com/\(handle)/profile_image?size=normal")
        }
        return nil
    }

    private func accountDisplayLabel(for account: DeckAccount) -> String {
        if let handle = account.handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return account.fallbackName
    }

    private func normalizedProfileImageURL(from raw: String) -> URL? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")

        if cleaned.hasPrefix("//") {
            return URL(string: "https:\(cleaned)")
        }

        guard cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") else {
            return nil
        }

        return URL(string: cleaned)
    }

    private var labelColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var separatorColor: Color {
        labelColor.opacity(colorScheme == .dark ? 0.2 : 0.12)
    }

    private var highlightShadow: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.5)
    }

    private var depthShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.18)
    }

    private var placeholderFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.2)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.white.opacity(0.22)
    }

    private var surfaceOpacity: Double {
        colorScheme == .dark ? 0.22 : 0.34
    }

    private var composeSurfaceOpacity: Double {
        colorScheme == .dark ? 0.28 : 0.42
    }

    private var canScrollMenu: Bool {
        menuScrollRange > 3
    }

    private var showsTopScrollHint: Bool {
        canScrollMenu && menuScrollOffset > 3
    }

    private var showsBottomScrollHint: Bool {
        canScrollMenu && menuScrollOffset < (menuScrollRange - 3)
    }

    private var activeAccount: DeckAccount? {
        accounts.first(where: { $0.id == activeAccountID })
    }

    private func sidebarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(labelColor.opacity(0.9))
            .frame(width: 50, height: 44)
    }

    private func scrollHintGlyph(_ symbolName: String) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(labelColor.opacity(0.86))
        }
        .frame(width: 38, height: 38)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.34 : 0.48), lineWidth: 1.2)
        )
        .shadow(color: depthShadow.opacity(0.95), radius: 7, x: 0, y: 3)
        .allowsHitTesting(false)
    }
}

private struct AppearanceModeSlider: View {
    let mode: AppAppearanceMode
    let foreground: Color
    let colorScheme: ColorScheme
    let onSelect: (AppAppearanceMode) -> Void

    private let modes: [AppAppearanceMode] = [.dark, .auto, .light]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let knobSize = max(20, size.height - 6)
            let knobOffset = offset(for: mode, in: size.width, knobSize: knobSize)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.3))
                    .shadow(color: Color.white.opacity(0.55), radius: 4, x: -2, y: -2)
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 3, y: 3)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.48), lineWidth: 1)
                    )

                HStack {
                    trackIcon("moon.fill", active: mode == .dark)
                    Spacer()
                    trackIcon("circle.lefthalf.filled", active: mode == .auto)
                    Spacer()
                    trackIcon("sun.max.fill", active: mode == .light)
                }
                .padding(.horizontal, 8)

                Circle()
                    .fill(Color.white.opacity(0.9))
                    .shadow(color: Color.white.opacity(0.62), radius: 4, x: -2, y: -2)
                    .shadow(color: Color.black.opacity(0.22), radius: 6, x: 3, y: 3)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.52), lineWidth: 1)
                    )
                    .overlay(knobIcon)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: knobOffset)
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: mode)
            .contentShape(Capsule(style: .continuous))
            .onTapGesture {
                onSelect(nextMode(after: mode))
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        let selected = mode(for: value.location.x, width: size.width, knobSize: knobSize)
                        if selected != mode {
                            onSelect(selected)
                        }
                    }
                    .onEnded { value in
                        let selected = mode(for: value.location.x, width: size.width, knobSize: knobSize)
                        onSelect(selected)
                    }
            )
        }
    }

    private var knobIcon: some View {
        ZStack {
            knobGlyph("moon.fill", active: mode == .dark)
            knobGlyph("circle.lefthalf.filled", active: mode == .auto)
            knobGlyph("sun.max.fill", active: mode == .light)
        }
        .frame(width: 14, height: 14)
    }

    private func trackIcon(_ symbolName: String, active: Bool) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(foreground.opacity(trackOpacity(active: active)))
            .opacity(active ? 1 : 0.85)
    }

    private func knobGlyph(_ symbolName: String, active: Bool) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(knobGlyphColor)
            .opacity(active ? 1 : 0)
    }

    private func trackOpacity(active: Bool) -> Double {
        if colorScheme == .dark {
            return active ? 0.95 : 0.56
        }
        return active ? 0.7 : 0.34
    }

    private var knobGlyphColor: Color {
        if colorScheme == .dark {
            return Color.black.opacity(0.78)
        }
        return foreground.opacity(0.84)
    }

    private func mode(for x: CGFloat, width: CGFloat, knobSize: CGFloat) -> AppAppearanceMode {
        let travel = max(1, width - knobSize)
        let normalized = min(max((x - (knobSize * 0.5)) / travel, 0), 1)

        if normalized < 0.25 {
            return .dark
        }
        if normalized > 0.75 {
            return .light
        }
        return .auto
    }

    private func offset(for mode: AppAppearanceMode, in width: CGFloat, knobSize: CGFloat) -> CGFloat {
        let travel = max(0, width - knobSize)
        let index = CGFloat(modes.firstIndex(of: mode) ?? 1)
        let step = travel / CGFloat(max(modes.count - 1, 1))
        return index * step
    }

    private func nextMode(after mode: AppAppearanceMode) -> AppAppearanceMode {
        switch mode {
        case .dark:
            return .auto
        case .auto:
            return .light
        case .light:
            return .dark
        }
    }
}

private struct SidebarScrollMetricsReader: NSViewRepresentable {
    @Binding var offsetY: CGFloat
    @Binding var maxOffsetY: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetY: $offsetY, maxOffsetY: $maxOffsetY)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attachIfNeeded(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attachIfNeeded(to: nsView)
        context.coordinator.publishMetricsIfPossible()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private var offsetY: Binding<CGFloat>
        private var maxOffsetY: Binding<CGFloat>
        private weak var observedScrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?

        init(offsetY: Binding<CGFloat>, maxOffsetY: Binding<CGFloat>) {
            self.offsetY = offsetY
            self.maxOffsetY = maxOffsetY
        }

        func attachIfNeeded(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let scrollView = self.enclosingScrollView(for: view) else { return }
                guard scrollView !== self.observedScrollView else {
                    self.publishMetricsIfPossible()
                    return
                }

                self.detach()
                self.observedScrollView = scrollView
                scrollView.contentView.postsBoundsChangedNotifications = true
                self.boundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.publishMetricsIfPossible()
                }
                self.publishMetricsIfPossible()
            }
        }

        func publishMetricsIfPossible() {
            guard let scrollView = observedScrollView,
                  let documentView = scrollView.documentView else {
                return
            }

            let viewportHeight = max(0, scrollView.contentView.bounds.height)
            let documentHeight = max(0, documentView.bounds.height)
            let maxOffset = max(0, documentHeight - viewportHeight)
            let currentOffset = max(0, min(maxOffset, scrollView.contentView.bounds.origin.y))

            if abs(offsetY.wrappedValue - currentOffset) > 0.5 {
                offsetY.wrappedValue = currentOffset
            }
            if abs(maxOffsetY.wrappedValue - maxOffset) > 0.5 {
                maxOffsetY.wrappedValue = maxOffset
            }
        }

        func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
            observedScrollView = nil
        }

        private func enclosingScrollView(for view: NSView) -> NSScrollView? {
            var current: NSView? = view
            while let node = current {
                if let scrollView = node.enclosingScrollView {
                    return scrollView
                }
                current = node.superview
            }
            return nil
        }
    }
}
