import XCTest
@testable import Tunerfenster

final class LocalizationTests: XCTestCase {
    func testCatalogsContainTheSameKeysAndMatchingFormatArguments() {
        let english = L10n.translations(for: .english)
        let german = L10n.translations(for: .german)
        XCTAssertGreaterThan(english.count, 100)
        XCTAssertEqual(Set(english.keys), Set(german.keys))
        for (key, value) in english {
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertFalse(german[key]!.isEmpty, key)
            XCTAssertEqual(value.components(separatedBy: "%@").count, german[key]!.components(separatedBy: "%@").count, key)
        }
    }

    func testBothLanguagesRenderDynamicInterfaceMessages() {
        XCTAssertEqual(L10n.text("columnCount", arguments: ["4"], language: .english), "4 columns")
        XCTAssertEqual(L10n.text("columnCount", arguments: ["4"], language: .german), "4 Spalten")
        XCTAssertEqual(L10n.text("tunerCountOne", arguments: ["1"], language: .english), "1 tuner")
        XCTAssertEqual(L10n.text("tunerCountMany", arguments: ["14"], language: .english), "14 tuners")
        XCTAssertEqual(L10n.text("httpError", arguments: ["403", "status/inputs"], language: .english), "TVHeadend returned HTTP 403 for status/inputs.")
        XCTAssertEqual(L10n.text("httpError", arguments: ["403", "status/inputs"], language: .german), "TVHeadend antwortet mit HTTP 403 auf status/inputs.")
    }

    func testExistingErrorsCanBeRenderedAgainInAnotherLanguage() {
        let error = AppError.context("catalogUnavailable", .message("missingPermissions"))
        XCTAssertTrue(error.description(language: .english).hasPrefix("Channel list unavailable: Authentication"))
        XCTAssertTrue(error.description(language: .german).hasPrefix("Senderliste nicht verfügbar: Anmeldung"))
        let network = AppError.wrapping(URLError(.notConnectedToInternet))
        XCTAssertTrue(network.description(language: .english).contains("retry automatically"))
        XCTAssertTrue(network.description(language: .german).contains("automatisch erneut"))
    }

    func testLanguageSelectionIsAppSpecificAndHasAStableFallback() throws {
        let suite = "TunerfensterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppLanguage.initial(defaults: defaults, preferredLanguages: ["de-DE"]), .german)
        XCTAssertEqual(AppLanguage.initial(defaults: defaults, preferredLanguages: ["fr-FR"]), .english)
        defaults.set("en", forKey: "interfaceLanguage")
        XCTAssertEqual(AppLanguage.initial(defaults: defaults, preferredLanguages: ["de-DE"]), .english)
        defaults.set("de", forKey: "interfaceLanguage")
        XCTAssertEqual(AppLanguage.initial(defaults: defaults, preferredLanguages: ["en-GB"]), .german)
    }
}
