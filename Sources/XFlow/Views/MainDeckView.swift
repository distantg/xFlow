import SwiftUI

struct MainDeckView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var settingsColumnID: UUID?
    @State private var draggingColumnID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartIndex: Int?
    @State private var dragSlotWidth: CGFloat = 360
    @State private var dragShiftedSlots = 0
    @State private var mediaRequest: MediaRequest?
    @State private var ambientPulse = false
    @StateObject private var updateManager = UpdateManager()

    private let columnSpacing: CGFloat = 14

    var body: some View {
        ZStack {
            backgroundLayer

            HStack(spacing: 0) {
                SidebarView(
                    accounts: store.accounts,
                    activeAccountID: store.activeAccountID,
                    appearanceMode: store.appearanceMode,
                    onSwitchAccount: { id in
                        store.switchAccount(to: id)
                    },
                    onAddAccount: {
                        store.addAccount()
                    },
                    onRemoveAccount: { id in
                        store.removeAccount(id)
                    },
                    onQuickAction: { action in
                        store.handleSidebarAction(action)
                    },
                    onAppearanceModeChange: { mode in
                        store.setAppearanceMode(mode)
                    },
                    isCheckingForUpdates: updateManager.isChecking,
                    onCheckUpdates: {
                        Task {
                            await updateManager.checkManually()
                        }
                    }
                )
                .zIndex(100)

                Divider()
                    .overlay(Color.white.opacity(0.12))
                    .zIndex(90)

                content
                    .zIndex(0)
            }
            .ignoresSafeArea(.container, edges: .top)
            .background(deckGlassBackground)
        }
        .overlay(alignment: .topLeading) {
            TransparentWindowConfigurator()
                .frame(width: 0, height: 0)
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
            AddColumnSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isComposerSheetPresented) {
            if let activeAccount = store.activeAccount {
                ComposerSheetView(account: activeAccount)
                    .environmentObject(store)
            }
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
            store.refreshAuthenticationState(for: store.activeAccountID, shouldPromptIfNeeded: true)
            withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                ambientPulse = true
            }
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
    }

    private var backgroundLayer: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.16))
                .blur(radius: 120)
                .frame(width: 470, height: 470)
                .scaleEffect(ambientPulse ? 1.12 : 0.88)
                .offset(x: -360, y: -260)

            Circle()
                .fill(Color.purple.opacity(0.14))
                .blur(radius: 110)
                .frame(width: 520, height: 520)
                .scaleEffect(ambientPulse ? 0.9 : 1.1)
                .offset(x: 430, y: 310)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .blur(radius: 95)
                .frame(width: 420, height: 420)
                .scaleEffect(ambientPulse ? 1.08 : 0.9)
                .offset(x: 120, y: -340)
        }
    }

    private var deckGlassBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.08),
                    Color.purple.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        GeometryReader { proxy in
            contentBody(columnHeight: max(0, proxy.size.height - 28))
        }
    }

    @ViewBuilder
    private func contentBody(columnHeight: CGFloat) -> some View {
        if activeAccountNeedsLogin {
            AccountLockedDeckView(
                accountName: store.activeAccount?.name ?? "Account",
                onOpenLogin: {
                    if let activeID = store.activeAccount?.id {
                        store.presentLoginFlow(for: activeID)
                    }
                }
            )
        } else if store.columns.isEmpty {
            EmptyDeckView {
                store.presentAddColumnSheet()
            }
        } else {
            deckScrollView(columnHeight: columnHeight)
        }
    }

    private func deckScrollView(columnHeight: CGFloat) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(store.columns) { column in
                        columnCard(
                            column,
                            renderAccountID: store.activeAccountID,
                            columnHeight: columnHeight
                        )
                    }

                    addColumnTile
                        .frame(width: 220, height: columnHeight)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 14)
            }
            .scrollDisabled(draggingColumnID != nil)
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
        columnHeight: CGFloat
    ) -> some View {
        ColumnCardView(
            column: column,
            globalRefreshSignal: store.refreshSignal,
            activeAccountID: renderAccountID,
            onRemove: {
                store.removeColumn(id: column.id)
            },
            onDuplicate: {
                store.duplicateColumn(id: column.id)
            },
            onMoveLeft: {
                store.shiftColumn(id: column.id, by: -1)
            },
            onMoveRight: {
                store.shiftColumn(id: column.id, by: 1)
            },
            onWiden: {
                store.adjustWidth(for: column.id, delta: 30)
            },
            onNarrow: {
                store.adjustWidth(for: column.id, delta: -30)
            },
            onConfigure: {
                settingsColumnID = column.id
            },
            onCompose: {
                store.presentComposer()
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
            )
        )
        .id(column.id)
        .frame(width: column.width, height: columnHeight)
        .offset(x: dragOffset(for: column.id))
        .scaleEffect(draggingColumnID == column.id ? 1.015 : 1)
        .zIndex(draggingColumnID == column.id ? 15 : 0)
    }

    private func notificationHandler(
        for column: DeckColumn,
        accountID: UUID
    ) -> ((Int, String?) -> Void)? {
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
        Button {
            store.presentAddColumnSheet()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                Text("Add Column")
                    .font(.headline)
                Text("Home, Search, Profile, List")
                    .font(.caption)
                    .foregroundStyle(addColumnSecondaryTextColor)
            }
            .foregroundStyle(addColumnPrimaryTextColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.1, dash: [7, 5]),
                        antialiased: true
                    )
                    .foregroundStyle(addColumnBorderColor)
            )
        }
        .buttonStyle(.plain)
    }

    private var addColumnPrimaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.84)
    }

    private var addColumnSecondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.64)
    }

    private var addColumnBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.22)
    }

    private func dragOffset(for columnID: UUID) -> CGFloat {
        draggingColumnID == columnID ? dragTranslation : 0
    }

    private func beginColumnDrag(_ columnID: UUID) {
        if draggingColumnID == nil {
            draggingColumnID = columnID
            dragTranslation = 0
            dragStartIndex = store.columns.firstIndex(where: { $0.id == columnID })
            dragShiftedSlots = 0
            if let startIndex = dragStartIndex {
                dragSlotWidth = CGFloat(store.columns[startIndex].width) + columnSpacing
            } else {
                dragSlotWidth = 360
            }
        }
    }

    private func updateColumnDrag(_ columnID: UUID, translation rawTranslation: CGFloat) {
        guard draggingColumnID == columnID else {
            return
        }

        reorderColumnsIfNeeded(for: columnID, rawTranslation: rawTranslation)
    }

    private func endColumnDrag(_ columnID: UUID) {
        guard draggingColumnID == columnID else {
            return
        }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            dragTranslation = 0
        }
        dragStartIndex = nil
        dragSlotWidth = 360
        dragShiftedSlots = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if draggingColumnID == columnID {
                draggingColumnID = nil
            }
        }
    }

    private func reorderColumnsIfNeeded(for columnID: UUID, rawTranslation: CGFloat) {
        guard let startIndex = dragStartIndex else {
            dragTranslation = rawTranslation
            return
        }

        let safeSlotWidth = max(140, dragSlotWidth)
        let minShift = -startIndex
        let maxShift = (store.columns.count - 1) - startIndex

        var shiftedSlots = dragShiftedSlots
        let trigger: CGFloat = 0.68

        while shiftedSlots < maxShift,
              rawTranslation >= (CGFloat(shiftedSlots) + trigger) * safeSlotWidth {
            shiftedSlots += 1
        }

        while shiftedSlots > minShift,
              rawTranslation <= (CGFloat(shiftedSlots) - trigger) * safeSlotWidth {
            shiftedSlots -= 1
        }

        dragTranslation = rawTranslation - (CGFloat(shiftedSlots) * safeSlotWidth)

        guard let currentIndex = store.columns.firstIndex(where: { $0.id == columnID }) else {
            return
        }

        let desiredIndex = max(0, min(store.columns.count - 1, startIndex + shiftedSlots))
        guard desiredIndex != currentIndex else {
            dragShiftedSlots = shiftedSlots
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            store.columns.move(
                fromOffsets: IndexSet(integer: currentIndex),
                toOffset: desiredIndex > currentIndex ? desiredIndex + 1 : desiredIndex
            )
        }
        dragShiftedSlots = shiftedSlots
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
                guard let accountID = store.presentedLoginAccountID else {
                    return nil
                }
                return store.account(with: accountID)
            },
            set: { value in
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
