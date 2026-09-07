import SwiftUI

private struct ColumnFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

struct MainDeckView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var isLaunchSplashVisible = true
    @State private var launchReadyColumns: Set<UUID> = []
    @State private var allowsLaunchContinue = false
    @State private var hasPresentedLaunchSplash = false
    @State private var hasFinishedLaunchPresentation = false
    @State private var hasRestoredLaunchSession = false

    @State private var settingsColumnID: UUID?
    @State private var draggingColumnID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragColumnOrder: [UUID] = []
    @State private var dragColumnWidths: [UUID: CGFloat] = [:]
    @State private var dragSourceIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var isColumnDragSettling = false
    @State private var mediaRequest: MediaRequest?
    @State private var isDeckTransitioning = false
    @State private var resetRevealCount: Int?
    @State private var layoutResetAnimationID: UUID?
    @StateObject private var updateManager = UpdateManager()
    @State private var columnFrames: [UUID: CGRect] = [:]
    @State private var liveColumnIDs: Set<UUID> = []

    private let columnSpacing: CGFloat = 10
    private let columnViewportCoordinateSpace = "mosaic-column-viewport"

    var body: some View {
        ZStack {
            backgroundLayer

            HStack(spacing: 0) {
                SidebarView(
                    accounts: store.accounts,
                    activeAccountID: store.activeAccountID,
                    appearanceMode: store.appearanceMode,
                    columnAppearanceMode: store.columnAppearanceMode,
                    onSwitchAccount: { id in
                        switchAccount(to: id)
                    },
                    onAddAccount: {
                        store.addAccount()
                    },
                    onRemoveAccount: { id in
                        store.removeAccount(id)
                    },
                    onQuickAction: { action in
                        if action == .compose {
                            withAnimation(MosaicMotion.expressive(reduceMotion: reduceMotion)) {
                                store.presentComposer()
                            }
                        } else {
                            store.handleSidebarAction(action)
                        }
                    },
                    onAppearanceModeChange: { mode in
                        store.setAppearanceMode(mode)
                    },
                    onColumnAppearanceModeChange: { mode in
                        store.setColumnAppearanceMode(mode)
                    },
                    isCheckingForUpdates: updateManager.isChecking,
                    onCheckUpdates: {
                        Task {
                            await updateManager.checkManually()
                        }
                    }
                )
                .zIndex(100)

                content
                    .zIndex(0)
            }
            .ignoresSafeArea(.container, edges: .top)
            .background(deckGlassBackground)
            .accessibilityHidden(isLaunchSplashVisible)
        }
        .overlay {
            if isLaunchSplashVisible && !hasRestoredLaunchSession {
                WebColumnView(
                    url: URL(string: "https://x.com/home")!,
                    refreshKey: "launch-session",
                    accountID: store.activeAccountID,
                    filter: .none,
                    enableChromeStripping: false,
                    enableMediaCapture: false,
                    enableHandleDetection: false,
                    routeHorizontalScrollToParent: false,
                    isMediaSuspended: true,
                    onLaunchSessionResolved: { authenticated in
                        store.completeLaunchSessionRestoration(accountID: store.activeAccountID, authenticated: authenticated)
                        hasRestoredLaunchSession = true
                    }
                )
                .frame(width: 920, height: 720)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: hasPresentedLaunchSplash) {
            guard hasPresentedLaunchSplash else { return }
            // Only reveal after visible content has rendered. Slow connections
            // offer an explicit escape inside the splash instead of exposing preload UI.
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                var checks = 0
                while isLaunchSplashVisible && !isLaunchContentReady {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    checks += 1
                    if checks >= 130 { allowsLaunchContinue = true }
                }
                dismissLaunchSplash()
            } catch { /* A cancelled launch must not schedule a later reveal. */ }
        }
        .overlay(alignment: .topLeading) {
            TransparentWindowConfigurator(
                isLaunching: isLaunchSplashVisible,
                reduceMotion: reduceMotion,
                allowsContinue: allowsLaunchContinue,
                onContinue: dismissLaunchSplash,
                onSplashPresented: { hasPresentedLaunchSplash = true },
                onSplashDismissed: {
                    // Session restoration has already finished behind the splash.
                    hasFinishedLaunchPresentation = true
                }
            )
                .frame(width: 0, height: 0)
        }
        .overlay {
            if store.isComposerSheetPresented, let activeAccount = store.activeAccount {
                composerOverlay(account: activeAccount)
                    .zIndex(45)
            }
        }
        .overlay {
            if let mediaRequest {
                MediaLightboxView(
                    request: mediaRequest,
                    accountID: store.activeAccountID,
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            self.mediaRequest = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(50)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.88), value: mediaRequest != nil)
        .alert(item: $updateManager.alert) { updateAlert in
            if let downloadURL = updateAlert.downloadURL {
                return Alert(
                    title: Text(updateAlert.title),
                    message: Text(updateAlert.message),
                    primaryButton: .default(Text("Open GitHub Release")) {
                        updateManager.openDownloadPage(downloadURL)
                    },
                    secondaryButton: .cancel(Text("Later"))
                )
            }

            return Alert(
                title: Text(updateAlert.title),
                message: Text(updateAlert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $store.isAddColumnSheetPresented) {
            AddColumnSheet(initialType: store.addColumnInitialType)
                .environmentObject(store)
        }
        .sheet(item: quickPanelBinding) { destination in
            QuickActionPanelView(
                destination: destination,
                accountID: store.activeAccountID
            )
            .environmentObject(store)
        }
        .sheet(item: settingsColumnBinding) { column in
            ColumnSettingsSheet(column: column)
                .environmentObject(store)
        }
        .sheet(item: loginAccountBinding) { account in
            AccountLoginSheetView(account: account)
                .environmentObject(store)
        }
        .onAppear {
            XFlowNotificationCenter.shared.configure(with: store)
            updateManager.startAutomaticChecks()
        }
        .onChange(of: store.accounts) { accounts in
            XFlowNotificationCenter.shared.syncRemoteRouting(
                accounts: accounts,
                activeAccountID: store.activeAccountID
            )
        }
        .onChange(of: store.activeAccountID) { activeAccountID in
            XFlowNotificationCenter.shared.syncRemoteRouting(
                accounts: store.accounts,
                activeAccountID: activeAccountID
            )
        }
        .onChange(of: store.layoutResetSignal) { _ in
            beginLayoutResetReveal()
        }
    }

    private var isLaunchContentReady: Bool {
        guard hasRestoredLaunchSession else { return false }
        if store.columns.isEmpty || store.activeAccount?.requiresLogin == true { return true }
        let expected = liveColumnIDs.isEmpty
            ? Set(store.columns.prefix(3).map(\.id)) : liveColumnIDs
        return expected.isSubset(of: launchReadyColumns)
    }

    private func dismissLaunchSplash() {
        // An explicit slow-load escape may bypass restoration; normal launch cannot.
        if allowsLaunchContinue { hasRestoredLaunchSession = true }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.5)) {
            isLaunchSplashVisible = false
        }
    }

    private var backgroundLayer: some View {
        Color.clear
            .ignoresSafeArea()
    }

    private var deckGlassBackground: some View {
        ZStack {
            if reduceTransparency {
                Rectangle()
                    .fill(colorScheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.15) : MosaicTheme.paleGlass)
            } else {
                MosaicBackdrop()
            }

            Rectangle()
                .fill(
                    colorScheme == .dark
                        ? Color(red: 0.07, green: 0.085, blue: 0.105)
                            .opacity(controlActiveState == .inactive ? 0.06 : 0.025)
                        : Color(red: 0.96, green: 0.945, blue: 0.91)
                            .opacity(controlActiveState == .inactive ? 0.035 : 0.0105)
                )

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.34, green: 0.43, blue: 0.52).opacity(0.045),
                        Color.clear,
                        Color(red: 0.45, green: 0.35, blue: 0.25).opacity(0.025)
                    ]
                    : [
                        Color(red: 1.0, green: 0.94, blue: 0.82).opacity(0.0315),
                        Color.clear,
                        Color(red: 0.73, green: 0.84, blue: 0.9).opacity(0.0245)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        GeometryReader { proxy in
            contentBody(
                columnHeight: max(0, proxy.size.height - 28),
                viewportSize: proxy.size
            )
        }
    }

    @ViewBuilder
    private func contentBody(columnHeight: CGFloat, viewportSize: CGSize) -> some View {
        if !hasRestoredLaunchSession {
            Color.clear
        } else if activeAccountNeedsLogin {
            AccountLockedDeckView(
                accountName: store.activeAccount?.name ?? "Account",
                onOpenLogin: {
                    if let activeID = store.activeAccount?.id {
                        store.presentLoginFlow(for: activeID)
                    }
                }
            )
        } else if store.columns.isEmpty {
            EmptyDeckView { type in
                store.presentAddColumnSheet(type: type)
            }
        } else {
            deckScrollView(columnHeight: columnHeight, viewportSize: viewportSize)
        }
    }

    private func deckScrollView(columnHeight: CGFloat, viewportSize: CGSize) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // Keep each lightweight column host alive after it has been visited so
                // SwiftUI cannot dismantle a parked WKWebView and lose timeline state.
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(Array(store.columns.enumerated()), id: \.element.id) { index, column in
                        columnCard(
                            column,
                            renderAccountID: store.activeAccountID,
                            columnHeight: columnHeight,
                            isWebViewLive: shouldKeepWebViewLive(for: column)
                        )
                        .opacity(isResetTileVisible(at: index) ? 1 : 0)
                        .scaleEffect(
                            isResetTileVisible(at: index) || reduceMotion ? 1 : 0.965,
                            anchor: .leading
                        )
                    }

                    addColumnTile
                        .frame(width: 220, height: columnHeight)
                }
                .animation(MosaicMotion.structural(reduceMotion: reduceMotion), value: store.columns.map(\.id))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .padding(.top, 10)
            }
            .coordinateSpace(name: columnViewportCoordinateSpace)
            .onPreferenceChange(ColumnFramePreferenceKey.self) { frames in
                columnFrames = frames
                updateLiveColumns(viewportSize: viewportSize)
            }
            .onChange(of: viewportSize) { newSize in
                updateLiveColumns(viewportSize: newSize)
            }
            .onChange(of: store.columns) { _ in
                updateLiveColumns(viewportSize: viewportSize)
            }
            .scrollDisabled(draggingColumnID != nil)
            .opacity(isDeckTransitioning ? 0.42 : 1)
            .scaleEffect(isDeckTransitioning && !reduceMotion ? 0.995 : 1)
            .onChange(of: store.scrollTargetColumnID) { target in
                guard let target else {
                    return
                }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                    scrollProxy.scrollTo(target, anchor: .leading)
                }
            }
        }
    }

    private func columnCard(
        _ column: DeckColumn,
        renderAccountID: UUID,
        columnHeight: CGFloat,
        isWebViewLive: Bool
    ) -> some View {
        ColumnCardView(
            column: column,
            columnAppearanceMode: store.columnAppearanceMode,
            globalRefreshSignal: store.refreshSignal,
            activeAccountID: renderAccountID,
            isWebViewLive: isWebViewLive,
            isMediaSuspended: scenePhase != .active,
            onRemove: {
                withAnimation(MosaicMotion.structural(reduceMotion: reduceMotion)) {
                    store.removeColumn(id: column.id)
                }
            },
            onDuplicate: {
                withAnimation(MosaicMotion.structural(reduceMotion: reduceMotion)) {
                    store.duplicateColumn(id: column.id)
                }
            },
            onMoveLeft: {
                withAnimation(MosaicMotion.structural(reduceMotion: reduceMotion)) {
                    store.shiftColumn(id: column.id, by: -1)
                }
            },
            onMoveRight: {
                withAnimation(MosaicMotion.structural(reduceMotion: reduceMotion)) {
                    store.shiftColumn(id: column.id, by: 1)
                }
            },
            onWiden: {
                withAnimation(MosaicMotion.structural(reduceMotion: reduceMotion)) {
                    store.adjustWidth(for: column.id, delta: 30)
                }
            },
            onNarrow: {
                withAnimation(MosaicMotion.structural(reduceMotion: reduceMotion)) {
                    store.adjustWidth(for: column.id, delta: -30)
                }
            },
            onConfigure: {
                settingsColumnID = column.id
            },
            onCompose: {
                withAnimation(MosaicMotion.expressive(reduceMotion: reduceMotion)) {
                    store.presentComposer()
                }
            },
            onResizeToWidth: { width in
                store.setWidth(for: column.id, width: width)
            },
            onReorderDragStart: {
                beginColumnDrag(column.id)
            },
            onReorderDragChanged: { translation in
                updateColumnDrag(column.id, translation: translation)
            },
            onReorderDragEnded: {
                endColumnDrag(column.id)
            },
            onNavigation: { url in
                if column.type.allowsAccountMetadataDetection {
                    store.captureHandle(for: renderAccountID, from: url)
                }
                store.captureListMetadata(for: column.id, from: url, pageTitle: nil)
            },
            onDetectedHandle: { handle in
                store.setHandle(accountID: renderAccountID, handle: handle)
            },
            onDetectedProfileImage: { imageURL in
                store.setProfileImage(accountID: renderAccountID, imageURL: imageURL)
            },
            onPageTitle: { pageTitle in
                store.captureListMetadata(for: column.id, from: nil, pageTitle: pageTitle)
            },
            onMediaRequest: { request in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    mediaRequest = request
                }
            },
            onUnreadNotificationCountChanged: notificationHandler(
                for: column,
                accountID: renderAccountID
            ),
            notificationNavigationURL: store.notificationNavigationURLs[column.id],
            onInitialContentReady: isLaunchSplashVisible ? {
                launchReadyColumns.insert(column.id)
            } : nil
        )
        .id(column.id)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.96, anchor: .leading)),
                removal: .opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.94))
            )
        )
        .frame(width: column.width, height: columnHeight)
        .offset(x: dragOffset(for: column.id))
        .scaleEffect(draggingColumnID == column.id && !isColumnDragSettling && !reduceMotion ? 1.012 : 1)
        .zIndex(draggingColumnID == column.id ? 15 : 0)
        .shadow(
            color: Color.black.opacity(draggingColumnID == column.id && !isColumnDragSettling ? 0.24 : 0),
            radius: draggingColumnID == column.id && !isColumnDragSettling ? 22 : 0,
            x: 0,
            y: draggingColumnID == column.id && !isColumnDragSettling ? 10 : 0
        )
        .animation(MosaicMotion.micro(reduceMotion: reduceMotion), value: draggingColumnID == column.id)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ColumnFramePreferenceKey.self,
                    value: [column.id: proxy.frame(in: .named(columnViewportCoordinateSpace))]
                )
            }
        }
    }

    private func shouldKeepWebViewLive(for column: DeckColumn) -> Bool {
        if ColumnResidencyPolicy.isBackgroundMonitor(column) {
            return true
        }

        if liveColumnIDs.isEmpty {
            return store.columns.prefix(3).contains(where: { $0.id == column.id })
        }

        return liveColumnIDs.contains(column.id)
    }

    private func updateLiveColumns(viewportSize: CGSize) {
        guard viewportSize.width > 0 else { return }

        let desired = ColumnResidencyPolicy.desiredLiveColumnIDs(
            columns: store.columns,
            frames: columnFrames,
            viewportSize: viewportSize,
            columnSpacing: columnSpacing
        )

        if desired != liveColumnIDs {
            liveColumnIDs = desired
        }
    }

    private func notificationHandler(
        for column: DeckColumn,
        accountID: UUID
    ) -> ((Int, NotificationActivity?) -> Void)? {
        guard column.type == .notifications else {
            return nil
        }

        return { unreadCount, activity in
            if let account = store.account(with: accountID) {
                XFlowNotificationCenter.shared.publishUnreadNotification(
                    count: unreadCount,
                    account: account,
                    activity: activity
                )
            }
        }
    }

    private var activeAccountNeedsLogin: Bool {
        store.activeAccount?.requiresLogin ?? true
    }

    private var addColumnTile: some View {
        AddColumnTypeMenu { type in
            store.presentAddColumnSheet(type: type)
        } label: {
            ZStack {
                VStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(MosaicSurface(level: .raised, cornerRadius: 18))
                    Text("Add Column")
                        .font(.system(size: 13, weight: .semibold))
                    Text("⌘N")
                        .font(.caption2.monospaced())
                        .foregroundStyle(addColumnSecondaryTextColor)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
            .foregroundStyle(addColumnPrimaryTextColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Column")
    }

    private func composerOverlay(account: DeckAccount) -> some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.32 : 0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(MosaicMotion.expressive(reduceMotion: reduceMotion)) {
                        store.dismissComposer()
                    }
                }

            ComposerSheetView(account: account)
                .environmentObject(store)
                .frame(maxWidth: 980, maxHeight: 760)
                .padding(34)
                .transition(
                    .opacity.combined(
                        with: .scale(scale: reduceMotion ? 1 : 0.78, anchor: .topLeading)
                    )
                )
        }
        .animation(MosaicMotion.expressive(reduceMotion: reduceMotion), value: store.isComposerSheetPresented)
    }

    private func switchAccount(to accountID: UUID) {
        guard accountID != store.activeAccountID else {
            return
        }

        guard !reduceMotion else {
            store.switchAccount(to: accountID)
            return
        }

        withAnimation(.easeOut(duration: 0.1)) {
            isDeckTransitioning = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            store.switchAccount(to: accountID)
            withAnimation(MosaicMotion.structural(reduceMotion: false)) {
                isDeckTransitioning = false
            }
        }
    }

    private func beginLayoutResetReveal() {
        guard !reduceMotion else {
            resetRevealCount = nil
            layoutResetAnimationID = nil
            return
        }

        let animationID = UUID()
        layoutResetAnimationID = animationID
        resetRevealCount = 0

        for index in store.columns.indices {
            let delay = min(Double(index) * 0.035, 0.14)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard layoutResetAnimationID == animationID else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    resetRevealCount = max(resetRevealCount ?? 0, index + 1)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            guard layoutResetAnimationID == animationID else { return }
            resetRevealCount = nil
            layoutResetAnimationID = nil
        }
    }

    private func isResetTileVisible(at index: Int) -> Bool {
        guard let resetRevealCount else { return true }
        return index < resetRevealCount
    }

    private var addColumnPrimaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.84)
    }

    private var addColumnSecondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.64)
    }

    private func dragOffset(for columnID: UUID) -> CGFloat {
        guard let draggingColumnID,
              let sourceIndex = dragSourceIndex,
              let targetIndex = dragTargetIndex else {
            return 0
        }

        if columnID == draggingColumnID {
            return dragTranslation
        }

        guard let columnIndex = dragColumnOrder.firstIndex(of: columnID) else {
            return 0
        }

        let draggedSlotWidth = (dragColumnWidths[draggingColumnID] ?? 0) + columnSpacing

        if targetIndex > sourceIndex,
           columnIndex > sourceIndex,
           columnIndex <= targetIndex {
            return -draggedSlotWidth
        }

        if targetIndex < sourceIndex,
           columnIndex >= targetIndex,
           columnIndex < sourceIndex {
            return draggedSlotWidth
        }

        return 0
    }

    private func beginColumnDrag(_ columnID: UUID) {
        if draggingColumnID == nil {
            let order = store.columns.map(\.id)
            let sourceIndex = order.firstIndex(of: columnID)

            draggingColumnID = columnID
            dragTranslation = 0
            dragColumnOrder = order
            dragColumnWidths = Dictionary(
                uniqueKeysWithValues: store.columns.map { ($0.id, CGFloat($0.width)) }
            )
            dragSourceIndex = sourceIndex
            dragTargetIndex = sourceIndex
        }
    }

    private func updateColumnDrag(_ columnID: UUID, translation rawTranslation: CGFloat) {
        guard draggingColumnID == columnID, !isColumnDragSettling else {
            return
        }

        dragTranslation = rawTranslation

        let newTargetIndex = targetIndex(for: columnID, translation: rawTranslation)
        guard newTargetIndex != dragTargetIndex else {
            return
        }

        withAnimation(MosaicMotion.structural(reduceMotion: reduceMotion)) {
            dragTargetIndex = newTargetIndex
        }
    }

    private func endColumnDrag(_ columnID: UUID) {
        guard draggingColumnID == columnID else {
            return
        }

        let landingOffset = landingOffsetForDraggedColumn()
        let duration = reduceMotion ? 0.12 : 0.36
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: duration)) {
            isColumnDragSettling = true
            dragTranslation = landingOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            commitColumnDrag(columnID)
        }
    }

    private func targetIndex(for columnID: UUID, translation: CGFloat) -> Int? {
        guard let sourceIndex = dragSourceIndex,
              dragColumnOrder.indices.contains(sourceIndex) else {
            return nil
        }

        let draggedWidth = dragColumnWidths[columnID] ?? 0
        let draggedCenter = leadingOffset(for: sourceIndex) + (draggedWidth / 2) + translation
        var targetIndex = sourceIndex

        for index in dragColumnOrder.indices where index != sourceIndex {
            let id = dragColumnOrder[index]
            let width = dragColumnWidths[id] ?? 0
            let center = leadingOffset(for: index) + (width / 2)

            if index < sourceIndex, draggedCenter < center {
                targetIndex = index
                break
            }

            if index > sourceIndex, draggedCenter > center {
                targetIndex = index
            }
        }

        return targetIndex
    }

    private func leadingOffset(for index: Int) -> CGFloat {
        guard index > 0 else {
            return 0
        }

        return dragColumnOrder[..<index].reduce(0) { offset, id in
            offset + (dragColumnWidths[id] ?? 0) + columnSpacing
        }
    }

    private func landingOffsetForDraggedColumn() -> CGFloat {
        guard let sourceIndex = dragSourceIndex,
              let targetIndex = dragTargetIndex else {
            return 0
        }

        if targetIndex > sourceIndex {
            return dragColumnOrder[(sourceIndex + 1)...targetIndex].reduce(0) { offset, id in
                offset + (dragColumnWidths[id] ?? 0) + columnSpacing
            }
        }

        if targetIndex < sourceIndex {
            return -dragColumnOrder[targetIndex..<sourceIndex].reduce(0) { offset, id in
                offset + (dragColumnWidths[id] ?? 0) + columnSpacing
            }
        }

        return 0
    }

    private func commitColumnDrag(_ columnID: UUID) {
        guard draggingColumnID == columnID,
              let targetIndex = dragTargetIndex,
              let currentIndex = store.columns.firstIndex(where: { $0.id == columnID }) else {
            resetColumnDrag()
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if targetIndex != currentIndex {
                store.columns.move(
                    fromOffsets: IndexSet(integer: currentIndex),
                    toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
                )
            }
            resetColumnDrag()
        }
    }

    private func resetColumnDrag() {
        draggingColumnID = nil
        dragTranslation = 0
        dragColumnOrder = []
        dragColumnWidths = [:]
        dragSourceIndex = nil
        dragTargetIndex = nil
        isColumnDragSettling = false
    }

    private var settingsColumnBinding: Binding<DeckColumn?> {
        Binding<DeckColumn?>(
            get: {
                guard let settingsColumnID else {
                    return nil
                }
                return store.columns.first(where: { $0.id == settingsColumnID })
            },
            set: { value in
                settingsColumnID = value?.id
            }
        )
    }

    private var loginAccountBinding: Binding<DeckAccount?> {
        Binding<DeckAccount?>(
            get: {
                guard hasFinishedLaunchPresentation,
                      let accountID = store.presentedLoginAccountID else {
                    return nil
                }
                return store.account(with: accountID)
            },
            set: { value in
                guard hasFinishedLaunchPresentation else { return }
                if let value {
                    store.presentLoginFlow(for: value.id)
                } else {
                    store.dismissLoginFlow()
                }
            }
        )
    }

    private var quickPanelBinding: Binding<QuickPanelDestination?> {
        Binding<QuickPanelDestination?>(
            get: { store.quickPanelDestination },
            set: { value in
                if value == nil {
                    store.dismissQuickPanel()
                }
            }
        )
    }
}
