import XCTest
@testable import XFlow

final class UpdateEvaluatorTests: XCTestCase {
    private let releaseURL = URL(string: "https://github.com/distantg/xFlow/releases/tag/v1.1.0")!

    func testSameVersionIsUpToDate() {
        let manifest = makeManifest(version: "1.0.0", publishedAt: Date(timeIntervalSince1970: 0))

        let result = UpdateEvaluator.evaluate(
            manifest: manifest,
            installedVersion: "1.0.0",
            now: Date(timeIntervalSince1970: 10_000),
            mode: .manual,
            rolloutDelay: 7 * 24 * 60 * 60
        )

        XCTAssertEqual(result, .upToDate)
    }

    func testManualCheckShowsNewerVersionImmediately() {
        let now = Date()
        let manifest = makeManifest(version: "1.1.0", publishedAt: now)

        let result = UpdateEvaluator.evaluate(
            manifest: manifest,
            installedVersion: "1.0.0",
            now: now,
            mode: .manual,
            rolloutDelay: 7 * 24 * 60 * 60
        )

        guard case .available(let update) = result else {
            return XCTFail("Expected manual checks to surface the new version immediately.")
        }
        XCTAssertEqual(update.latestVersion, "1.1.0")
    }

    func testAutomaticCheckDefersBeforeSevenDayRolloutDelay() {
        let publishedAt = Date(timeIntervalSince1970: 1_000)
        let sixDaysLater = publishedAt.addingTimeInterval(6 * 24 * 60 * 60)
        let manifest = makeManifest(version: "1.1.0", publishedAt: publishedAt)

        let result = UpdateEvaluator.evaluate(
            manifest: manifest,
            installedVersion: "1.0.0",
            now: sixDaysLater,
            mode: .automatic,
            rolloutDelay: 7 * 24 * 60 * 60
        )

        guard case .deferred(let update) = result else {
            return XCTFail("Expected automatic checks to defer during rollout delay.")
        }
        XCTAssertEqual(update.latestVersion, "1.1.0")
    }

    func testAutomaticCheckShowsAfterSevenDayRolloutDelay() {
        let publishedAt = Date(timeIntervalSince1970: 1_000)
        let sevenDaysLater = publishedAt.addingTimeInterval(7 * 24 * 60 * 60)
        let manifest = makeManifest(version: "1.1.0", publishedAt: publishedAt)

        let result = UpdateEvaluator.evaluate(
            manifest: manifest,
            installedVersion: "1.0.0",
            now: sevenDaysLater,
            mode: .automatic,
            rolloutDelay: 7 * 24 * 60 * 60
        )

        guard case .available(let update) = result else {
            return XCTFail("Expected automatic checks to surface eligible updates.")
        }
        XCTAssertEqual(update.latestVersion, "1.1.0")
    }

    func testNewestManifestVersionSupersedesOlderVersion() {
        let publishedAt = Date(timeIntervalSince1970: 1_000)
        let eligibleDate = publishedAt.addingTimeInterval(8 * 24 * 60 * 60)
        let manifest = makeManifest(version: "1.1.1", publishedAt: publishedAt)

        let result = UpdateEvaluator.evaluate(
            manifest: manifest,
            installedVersion: "1.0.0",
            now: eligibleDate,
            mode: .automatic,
            rolloutDelay: 7 * 24 * 60 * 60
        )

        guard case .available(let update) = result else {
            return XCTFail("Expected latest manifest version to be surfaced.")
        }
        XCTAssertEqual(update.latestVersion, "1.1.1")
    }

    func testSemanticVersionComparisonHandlesDifferentDigitCounts() {
        XCTAssertGreaterThan(SemanticVersion("1.10.0"), SemanticVersion("1.2.9"))
        XCTAssertEqual(SemanticVersion("v1.1.0"), SemanticVersion("1.1"))
        XCTAssertLessThan(SemanticVersion("1.0.9"), SemanticVersion("1.0.10"))
    }

    @MainActor
    func testManualFetchFailureShowsErrorAlert() async {
        let manager = UpdateManager(fetcher: FailingManifestFetcher())

        await manager.checkManually()

        XCTAssertEqual(manager.alert?.kind, .error)
    }

    @MainActor
    func testManualNewerManifestProducesDownloadURL() async {
        let manifest = makeManifest(version: "999.0.0", publishedAt: Date())
        let manager = UpdateManager(fetcher: StaticManifestFetcher(manifest: manifest))

        await manager.checkManually()

        XCTAssertEqual(manager.alert?.kind, .available)
        XCTAssertEqual(manager.alert?.downloadURL, releaseURL)
    }

    private func makeManifest(version: String, publishedAt: Date) -> UpdateManifest {
        UpdateManifest(
            latestVersion: version,
            publishedAt: publishedAt,
            downloadURL: releaseURL,
            releaseNotes: "Test release notes.",
            minimumSupportedVersion: "1.0.0"
        )
    }
}

private struct StaticManifestFetcher: UpdateManifestFetching {
    let manifest: UpdateManifest

    func fetchManifest(from url: URL) async throws -> UpdateManifest {
        manifest
    }
}

private struct FailingManifestFetcher: UpdateManifestFetching {
    func fetchManifest(from url: URL) async throws -> UpdateManifest {
        throw URLError(.cannotFindHost)
    }
}
