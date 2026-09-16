import JavaScriptCore
import XCTest
@testable import XFlow

final class ColumnScrollUpdateTests: XCTestCase {
    func testFastScrollEventsUseLatestPositionOncePerFrameAndCancelOnRemoval() throws {
        let script = WebColumnView.Coordinator.integratedColumnThemeScript
        let start = try XCTUnwrap(script.range(of: "function installTopTabInteraction()"))
        let end = try XCTUnwrap(script.range(of: "markGrokComposer();", range: start.upperBound..<script.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        const frames = new Map();
        let nextFrame = 1;
        let updates = [];
        let captures = 0;
        const document = { addEventListener() {} };
        const window = { addEventListener() {} };
        function requestAnimationFrame(callback) { const id = nextFrame++; frames.set(id, callback); return id; }
        function cancelAnimationFrame(id) { frames.delete(id); }
        function flush() { const pending = Array.from(frames.values()); frames.clear(); pending.forEach(f => f()); }
        function updateTopTabScrollState(target) { updates.push(target.position); }
        function postTopTabCapture() { captures++; }
        """)
        context.evaluateScript(String(script[start.lowerBound..<end.lowerBound]))
        context.evaluateScript("""
        installTopTabInteraction();
        const handlers = globalThis.__mosaicTopTabHandlers;
        for (let i = 0; i < 100; i++) handlers.scroll({ target: { position: i } });
        """)
        XCTAssertNil(context.exception)
        XCTAssertEqual(context.evaluateScript("frames.size")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("updates.length")?.toInt32(), 0)
        context.evaluateScript("flush();")
        XCTAssertEqual(context.evaluateScript("updates.join(',')")?.toString(), "99")
        XCTAssertEqual(context.evaluateScript("captures")?.toInt32(), 1)
        context.evaluateScript("handlers.scroll({target:{position:120}}); flush();")
        XCTAssertEqual(context.evaluateScript("updates.join(',')")?.toString(), "99,120")
        context.evaluateScript("handlers.scroll({target:{position:130}}); handlers.cancelScroll(); flush();")
        XCTAssertEqual(context.evaluateScript("updates.join(',')")?.toString(), "99,120")
        XCTAssertEqual(context.evaluateScript("frames.size")?.toInt32(), 0)
        XCTAssertNil(context.exception)
    }
}
