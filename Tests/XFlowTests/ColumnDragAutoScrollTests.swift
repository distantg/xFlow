import XCTest
@testable import XFlow

final class ColumnDragAutoScrollTests: XCTestCase {
    func testOnlyEdgesScrollAndSpeedIncreasesTowardEdge() {
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: 500, viewportWidth: 1000), 0)
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: 80, viewportWidth: 1000), 0)
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: 920, viewportWidth: 1000), 0)
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: 40, viewportWidth: 1000), -360)
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: 960, viewportWidth: 1000), 360)
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: -30, viewportWidth: 1000), -720)
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: 1030, viewportWidth: 1000), 720)
    }

    func testHeldPointerKeepsScrollingInBothDirectionsUntilContentBoundary() {
        var offset: CGFloat = 0
        for _ in 0..<120 {
            offset = ColumnDragAutoScroll.offset(current: offset, velocity: 720, elapsed: 1.0 / 60, minimum: 0, maximum: 1000)
        }
        XCTAssertEqual(offset, 1000)
        for _ in 0..<120 {
            offset = ColumnDragAutoScroll.offset(current: offset, velocity: -720, elapsed: 1.0 / 60, minimum: 0, maximum: 1000)
        }
        XCTAssertEqual(offset, 0)
    }

    func testSmallViewportAndDelayedTickStayBounded() {
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: 30, viewportWidth: 60), 0)
        XCTAssertEqual(ColumnDragAutoScroll.velocity(pointerX: 0, viewportWidth: 0), 0)
        XCTAssertEqual(ColumnDragAutoScroll.offset(current: 100, velocity: 720, elapsed: 5, minimum: 0, maximum: 1000), 136)
        XCTAssertEqual(ColumnDragAutoScroll.offset(current: 0, velocity: 720, elapsed: 1, minimum: 0, maximum: 0), 0)
    }
}
