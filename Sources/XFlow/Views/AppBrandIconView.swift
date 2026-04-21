import AppKit
import SwiftUI

struct AppBrandIconView: View {
    var body: some View {
        Group {
            if let image = loadBrandImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text("X")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .frame(width: 54, height: 54)
    }

    private func loadBrandImage() -> NSImage? {
        if let explicit = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: explicit) {
            return image
        }

        return NSImage(named: "AppIcon")
    }
}
