import UniformTypeIdentifiers
import WebKit
import XCTest
@testable import XFlow

final class ComposerAttachmentPickerTests: XCTestCase {
    func testCoordinatorHandlesWebKitFileUploadRequests() {
        let selector = #selector(
            WKUIDelegate.webView(
                _:runOpenPanelWith:initiatedByFrame:completionHandler:
            )
        )

        XCTAssertTrue(WebColumnView.Coordinator.instancesRespond(to: selector))
    }

    func testAttachmentPickerOffersPhotosAndVideos() {
        XCTAssertEqual(
            WebColumnView.Coordinator.composerAttachmentContentTypes.map(\.identifier),
            [UTType.image.identifier, UTType.movie.identifier]
        )
    }
}
