import JavaScriptCore
import XCTest
@testable import XFlow

final class AccountIdentityScriptTests: XCTestCase {
    private func extract(profile: String) throws -> String {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(#"""
        var result;
        var Promise = function(body) { body(function(value) { result = value; }); };
        var setTimeout = function(callback) { callback(); };
        var window = { location: { pathname: '/random_user/status/123' } };
        var document = {
          title: 'Random (@random_user)',
          documentElement: { innerHTML: '"screen_name":"random_user"' },
          querySelector: function(selector) {
            if (selector === 'a[data-testid="AppTabBar_Profile_Link"]' && PROFILE) {
              return { getAttribute: function() { return PROFILE; }, querySelector: function() { return null; } };
            }
            return null;
          }
        };
        """#)
        context.setObject(profile, forKeyedSubscript: "PROFILE" as NSString)
        context.evaluateScript(AccountIdentityScript.extractionScript)
        XCTAssertNil(context.exception)
        let payload = try XCTUnwrap(context.objectForKeyedSubscript("result")?.toString()?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: String])
        return try XCTUnwrap(json["handle"])
    }

    func testFeedAndVisitedProfileNeverBecomeAccountIdentity() throws {
        XCTAssertEqual(try extract(profile: ""), "")
    }

    func testAccountProfileControlWinsOverFeedContent() throws {
        XCTAssertEqual(try extract(profile: "/actual_owner"), "actual_owner")
    }
}
