import SwiftUI

struct AccountLockedDeckView: View {
    let accountName: String
    let onOpenLogin: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Sign in required")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text("Complete X login for \(accountName) to load all columns.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))

            Button("Open Login") {
                onOpenLogin()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
