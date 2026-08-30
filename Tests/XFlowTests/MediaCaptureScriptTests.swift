import JavaScriptCore
import XCTest
@testable import XFlow

final class MediaCaptureScriptTests: XCTestCase {
    func testMediaCaptureScriptHasValidJavaScriptSyntax() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [WebColumnView.Coordinator.mediaCaptureScript]
        )
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        let scriptArgument = String(encoded.dropFirst().dropLast())
        let context = try XCTUnwrap(JSContext())

        var exception: JSValue?
        context.exceptionHandler = { _, value in
            exception = value
        }
        context.evaluateScript("new Function(\(scriptArgument))")

        XCTAssertNil(exception, exception?.toString() ?? "Unexpected JavaScript syntax error")
    }
}
