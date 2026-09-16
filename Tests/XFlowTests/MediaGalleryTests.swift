import XCTest
@testable import XFlow

final class MediaGalleryTests: XCTestCase {
    func testGalleryPreservesOrderAndClickedItemForMixedMedia() throws {
        let image = "https://pbs.twimg.com/media/first?format=jpg&name=small"
        let video = "https://x.com/person/status/123/video/2"
        let request = try XCTUnwrap(MediaRequest.validatedBridgeRequest(
            kind: .video, url: URL(string: video)!, currentTime: 12, mediaURL: nil))
        let gallery = request.includingGallery([
            ["kind": "image", "url": image],
            ["kind": "video", "url": video, "currentTime": 12]
        ], selectedIndex: 1)
        XCTAssertEqual(gallery.selectedIndex, 1)
        XCTAssertEqual(gallery.items.map(\.kind), [.image, .video])
        XCTAssertEqual(gallery.items[1].currentTime, 12)
        XCTAssertTrue(gallery.items[0].mediaURL!.absoluteString.contains("name=orig"))
    }

    func testInvalidGalleryFallsBackToOriginalItem() throws {
        let url = URL(string: "https://pbs.twimg.com/media/first")!
        let request = MediaRequest(kind: .image, url: url, currentTime: nil, mediaURL: nil)
        let valid: [String: Any] = ["kind": "image", "url": url.absoluteString]
        let unsafe: [String: Any] = ["kind": "image", "url": "https://untrusted.example/image.jpg"]
        XCTAssertTrue(request.includingGallery([valid, unsafe], selectedIndex: 0).items.isEmpty)
        XCTAssertTrue(request.includingGallery([valid, valid], selectedIndex: 2).items.isEmpty)
        XCTAssertTrue(request.includingGallery([valid, valid], selectedIndex: -1).items.isEmpty)
        XCTAssertTrue(request.includingGallery(Array(repeating: valid, count: 17), selectedIndex: 0).items.isEmpty)
        XCTAssertTrue(request.includingGallery([valid], selectedIndex: 0).items.isEmpty)
    }
}
