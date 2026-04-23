import SwiftUI

struct AccountLoginSheetView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss

    let account: DeckAccount

    @State private var refreshKey = UUID()
    @State private var isChecking = false
    @State private var isAuthenticated = false
    @State private var didComplete = false

    private let loginURL = URL(string: "https://x.com/i/flow/login")!

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.12))

            WebColumnView(
                url: loginURL,
                refreshKey: refreshKey.uuidString,
                accountID: account.id,
                filter: .none,
                onNavigation: { url in
                    store.captureHandle(for: account.id, from: url)
                    checkAuthStatus()
                },
                onDetectedHandle: { handle in
                    store.setHandle(accountID: account.id, handle: handle)
                },
                onDetectedProfileImage: { imageURL in
                    store.setProfileImage(accountID: account.id, imageURL: imageURL)
                },
                enableChromeStripping: false,
                enableMediaCapture: false,
                enableHandleDetection: true,
                enableBroadHandleDetection: true
            )
            .id("login-\(account.id.uuidString)")
        }
        .frame(minWidth: 920, minHeight: 720)
        .onAppear {
            checkAuthStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign In to X")
                    .font(.title3.weight(.bold))

                Text("Log in once for \(account.name). This account will be shared by all columns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(isAuthenticated ? "Login detected" : "Waiting for login")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isAuthenticated ? .green : .orange)
            }

            Spacer()

            if isChecking {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Refresh") {
                refreshKey = UUID()
            }

            Button("Check Status") {
                checkAuthStatus()
            }

            Button("Continue") {
                store.markAccountSignedIn(accountID: account.id)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isAuthenticated)

            Button("Cancel") {
                store.dismissLoginFlow()
                dismiss()
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18))
    }

    private func checkAuthStatus() {
        guard !isChecking, !didComplete else {
            return
        }

        isChecking = true

        store.refreshAuthenticationState(for: account.id, shouldPromptIfNeeded: false) { authenticated in
            isAuthenticated = authenticated
            isChecking = false

            if authenticated {
                didComplete = true
                store.markAccountSignedIn(accountID: account.id)
                dismiss()
            }
        }
    }
}
