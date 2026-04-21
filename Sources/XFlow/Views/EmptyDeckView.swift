import SwiftUI

struct EmptyDeckView: View {
    let onAddColumn: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("No Columns Yet")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text("Build your own deck by adding Home, Search, Profile, or List columns.")
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            Button("Add First Column") {
                onAddColumn()
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
