import SwiftUI

struct EmptyDeckView: View {
    let onAddColumn: (DeckColumnType) -> Void

    var body: some View {
        MosaicEmptyState(
            symbol: "square.grid.2x2",
            title: "A clear canvas",
            detail: "Add Home, Search, Profile, or List tiles to shape your workspace."
        ) {
            AddColumnTypeMenu(onSelect: onAddColumn) {
                Text("Add First Column")
            }
            .buttonStyle(MosaicButtonStyle(kind: .prominent))
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Add First Column")
        }
        .padding(28)
    }
}
