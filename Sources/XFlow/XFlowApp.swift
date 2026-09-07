import SwiftUI

@main
struct XFlowApp: App {
    @NSApplicationDelegateAdaptor(XFlowAppDelegate.self) private var appDelegate
    @StateObject private var store = DeckStore()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        Window("Mosaic", id: "main") {
            MainDeckView()
                .environmentObject(store)
                .environmentObject(updateManager)
                .preferredColorScheme(store.appearanceMode.preferredColorScheme)
                .frame(minWidth: 1200, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            DeckCommands(store: store)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updateManager.checkManually() }
                    .disabled(!updateManager.canCheckForUpdates)
            }
        }

        Settings {
            MosaicSettingsView()
                .environmentObject(store)
                .environmentObject(updateManager)
                .preferredColorScheme(store.appearanceMode.preferredColorScheme)
        }
    }
}

struct DeckCommands: Commands {
    @ObservedObject var store: DeckStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Column") {
                store.presentAddColumnSheet()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Accounts") {
            Button("Add Account") {
                store.addAccount()
            }

            Divider()

            ForEach(store.accounts) { account in
                Button(account.name) {
                    store.switchAccount(to: account.id)
                }
            }
        }

        CommandMenu("Columns") {
            Button("Refresh All") {
                store.refreshAllColumns()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Compose") {
                store.presentComposer()
            }
            .keyboardShortcut("p", modifiers: .command)

            Divider()

            Button("Reset To Starter Layout") {
                store.resetToStarterColumns()
            }

            Button("Clear All Columns") {
                store.clearColumns()
            }
        }
    }
}
