import AppKit
import XCTest
@testable import XFlow

final class AccountAvatarPersistenceTests: XCTestCase {
    @MainActor
    func testAvatarSurvivesReloadAndLogoutPurgesOnlyItsAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "AvatarTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let first = UUID(), second = UUID()
        let storage = AccountAvatarStorage(directory: directory)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try storage.save(png, for: first)
        try storage.save(png, for: second)
        let reloadedStorage = AccountAvatarStorage(directory: directory)
        XCTAssertNotNil(reloadedStorage.image(for: first))
        let session = AccountAvatarSession(storage: reloadedStorage, defaults: defaults)
        session.setAuthenticated(false, accountID: first)
        XCTAssertNil(reloadedStorage.image(for: first))
        XCTAssertNotNil(reloadedStorage.image(for: second))
        let reloadedSession = AccountAvatarSession(storage: reloadedStorage, defaults: defaults)
        XCTAssertTrue(reloadedSession.signedOut.contains(first.uuidString))
        reloadedSession.setAuthenticated(true, accountID: first)
        XCTAssertFalse(reloadedSession.signedOut.contains(first.uuidString))
    }
}
