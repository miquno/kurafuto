import SwiftUI

/// The three looks of the "Instrument" design. Gray and dark both use the system's dark scheme.
enum ThemeMode: String, CaseIterable, Identifiable {
    case dark, gray, light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: String(localized: "Dark")
        case .gray: String(localized: "Gray")
        case .light: String(localized: "Light")
        }
    }

    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

/// Elements that carry their own accent color, chosen by the user in Settings.
enum AccentRole: String, CaseIterable, Identifiable {
    case accent, cpu, ram, players, storage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accent: String(localized: "Accent")
        case .cpu: String(localized: "CPU")
        case .ram: String(localized: "RAM")
        case .players: String(localized: "Players")
        case .storage: String(localized: "Storage")
        }
    }

    var symbol: String {
        switch self {
        case .accent: "paintbrush.pointed.fill"
        case .cpu: "cpu"
        case .ram: "memorychip"
        case .players: "person.2.fill"
        case .storage: "internaldrive"
        }
    }

    var defaultPreset: AccentPreset {
        switch self {
        case .accent, .cpu: .cyan
        case .ram: .violet
        case .players: .green
        case .storage: .amber
        }
    }
}

/// A fixed set of accent colors instead of a free color picker, so every choice keeps
/// readable contrast on all three backgrounds. Light mode uses a darker shade of each.
enum AccentPreset: String, CaseIterable, Identifiable {
    case cyan, green, violet, amber, pink, blue, orange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cyan: String(localized: "Cyan")
        case .green: String(localized: "Green")
        case .violet: String(localized: "Violet")
        case .amber: String(localized: "Amber")
        case .pink: String(localized: "Pink")
        case .blue: String(localized: "Blue")
        case .orange: String(localized: "Orange")
        }
    }

    func color(for mode: ThemeMode) -> Color {
        let hex: UInt32 = switch (self, mode == .light) {
        case (.cyan, false): 0x3DD9EB
        case (.cyan, true): 0x007C8F
        case (.green, false): 0x5BD27A
        case (.green, true): 0x1B7A3B
        case (.violet, false): 0x9B8CFF
        case (.violet, true): 0x5B47D6
        case (.amber, false): 0xFFB547
        case (.amber, true): 0x8F5500
        case (.pink, false): 0xFF7AB8
        case (.pink, true): 0xB0144F
        case (.blue, false): 0x6FA8FF
        case (.blue, true): 0x2350E6
        case (.orange, false): 0xFF8A4C
        case (.orange, true): 0xB04400
        }
        return Color(hex: hex)
    }
}

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

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
