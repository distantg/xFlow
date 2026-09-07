import SwiftUI

/// Shared dimming layer for compose and expanded images. The deck beneath
/// these overlays supplies the blur so the modal content remains sharp.
struct MosaicModalBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Color.black.opacity(reduceTransparency
            ? (colorScheme == .dark ? 0.48 : 0.28)
            : (colorScheme == .dark ? 0.22 : 0.10))
    }
}
