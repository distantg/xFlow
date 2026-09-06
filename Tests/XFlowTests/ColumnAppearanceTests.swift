import JavaScriptCore
import XCTest
@testable import XFlow

final class ColumnAppearanceTests: XCTestCase {
    func testPreferenceDefaultsToOriginalX() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(ColumnAppearancePreference.load(from: defaults), .originalX)
    }

    func testPreferencePersistsIntegratedMode() throws {
        let defaults = try makeDefaults()
        ColumnAppearancePreference.save(.mosaicIntegrated, to: defaults)
        XCTAssertEqual(ColumnAppearancePreference.load(from: defaults), .mosaicIntegrated)
    }

    func testInvalidPreferenceFallsBackToOriginalX() throws {
        let defaults = try makeDefaults()
        defaults.set("future-mode", forKey: ColumnAppearancePreference.storageKey)
        XCTAssertEqual(ColumnAppearancePreference.load(from: defaults), .originalX)
    }

    func testAppearanceScriptsHaveValidJavaScriptSyntax() throws {
        for script in [
            WebColumnView.Coordinator.structuralColumnChromeScript,
            WebColumnView.Coordinator.integratedColumnThemeScript,
            WebColumnView.Coordinator.removeIntegratedColumnThemeScript
        ] {
            let context = try XCTUnwrap(JSContext())
            var exception: JSValue?
            context.exceptionHandler = { _, value in exception = value }

            let data = try JSONSerialization.data(withJSONObject: [script])
            let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
            context.evaluateScript("new Function(\(String(encoded.dropFirst().dropLast())))")

            XCTAssertNil(exception, exception?.toString() ?? "Unexpected JavaScript syntax error")
        }
    }

    func testIntegratedThemeIsIdempotentAndRemovable() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        const __nodes = {};
        const document = {
          documentElement: { dataset: {} },
          head: {
            appendChild(node) {
              __nodes[node.id] = node;
              node.remove = function() { delete __nodes[node.id]; };
            }
          },
          getElementById(id) { return __nodes[id] || null; },
          createElement() { return { id: '', textContent: '' }; }
        };
        """)

        context.evaluateScript(WebColumnView.Coordinator.integratedColumnThemeScript)
        context.evaluateScript(WebColumnView.Coordinator.integratedColumnThemeScript)
        XCTAssertEqual(context.evaluateScript("Object.keys(__nodes).length")?.toInt32(), 1)
        XCTAssertEqual(
            context.evaluateScript("document.documentElement.dataset.mosaicAppearance")?.toString(),
            "integrated"
        )

        context.evaluateScript(WebColumnView.Coordinator.removeIntegratedColumnThemeScript)
        XCTAssertEqual(context.evaluateScript("Object.keys(__nodes).length")?.toInt32(), 0)
        XCTAssertTrue(
            context.evaluateScript("document.documentElement.dataset.mosaicAppearance === undefined")?.toBool() == true
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "ColumnAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
