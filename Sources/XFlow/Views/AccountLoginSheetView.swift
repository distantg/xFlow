import SwiftUI

struct AccountLoginSheetView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
                .overlay(MosaicTheme.hairline(for: colorScheme))

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
        .background(MosaicSurface(level: .base, cornerRadius: 0))
        .onAppear {
            checkAuthStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isAuthenticated ? "checkmark.shield.fill" : "person.badge.key.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isAuthenticated ? Color.green : MosaicTheme.activeAccent(for: colorScheme))

            VStack(alignment: .leading, spacing: 4) {
                Text("Sign In to X")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text("Log in once for \(account.name). This account will be shared by all columns.")
                    .font(.caption)
                    .foregroundStyle(MosaicTheme.secondaryText(for: colorScheme))

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
            .buttonStyle(MosaicButtonStyle(compact: true))

            Button("Check Status") {
                checkAuthStatus()
            }
            .buttonStyle(MosaicButtonStyle(compact: true))

            Button("Continue") {
                store.markAccountSignedIn(accountID: account.id)
                dismiss()
            }
            .buttonStyle(MosaicButtonStyle(kind: .prominent, compact: true))
            .disabled(!isAuthenticated)

            Button("Cancel") {
                store.dismissLoginFlow()
                dismiss()
            }
            .buttonStyle(MosaicButtonStyle(kind: .quiet, compact: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MosaicSurface(level: .raised, cornerRadius: 0))
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
