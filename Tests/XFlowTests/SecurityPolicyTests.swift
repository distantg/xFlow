import Foundation
import JavaScriptCore
import XCTest
@testable import XFlow

final class SecurityPolicyTests: XCTestCase {
    func testXPagePolicyRejectsLookalikeAndInsecureHosts() {
        XCTAssertTrue(TrustedURLPolicy.isTrustedXPage(url("https://x.com/home")))
        XCTAssertFalse(TrustedURLPolicy.isTrustedXPage(url("http://x.com/home")))
        XCTAssertFalse(TrustedURLPolicy.isTrustedXPage(url("https://x.com.evil.example/home")))
        XCTAssertFalse(TrustedURLPolicy.isTrustedXPage(url("https://evilx.com/home")))
        XCTAssertFalse(TrustedURLPolicy.isTrustedXPage(url("https://user@x.com/home")))
        XCTAssertFalse(TrustedURLPolicy.isTrustedXPage(url("https://.x.com/home")))
        XCTAssertFalse(TrustedURLPolicy.isTrustedXPage(url("https://x.com./home")))
    }

    func testSubframePolicyRejectsInsecureAndActiveContentSchemes() {
        XCTAssertTrue(TrustedURLPolicy.isSafeSubframeURL(url("https://accounts.google.com/frame")))
        XCTAssertTrue(TrustedURLPolicy.isSafeSubframeURL(url("about:blank")))
        XCTAssertTrue(TrustedURLPolicy.isSafeSubframeURL(url("blob:https://x.com/example")))
        XCTAssertFalse(TrustedURLPolicy.isSafeSubframeURL(url("http://example.com/frame")))
        XCTAssertFalse(TrustedURLPolicy.isSafeSubframeURL(url("data:text/html,unsafe")))
        XCTAssertFalse(TrustedURLPolicy.isSafeSubframeURL(url("javascript:alert(1)")))
    }

    func testMediaPolicyAllowsOnlyExpectedXCDNHosts() {
        XCTAssertTrue(
            TrustedURLPolicy.isTrustedImageMediaURL(
                url("https://pbs.twimg.com/media/Example?format=jpg&name=small")
            )
        )
        XCTAssertTrue(
            TrustedURLPolicy.isTrustedVideoMediaURL(
                url("https://video.twimg.com/ext_tw_video/123/pu/vid/test.mp4")
            )
        )
        XCTAssertFalse(
            TrustedURLPolicy.isTrustedVideoMediaURL(
                url("https://video.twimg.com.evil.example/test.mp4")
            )
        )
        XCTAssertFalse(
            TrustedURLPolicy.isTrustedVideoMediaURL(
                url("https://example.com/test.mp4")
            )
        )
    }

    func testBridgeRejectsUntrustedImageAndPostURLs() {
        XCTAssertNil(
            MediaRequest.validatedBridgeRequest(
                kind: .image,
                url: url("https://example.com/tracker.jpg"),
                currentTime: 0,
                mediaURL: nil
            )
        )
        XCTAssertNil(
            MediaRequest.validatedBridgeRequest(
                kind: .video,
                url: url("https://x.com.evil.example/post"),
                currentTime: 1,
                mediaURL: url("https://video.twimg.com/test.mp4")
            )
        )
    }

    func testBridgeDropsUntrustedDirectVideoButKeepsTrustedPermalinkFallback() throws {
        let request = try XCTUnwrap(
            MediaRequest.validatedBridgeRequest(
                kind: .video,
                url: url("https://x.com/example/status/123"),
                currentTime: 42,
                mediaURL: url("https://example.com/video.mp4")
            )
        )
        XCTAssertNil(request.mediaURL)
        XCTAssertEqual(request.currentTime, 42)
    }

    func testSavedColumnURLsCannotEscapeX() {
        XCTAssertEqual(
            DeckColumnType.list.buildURL(parameter: "file:///etc/passwd").absoluteString,
            "https://x.com/i/lists"
        )
        XCTAssertEqual(
            DeckColumnType.list.buildURL(parameter: "https://evil.example/i/lists/123").absoluteString,
            "https://x.com/i/lists"
        )
        XCTAssertEqual(
            DeckColumnType.list.buildURL(parameter: "123").absoluteString,
            "https://x.com/i/lists/123"
        )
        XCTAssertEqual(
            DeckColumnType.profile.buildURL(parameter: "../../etc/passwd").absoluteString,
            "https://x.com/x"
        )
    }

