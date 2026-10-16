import XCTest
@testable import Kurafuto

/// Checks the compiled String Catalogs in the app bundle. Completeness against the code is checked by
/// `scripts/check-localizations.sh` in CI, which can read the catalog itself.
final class LocalizationTests: XCTestCase {
    private static let translations = ["de", "ja", "zh-Hans"]

    private func bundle(_ language: String) throws -> Bundle {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"), "\(language).lproj missing")
        return try XCTUnwrap(Bundle(url: url))
    }

    private func keys(_ language: String, _ file: String) throws -> Set<String> {
        let url = try bundle(language).url(forResource: "Localizable", withExtension: file)
        return Set((url.flatMap { NSDictionary(contentsOf: $0) } as? [String: Any] ?? [:]).keys)
    }

    private func text(_ key: String, _ language: String, _ arguments: CVarArg...) throws -> String {
        let format = try bundle(language).localizedString(forKey: key, value: "⚠️ missing", table: nil)
        return String(format: format, locale: Locale(identifier: language), arguments: arguments)
    }

    func testEveryLanguageShipsTheSameStrings() throws {
        XCTAssertTrue(Set(Bundle.main.localizations).isSuperset(of: ["en"] + Self.translations), "\(Bundle.main.localizations)")
        let german = try keys("de", "strings").union(keys("de", "stringsdict"))
        XCTAssertGreaterThan(german.count, 300)
        for language in Self.translations.dropFirst() {
            let other = try keys(language, "strings").union(keys(language, "stringsdict"))
            XCTAssertEqual(other.subtracting(german), [], "only in \(language)")
            XCTAssertEqual(german.subtracting(other), [], "missing in \(language)")
        }
    }

    func testPermissionPromptsAreTranslated() throws {
        for language in Self.translations {
            let prompts = try bundle(language).url(forResource: "InfoPlist", withExtension: "strings").flatMap { NSDictionary(contentsOf: $0) }
            XCTAssertNotNil(prompts?["NSFaceIDUsageDescription"], language)
            XCTAssertNotNil(prompts?["NSLocalNetworkUsageDescription"], language)
        }
    }

    func testTranslationsResolve() throws {
        XCTAssertEqual(try text("Settings", "de"), "Einstellungen")
        XCTAssertEqual(try text("Settings", "ja"), "設定")
        XCTAssertEqual(try text("Settings", "zh-Hans"), "设置")
        XCTAssertEqual(try text("Stop %@?", "de", "Survival SMP"), "Survival SMP stoppen?")
    }

    func testPluralsFollowTheNumber() throws {
        XCTAssertEqual(try text("Every %lld days", "en", 1), "Every day")
        XCTAssertEqual(try text("Every %lld days", "en", 3), "Every 3 days")
        XCTAssertEqual(try text("Every %lld days", "de", 1), "Jeden Tag")
        XCTAssertEqual(try text("Every %lld days", "de", 3), "Alle 3 Tage")
        XCTAssertEqual(try text("Every %lld days", "ja", 1), "1 日ごと")
        XCTAssertEqual(try text("%lld players will be disconnected.", "en", 1), "1 player will be disconnected.")
        XCTAssertEqual(try text("%lld players will be disconnected.", "de", 4), "4 Spieler werden getrennt.")
        XCTAssertEqual(try text("Delete %lld schedules?", "de", 1), "Zeitplan löschen?")
    }

    func testTranslationsCanReorderArguments() throws {
        XCTAssertEqual(try text("Players: %lld of %lld", "ja", 3, 10), "プレイヤー: 10 人中 3 人")
        XCTAssertEqual(try text("%@ on %@", "zh-Hans", "Files", "Survival SMP"), "Survival SMP 的 Files")
    }

    /// The tests run in English; the summary goes through the same catalog the app uses.
    func testScheduleSummaryReadsNaturally() {
        var s = MockData.schedules[0]
        (s.intervalType, s.interval, s.startTime) = (.days, 1, "04:00")
        XCTAssertEqual(s.summary, "Every day at 04:00")
        s.interval = 2
        XCTAssertEqual(s.summary, "Every 2 days at 04:00")
        (s.intervalType, s.interval) = (.hours, 1)
        XCTAssertEqual(s.summary, "Every hour")
        (s.intervalType, s.interval) = (.minutes, 15)
        XCTAssertEqual(s.summary, "Every 15 minutes")
    }
}
