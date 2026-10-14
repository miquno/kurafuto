import XCTest
import SwiftUI
@testable import Kurafuto

@MainActor
final class AppearanceTests: XCTestCase {
    private let suite = "AppearanceTests"

    /// An empty, test-only defaults domain, cleared again after the test.
    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { [suite] in UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testDefaultsToDarkWithRoleDefaults() {
        let a = Appearance(defaults: freshDefaults())
        XCTAssertEqual(a.mode, .dark)
        for role in AccentRole.allCases {
            XCTAssertEqual(a.preset(for: role), role.defaultPreset)
        }
    }

    func testChoicesPersistAcrossInstances() {
        let defaults = freshDefaults()
        let a = Appearance(defaults: defaults)
        a.mode = .gray
        a.setPreset(.pink, for: .cpu)

        let reloaded = Appearance(defaults: defaults)
        XCTAssertEqual(reloaded.mode, .gray)
        XCTAssertEqual(reloaded.preset(for: .cpu), .pink)
        XCTAssertEqual(reloaded.preset(for: .ram), AccentRole.ram.defaultPreset)
    }

    func testResetRestoresRoleDefaults() {
        let defaults = freshDefaults()
        let a = Appearance(defaults: defaults)
        a.setPreset(.orange, for: .players)
        a.resetAccents()

        XCTAssertEqual(a.preset(for: .players), AccentRole.players.defaultPreset)
        XCTAssertEqual(Appearance(defaults: defaults).preset(for: .players), AccentRole.players.defaultPreset)
    }

    func testUnknownStoredValuesFallBack() {
        let defaults = freshDefaults()
        defaults.set("neon", forKey: "appearance.mode")
        defaults.set("rainbow", forKey: "appearance.accent.cpu")

        let a = Appearance(defaults: defaults)
        XCTAssertEqual(a.mode, .dark)
        XCTAssertEqual(a.preset(for: .cpu), AccentRole.cpu.defaultPreset)
    }

    func testLightModeUsesDarkerShadesAndLightScheme() {
        for preset in AccentPreset.allCases {
            XCTAssertNotEqual(preset.color(for: .light), preset.color(for: .dark), preset.rawValue)
            XCTAssertEqual(preset.color(for: .gray), preset.color(for: .dark), preset.rawValue)
        }
        XCTAssertEqual(ThemeMode.light.colorScheme, .light)
        XCTAssertEqual(ThemeMode.gray.colorScheme, .dark)
    }

    func testStartTimeParsesCraftyFormatAsUTC() throws {
        let date = try XCTUnwrap(ServerStats.startTime("2026-10-14 08:12:03"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let parts = utc.dateComponents([.hour, .minute, .second], from: date)
        XCTAssertEqual(parts.hour, 8)
        XCTAssertEqual(parts.minute, 12)
        XCTAssertEqual(parts.second, 3)
        XCTAssertNil(ServerStats.startTime("not a date"))
    }
}
