import CoreGraphics
import Foundation

enum ColumnResidencyPolicy {
    static func desiredLiveColumnIDs(
        columns: [DeckColumn],
        frames: [UUID: CGRect],
        viewportSize: CGSize,
        columnSpacing: CGFloat
    ) -> Set<UUID> {
        guard viewportSize.width > 0 else {
            return fallbackIDs(columns: columns)
        }

        let overscan = CGFloat(DeckColumn.defaultWidth * 0.75) + columnSpacing
        let liveViewport = CGRect(
            x: -overscan,
            y: -1,
            width: viewportSize.width + (overscan * 2),
            height: max(1, viewportSize.height + 2)
        )

        var desired = Set(frames.compactMap { id, frame in
            frame.intersects(liveViewport) ? id : nil
        })
        desired.formUnion(columns.compactMap { column in
            isBackgroundMonitor(column) ? column.id : nil
        })

        if desired.isEmpty {
            desired = fallbackIDs(columns: columns)
        }
        return desired
    }

    static func isBackgroundMonitor(_ column: DeckColumn) -> Bool {
        column.type == .notifications || column.type == .messages
    }

    private static func fallbackIDs(columns: [DeckColumn]) -> Set<UUID> {
        var ids = Set(columns.prefix(3).map(\.id))
        ids.formUnion(columns.compactMap { isBackgroundMonitor($0) ? $0.id : nil })
        return ids
    }
}
