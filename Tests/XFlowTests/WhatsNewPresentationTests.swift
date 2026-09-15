import XCTest
@testable import XFlow

final class WhatsNewPresentationTests: XCTestCase {
    func testExistingUsersSeeReleaseOnlyOnce() throws {
        let name = "WhatsNewTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(WhatsNewPresentation.shouldPresent(in: defaults))
        defaults.set(Data(), forKey: "xflow.accounts.v1")
        XCTAssertTrue(WhatsNewPresentation.shouldPresent(in: defaults))
        defaults.set("2.1", forKey: WhatsNewPresentation.storageKey)
        XCTAssertTrue(WhatsNewPresentation.shouldPresent(in: defaults))
        WhatsNewPresentation.markPresented(in: defaults)
        XCTAssertFalse(WhatsNewPresentation.shouldPresent(in: defaults))
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertFalse(WhatsNewPresentation.shouldPresent(in: reopened))
    }

    func testFreshInstallDoesNotBecomeAnUpdateOnSecondLaunch() throws {
        let name = "WhatsNewTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(WhatsNewPresentation.shouldPresent(in: defaults))
        WhatsNewPresentation.markPresented(in: defaults)
        defaults.set(Data(), forKey: "xflow.accounts.v1")
        XCTAssertFalse(WhatsNewPresentation.shouldPresent(in: defaults))
    }
}
