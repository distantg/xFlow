import SwiftUI

struct SidebarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let accounts: [DeckAccount]
    let activeAccountID: UUID
    let appearanceMode: AppAppearanceMode
    let columnAppearanceMode: ColumnAppearanceMode
    let onSwitchAccount: (UUID) -> Void
    let onAddAccount: () -> Void
    let onRemoveAccount: (UUID) -> Void
    let onQuickAction: (XSidebarAction) -> Void
    let onAppearanceModeChange: (AppAppearanceMode) -> Void
    let onColumnAppearanceModeChange: (ColumnAppearanceMode) -> Void
    let isCheckingForUpdates: Bool
    let onCheckUpdates: () -> Void

    @State private var menuScrollOffset: CGFloat = 0
    @State private var menuScrollRange: CGFloat = 0

    @State private var isAccountPanelExpanded = false
    @State private var isAppearancePopoverPresented = false

    private let quickActions: [XSidebarAction] = [
        .home,
        .search,
        .notifications,
        .messages,
        .bookmarks,
        .creatorStudio,
        .articles,
        .profile,
        .more
    ]

    var body: some View {
        VStack(spacing: 8) {
            accountSwitcherArea
                .zIndex(300)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    Button {
                        onQuickAction(.compose)
                    } label: {
                        ZStack {
                            Image(systemName: XSidebarAction.compose.symbolName)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(labelColor.opacity(0.9))
                        }
                        .frame(width: 54, height: 54)
                    }
                    .buttonStyle(MosaicIconButtonStyle(size: 54, prominent: true))
                    .help(XSidebarAction.compose.title)

                    ForEach(quickActions) { action in
                        Button {
                            onQuickAction(action)
                        } label: {
                            sidebarIcon(action.symbolName)
                        }
                        .buttonStyle(MosaicIconButtonStyle(size: 44))
                        .help(action.title)
                    }

                    Spacer(minLength: 10)

                    Button {
                        isAppearancePopoverPresented.toggle()
                    } label: {
                        Image(systemName: appearanceSymbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(labelColor.opacity(0.88))
                    }
                    .buttonStyle(MosaicIconButtonStyle(size: 38))
                    .help("Appearance")
                    .popover(isPresented: $isAppearancePopoverPresented, arrowEdge: .leading) {
                        SidebarAppearancePopover(
                            appearanceMode: appearanceMode,
                            columnAppearanceMode: columnAppearanceMode,
                            onAppearanceModeChange: onAppearanceModeChange,
                            onColumnAppearanceModeChange: onColumnAppearanceModeChange
                        )
                    }

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
                    .buttonStyle(MosaicIconButtonStyle(size: 38))
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
        .padding(.horizontal, 8)
        .padding(.top, 40)
        .padding(.bottom, 14)
        .frame(width: 82)
        .background(
            MosaicSurface(level: .base, cornerRadius: 0)
        )
        .ignoresSafeArea(.container, edges: .top)
        .zIndex(200)
    }

    private var accountSwitcherArea: some View {
        Button {
            isAccountPanelExpanded.toggle()
        } label: {
            accountAvatar(for: activeAccount, size: 54, isActive: true)
        }
        .buttonStyle(.plain)
        .help("Accounts")
        .accessibilityLabel("Switch accounts")
        .popover(isPresented: $isAccountPanelExpanded, arrowEdge: .leading) {
            accountPanel
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Accounts")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Text("Switch accounts without changing your deck.")
                    .font(.caption)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
            }

            ScrollView(.vertical, showsIndicators: accounts.count > 5) {
                LazyVStack(spacing: 4) {
                    ForEach(accounts) { account in
                        accountRow(account)
                    }
                }
            }
            .frame(height: accountListHeight)

            Button {
                onAddAccount()
                isAccountPanelExpanded = false
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 22)

                    Text("Add Account")
                        .font(.system(size: 12, weight: .semibold))

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MosaicButtonStyle(kind: .quiet, cornerRadius: 11, compact: true))
            .help("Add another X account")
        }
        .padding(14)
        .frame(width: 286, alignment: .leading)
        .background(
            MosaicSurface(level: .base, cornerRadius: 16)
        )
    }

    private func accountRow(_ account: DeckAccount) -> some View {
        HStack(spacing: 4) {
            Button {
                onSwitchAccount(account.id)
                isAccountPanelExpanded = false
            } label: {
                HStack(spacing: 10) {
                    accountAvatar(for: account, size: 36, isActive: false)

                    Text(accountDisplayLabel(for: account))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(labelColor.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    if account.id == activeAccountID {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MosaicTheme.activeAccent(for: colorScheme))
                            .accessibilityLabel("Current account")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MosaicButtonStyle(kind: .quiet, cornerRadius: 12, compact: true))
            .help(account.id == activeAccountID ? "Current account" : "Switch to \(account.name)")

            Menu {
                Button("Remove Account", role: .destructive) {
                    let removedActiveAccount = account.id == activeAccountID
                    onRemoveAccount(account.id)
                    if removedActiveAccount {
                        isAccountPanelExpanded = false
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .disabled(accounts.count <= 1)
            .opacity(accounts.count <= 1 ? 0.3 : 0.78)
            .help(accounts.count <= 1 ? "At least one account is required" : "Account actions")
            .accessibilityLabel("Actions for \(account.name)")
        }
    }

    private var accountListHeight: CGFloat {
        max(52, min(CGFloat(accounts.count) * 52, 260))
    }

    private func accountAvatar(for account: DeckAccount?, size: CGFloat, isActive: Bool) -> some View {
        ZStack {
            if let account {
                PersistentAccountAvatar(accountID: account.id, url: accountAvatarURL(for: account)) {
                    placeholderAvatar
                }
                .id(account.id)
            } else {
                placeholderAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(isActive ? MosaicTheme.activeAccent(for: colorScheme).opacity(0.92) : borderColor, lineWidth: isActive ? 2 : 1)
        )
        .shadow(color: depthShadow.opacity(0.72), radius: 5, x: 0, y: 2)
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

        let candidate: URL?
        if cleaned.hasPrefix("//") {
            candidate = URL(string: "https:\(cleaned)")
        } else {
            candidate = URL(string: cleaned)
        }

        guard let candidate, TrustedURLPolicy.isTrustedProfileImageURL(candidate) else {
            return nil
        }
        return candidate
    }

    private var labelColor: Color {
        colorScheme == .dark ? .white : .black
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

    private var appearanceSymbol: String {
        switch appearanceMode {
        case .dark: return "moon.fill"
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        }
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
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(labelColor.opacity(0.9))
            .frame(width: 42, height: 38)
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

private struct SidebarAppearancePopover: View {
    @Environment(\.colorScheme) private var colorScheme

    let appearanceMode: AppAppearanceMode
    let columnAppearanceMode: ColumnAppearanceMode
    let onAppearanceModeChange: (AppAppearanceMode) -> Void
    let onColumnAppearanceModeChange: (ColumnAppearanceMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Appearance")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("WORKSPACE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))

                MosaicSegmentedControl(
                    AppAppearanceMode.allCases,
                    selection: appearanceBinding,
                    height: 29
                ) { mode in
                    Image(systemName: mode.symbolName)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .accessibilityLabel(mode.title)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("COLUMNS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))

                MosaicSegmentedControl(
                    ColumnAppearanceMode.allCases,
                    selection: columnAppearanceBinding,
                    height: 29
                ) { mode in
                    HStack(spacing: 6) {
                        if mode != .originalX {
                            Image(systemName: mode.symbolName)
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 10.5, weight: .semibold))
                                .frame(width: 13, height: 13)
                        }

                        Text(mode.title)
                    }
                }

                Text(columnAppearanceMode.summary)
                    .font(.caption2)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 290)
        .background(MosaicSurface(level: .base, cornerRadius: 16))
    }

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(get: { appearanceMode }, set: onAppearanceModeChange)
    }

    private var columnAppearanceBinding: Binding<ColumnAppearanceMode> {
        Binding(get: { columnAppearanceMode }, set: onColumnAppearanceModeChange)
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
