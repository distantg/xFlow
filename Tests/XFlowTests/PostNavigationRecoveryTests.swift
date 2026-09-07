import JavaScriptCore
import XCTest
@testable import XFlow

final class PostNavigationRecoveryTests: XCTestCase {
    func testOnlyEmptyCompletedPostSpinnerCanRecover() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        let primaryExists = true, protectedContent = false, spinner = true;
        const document = { hidden: false, readyState: 'complete', querySelector() {
          return primaryExists ? { querySelector(selector) {
            return selector === '[role="progressbar"]' ? spinner : protectedContent;
          }} : null;
        }};
        """)
        let script = WebColumnView.Coordinator.stalledPostScript
        XCTAssertEqual(context.evaluateScript(script)?.toBool(), true)
        context.evaluateScript("protectedContent = true")
        XCTAssertEqual(context.evaluateScript(script)?.toBool(), false)
        context.evaluateScript("protectedContent = false; spinner = false")
        XCTAssertEqual(context.evaluateScript(script)?.toBool(), false)
        context.evaluateScript("spinner = true; document.readyState = 'loading'")
        XCTAssertEqual(context.evaluateScript(script)?.toBool(), false)
        context.evaluateScript("document.readyState = 'complete'; document.hidden = true")
        XCTAssertEqual(context.evaluateScript(script)?.toBool(), false)
        context.evaluateScript("document.hidden = false; primaryExists = false")
        XCTAssertEqual(context.evaluateScript(script)?.toBool(), false)
        XCTAssertNil(context.exception)
    }
}
