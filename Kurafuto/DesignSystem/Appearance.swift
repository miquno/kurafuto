import SwiftUI

/// User-chosen look, persisted in UserDefaults (app-only preferences, see PRIVACY.md).
/// A main-actor singleton so `Theme`'s static colors stay observable from any view body.
@MainActor @Observable
final class Appearance {
    static let shared = Appearance()

    var mode: ThemeMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    private(set) var accents: [AccentRole: AccentPreset]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Keys.mode).flatMap(ThemeMode.init) ?? .dark
        accents = Dictionary(uniqueKeysWithValues: AccentRole.allCases.map { role in
            (role, defaults.string(forKey: Keys.accent(role)).flatMap(AccentPreset.init) ?? role.defaultPreset)
        })
    }

    func preset(for role: AccentRole) -> AccentPreset { accents[role] ?? role.defaultPreset }

    func setPreset(_ preset: AccentPreset, for role: AccentRole) {
        accents[role] = preset
        defaults.set(preset.rawValue, forKey: Keys.accent(role))
    }

    func color(for role: AccentRole) -> Color { preset(for: role).color(for: mode) }

    func resetAccents() {
        for role in AccentRole.allCases {
            accents[role] = role.defaultPreset
            defaults.removeObject(forKey: Keys.accent(role))
        }
    }

    private enum Keys {
        static let mode = "appearance.mode"
        static func accent(_ role: AccentRole) -> String { "appearance.accent.\(role.rawValue)" }
    }
}
