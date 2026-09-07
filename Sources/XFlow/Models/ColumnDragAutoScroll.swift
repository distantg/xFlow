import Foundation

/// Points per second, increasing as the pointer approaches either viewport edge.
enum ColumnDragAutoScroll {
    static func velocity(pointerX: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        guard viewportWidth > 0 else { return 0 }
        let edgeWidth = min(CGFloat(80), viewportWidth / 3)
        if pointerX < edgeWidth {
            return -720 * min(1, max(0, (edgeWidth - pointerX) / edgeWidth))
        }
        if pointerX > viewportWidth - edgeWidth {
            return 720 * min(1, max(0, (pointerX - viewportWidth + edgeWidth) / edgeWidth))
        }
        return 0
    }

    static func offset(current: CGFloat, velocity: CGFloat, elapsed: TimeInterval, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(maximum, max(minimum, current + velocity * min(max(elapsed, 0), 0.05)))
    }
}
