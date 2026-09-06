import SwiftUI

struct EmptyDeckView: View {
    let onAddColumn: () -> Void

    var body: some View {
        MosaicEmptyState(
            symbol: "square.grid.2x2",
            title: "A clear canvas",
            detail: "Add Home, Search, Profile, or List tiles to shape your workspace.",
            actionTitle: "Add First Column",
            action: onAddColumn
        )
        .padding(28)
    }
}