    func testUpdateURLsArePinnedToTheExpectedRepository() {
        XCTAssertTrue(
            TrustedURLPolicy.isTrustedUpdateManifestURL(
                url("https://raw.githubusercontent.com/distantg/xFlow/main/update-manifest.json")
            )
        )
        XCTAssertTrue(
            TrustedURLPolicy.isTrustedGitHubReleaseURL(
                url("https://github.com/distantg/xFlow/releases/tag/v1.3.0")
            )
        )
        XCTAssertFalse(
            TrustedURLPolicy.isTrustedGitHubReleaseURL(
                url("https://github.com/attacker/xFlow/releases/tag/v9.9.9")
            )
        )
    }

    func testPushEndpointRequiresTLSExceptForLoopbackDevelopment() {
        XCTAssertNotNil(XFlowPushBackendClient.validatedEndpointURL("https://push.example.com/v1/devices/sync"))
        XCTAssertNotNil(XFlowPushBackendClient.validatedEndpointURL("http://127.0.0.1:8787/v1/devices/sync"))
        XCTAssertNil(XFlowPushBackendClient.validatedEndpointURL("http://push.example.com/v1/devices/sync"))
        XCTAssertNil(XFlowPushBackendClient.validatedEndpointURL("https://user:pass@push.example.com/v1/devices/sync"))
    }

    func testPersistedAccountMetadataRejectsUntrustedValues() throws {
        let data = Data(
            #"{"id":"60A8069A-2AB2-4A67-95B0-C1240FD1223E","fallbackName":"Account","handle":"bad/name","profileImageURL":"https://example.com/tracker.png","requiresLogin":false}"#.utf8
        )

        let account = try JSONDecoder().decode(DeckAccount.self, from: data)

        XCTAssertNil(account.handle)
        XCTAssertNil(account.profileImageURL)
    }

    func testPersistedAccountMetadataRetainsTrustedValues() throws {
        let data = Data(
            #"{"id":"60A8069A-2AB2-4A67-95B0-C1240FD1223E","fallbackName":"Account","handle":"@Valid_User","profileImageURL":"https://pbs.twimg.com/profile_images/123/avatar_normal.jpg","requiresLogin":false}"#.utf8
        )

        let account = try JSONDecoder().decode(DeckAccount.self, from: data)

        XCTAssertEqual(account.handle, "valid_user")
        XCTAssertEqual(account.profileImageURL, "https://pbs.twimg.com/profile_images/123/avatar_normal.jpg")
    }

    func testAuthenticationCookieMustApplyToXHome() throws {
        let valid = try XCTUnwrap(cookie(domain: ".x.com", path: "/", secure: true))
        let subdomainOnly = try XCTUnwrap(cookie(domain: "api.x.com", path: "/", secure: true))
        let wrongPath = try XCTUnwrap(cookie(domain: ".x.com", path: "/settings", secure: true))
        let insecure = try XCTUnwrap(cookie(domain: ".x.com", path: "/", secure: false))

        XCTAssertTrue(WebSessionPool.isCookieApplicableToXHome(valid))
        XCTAssertFalse(WebSessionPool.isCookieApplicableToXHome(subdomainOnly))
        XCTAssertFalse(WebSessionPool.isCookieApplicableToXHome(wrongPath))
        XCTAssertFalse(WebSessionPool.isCookieApplicableToXHome(insecure))
    }

    func testJavaScriptStringEncodingCannotBreakOutOfLiteral() throws {
        let raw = "'); globalThis.compromised = true; //\n\r\u{2028}\u{2029}"
        let literal = JavaScriptEncoding.stringLiteral(raw)
        let context = try XCTUnwrap(JSContext())

        context.evaluateScript("globalThis.compromised = false; globalThis.value = \(literal);")

        XCTAssertEqual(context.objectForKeyedSubscript("value")?.toString(), raw)
        XCTAssertFalse(context.objectForKeyedSubscript("compromised")?.toBool() ?? true)
        XCTAssertNil(context.exception)
    }

    func testHTMLAttributeEncodingEscapesMarkupBoundaries() {
        let encoded = HTMLEncoding.attributeValue("' onerror='compromised' & <script>")

        XCTAssertEqual(
            encoded,
            "&#39; onerror=&#39;compromised&#39; &amp; &lt;script&gt;"
        )
        XCTAssertFalse(encoded.contains("<script>"))
    }

    private func url(_ value: String) -> URL {
        URL(string: value)!
    }

    private func cookie(domain: String, path: String, secure: Bool) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "auth_token",
            .value: "test-value",
            .domain: domain,
            .path: path
        ]
        if secure {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }
}
