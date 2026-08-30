import XCTest
@testable import XFlow

final class MediaURLResolverTests: XCTestCase {
    func testReplacesThumbnailSizeAndPreservesFormat() throws {
        let input = try XCTUnwrap(URL(string: "https://pbs.twimg.com/media/Example123?format=jpg&name=small"))

        let resolved = XMediaURLResolver.originalImageURL(from: input)

        XCTAssertEqual(resolved.host, "pbs.twimg.com")
        XCTAssertEqual(resolved.path, "/media/Example123")
        XCTAssertEqual(queryValue(named: "format", in: resolved), "jpg")
        XCTAssertEqual(queryValue(named: "name", in: resolved), "orig")
    }

    func testPreservesExistingQueryParameters() throws {
        let input = try XCTUnwrap(URL(string: "https://pbs.twimg.com/media/Example123?token=abc&name=360x360&format=webp"))

        let resolved = XMediaURLResolver.originalImageURL(from: input)

        XCTAssertEqual(queryValue(named: "token", in: resolved), "abc")
        XCTAssertEqual(queryValue(named: "format", in: resolved), "webp")
        XCTAssertEqual(queryValue(named: "name", in: resolved), "orig")
    }

    func testAddsOriginalSizeWhenNameIsMissing() throws {
        let input = try XCTUnwrap(URL(string: "https://pbs.twimg.com/media/Example123?format=png"))

        let resolved = XMediaURLResolver.originalImageURL(from: input)

        XCTAssertEqual(queryValue(named: "format", in: resolved), "png")
        XCTAssertEqual(queryValue(named: "name", in: resolved), "orig")
    }

    func testOriginalURLRemainsOriginalWithoutDuplicateName() throws {
        let input = try XCTUnwrap(URL(string: "https://pbs.twimg.com/media/Example123?format=jpg&name=orig&name=small"))

        let resolved = XMediaURLResolver.originalImageURL(from: input)
        let names = URLComponents(url: resolved, resolvingAgainstBaseURL: false)?.queryItems?
            .filter { $0.name == "name" }

        XCTAssertEqual(names?.count, 1)
        XCTAssertEqual(names?.first?.value, "orig")
    }

    func testUnrelatedHostIsUnchanged() throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/media/Example123?format=jpg&name=small"))

        XCTAssertEqual(XMediaURLResolver.originalImageURL(from: input), input)
    }

    func testNonMediaTwitterImageIsUnchanged() throws {
        let input = try XCTUnwrap(URL(string: "https://pbs.twimg.com/profile_images/123/avatar_normal.jpg"))

        XCTAssertEqual(XMediaURLResolver.originalImageURL(from: input), input)
    }

    func testMalformedRelativeURLIsUnchanged() throws {
        let input = try XCTUnwrap(URL(string: "not a valid absolute URL"))

        XCTAssertEqual(XMediaURLResolver.originalImageURL(from: input), input)
    }

    func testImageRequestKeepsThumbnailAsFallback() throws {
        let thumbnail = try XCTUnwrap(URL(string: "https://pbs.twimg.com/media/Example123?format=jpg&name=small"))

        let request = MediaRequest(kind: .image, url: thumbnail, currentTime: nil, mediaURL: thumbnail)

        XCTAssertEqual(request.url, thumbnail)
        XCTAssertEqual(queryValue(named: "name", in: try XCTUnwrap(request.mediaURL)), "orig")
    }

    private func queryValue(named name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == name }?
            .value
    }
}
