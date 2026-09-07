import JavaScriptCore
import XCTest
@testable import XFlow

final class XListDiscoveryServiceTests: XCTestCase {
    func testListsIndexURLUsesOnlyAValidatedActiveAccountHandle() {
        XCTAssertEqual(
            XListDiscoveryService.listsIndexURL(forHandle: "@example_user")?.absoluteString,
            "https://x.com/example_user/lists"
        )
        XCTAssertNil(XListDiscoveryService.listsIndexURL(forHandle: nil))
        XCTAssertNil(XListDiscoveryService.listsIndexURL(forHandle: "not/a/handle"))
    }

    func testExtractionScriptHasValidJavaScriptSyntax() throws {
        let context = try XCTUnwrap(JSContext())
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }

        let script = XListDiscoveryService.extractionScript
        let data = try JSONSerialization.data(withJSONObject: [script])
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        context.evaluateScript("new Function(\(String(encoded.dropFirst().dropLast())))")

        XCTAssertNil(exception, exception?.toString() ?? "Unexpected JavaScript syntax error")
    }

    func testPayloadParserKeepsOnlyCanonicalTrustedListChoices() throws {
        let payload = """
        [
          {
            "name": "  Macro Traders\\n@owner  ",
            "url": "https://www.x.com/i/lists/123?ref=home#selection"
          },
          {
            "name": "Duplicate",
            "url": "https://x.com/i/lists/123"
          },
          {
            "name": "Untrusted",
            "url": "https://x.com.evil.example/i/lists/456"
          },
          {
            "name": "",
            "url": "https://x.com/list_owner/lists/alpha-list"
          },
          {
            "name": "Directory",
            "url": "https://x.com/i/lists"
          },
          {
            "name": "Create a new List",
            "url": "https://x.com/i/lists/create"
          },
          {
            "name": "Show more",
            "url": "https://x.com/i/lists/suggested"
          }
        ]
        """

        let choices = try XCTUnwrap(XListDiscoveryService.parseListPayload(payload))

        XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(choices[0].name, "Macro Traders")
        XCTAssertEqual(choices[0].url.absoluteString, "https://x.com/i/lists/123")
        XCTAssertEqual(choices[1].name, "List alpha-list")
        XCTAssertEqual(choices[1].url.absoluteString, "https://x.com/list_owner/lists/alpha-list")
    }

    func testPayloadParserRejectsMalformedAndOversizedResponses() {
        XCTAssertNil(XListDiscoveryService.parseListPayload("not-json"))
        XCTAssertNil(XListDiscoveryService.parseListPayload(String(repeating: "x", count: 512 * 1024 + 1)))
    }
}
