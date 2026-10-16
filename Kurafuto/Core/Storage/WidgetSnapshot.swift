import Foundation

/// What the widgets show: the active panel's servers as the app last saw them, and the look to draw them in.
/// Never the panel address, the username, a token, console output or files (ADR 0009).
/// The app writes it (`WidgetSync`); the widget extension only reads it and never contacts the panel.
struct WidgetSnapshot: Codable, Equatable {
    struct Server: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var status: ServerStatus
        var online: Int
        var max: Int
        var version: String? = nil
        /// Percent; nil while the server is stopped.
        var cpu: Double? = nil
        var memBytes: Double? = nil
        /// The `-Xmx` limit from the start command.
        var memLimitBytes: Double? = nil
        /// The last hour, oldest first, at most `trendPoints` values.
        var cpuTrend: [Double] = []
        var memTrend: [Double] = []
        /// Names of the players online, shown only on Home Screen widgets and always privacy-sensitive.
        var players: [String] = []
        var lastBackup: Backup? = nil
    }

    struct Backup: Codable, Equatable {
        /// Wall-clock time of the panel's host, kept in UTC like `BackupFile.created`; show it in UTC.
        var date: Date
        var configName: String
    }

    static let trendPoints = 24
    static let maxPlayers = 8

    var panelName: String
    /// Crashed servers first, then the panel's order.
    var servers: [Server]
    var updated: Date
    /// The app lock is on, so the widgets hide their values while the device is locked.
    var isPrivate: Bool
    var mode: ThemeMode
    var accent: AccentPreset

    /// The server a widget shows: the configured one while it exists, else the running one with the most players.
    func server(id: String?) -> Server? {
        servers.first { $0.id == id }
            ?? servers.filter { $0.status == .online }.max { $0.online < $1.online }
            ?? servers.first
    }

    static func ordered(_ servers: [Server]) -> [Server] {
        servers.filter { $0.status == .crashed } + servers.filter { $0.status != .crashed }
    }

    /// Averages `values` into at most `trendPoints` buckets, enough for a sparkline.
    static func trend(_ values: [Double]) -> [Double] {
        guard values.count > trendPoints else { return values }
        let size = Double(values.count) / Double(trendPoints)
        return (0..<trendPoints).map { i in
            let bucket = values[Int(Double(i) * size)..<min(values.count, Int(Double(i + 1) * size))]
            return bucket.reduce(0, +) / Double(Swift.max(bucket.count, 1))
        }
    }

    /// What makes the widgets wrong when it changes. Live load values only count after `WidgetSync.refreshInterval`.
    var essentials: some Equatable {
        Essentials(panelName: panelName, isPrivate: isPrivate, mode: mode, accent: accent,
                   servers: servers.map { [$0.id, $0.name, $0.status.rawValue, "\($0.online)", "\($0.max)", $0.version ?? ""] + $0.players },
                   backups: servers.map(\.lastBackup))
    }

    private struct Essentials: Equatable {
        let panelName: String
        let isPrivate: Bool
        let mode: ThemeMode
        let accent: AccentPreset
        let servers: [[String]]
        let backups: [Backup?]
    }

    /// For the widget gallery and placeholders before the app has written anything.
    static let sample = WidgetSnapshot(
        panelName: "Homelab",
        servers: [Server(id: "sample-crashed", name: "ATM10 Modpack", status: .crashed, online: 0, max: 8, version: "NeoForge 1.21.1"),
                  Server(id: "sample-survival", name: "Survival SMP", status: .online, online: 4, max: 20, version: "Paper 1.21.4",
                         cpu: 23, memBytes: 3.1 * 1_073_741_824, memLimitBytes: 8 * 1_073_741_824,
                         cpuTrend: [18, 21, 19, 30, 22, 20, 24, 19, 27, 21, 22, 20, 26, 23, 25, 21, 24, 22, 23],
                         memTrend: [2.9, 3.0, 3.0, 3.1, 3.0, 3.1, 3.2, 3.1, 3.0, 3.1, 3.1, 3.2, 3.1].map { $0 * 1_073_741_824 },
                         players: ["Steve_DE", "Lena", "PixelMax", "Nico"],
                         lastBackup: Backup(date: .now.addingTimeInterval(-1_800), configName: "Default Backup")),
                  Server(id: "sample-bedrock", name: "Bedrock Friends", status: .online, online: 1, max: 10, version: "Bedrock 1.21",
                         cpu: 6, memBytes: 0.4 * 1_073_741_824, players: ["Alex2010"]),
                  Server(id: "sample-creative", name: "Creative World", status: .offline, online: 0, max: 10, version: "Purpur 1.21.4")],
        updated: .now, isPrivate: false, mode: .light, accent: .blue)
}

/// Widget kinds, shared so the app can ask which ones are installed.
enum WidgetKind {
    static let server = "dev.miquno.kurafuto.server"
    static let load = "dev.miquno.kurafuto.load"
    static let players = "dev.miquno.kurafuto.players"
    static let backup = "dev.miquno.kurafuto.backup"
    static let panel = "dev.miquno.kurafuto.panel"
}

extension ServerStatus: Codable {}
extension ThemeMode: Codable {}
extension AccentPreset: Codable {}

/// The snapshot file in the App Group container that the app and the widget extension share.
struct WidgetSnapshotStore {
    static let appGroup = "group.dev.miquno.kurafuto"
    static let shared = WidgetSnapshotStore(
        directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup))

    /// Nil when the App Group is unavailable (unsigned builds); the widgets then show their empty state.
    let fileURL: URL?

    init(directory: URL?) {
        fileURL = directory?.appending(path: "widget-snapshot.json")
    }

    func load() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Lock Screen widgets render while the device is locked, so the file stays readable after the first unlock.
    func save(_ snapshot: WidgetSnapshot) throws {
        guard let fileURL else { return }
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// `kurafuto://server/<id>[/console|/details]`: a widget opens the app on one server. Anyone can open such a
/// link, so the app only shows a server it already lists and never runs an action from it.
enum ServerLink {
    static let scheme = "kurafuto"

    enum Screen: String { case console, details }

    struct Target: Equatable {
        var serverID: String
        var screen: Screen?
    }

    static func url(serverID: String, screen: Screen? = nil) -> URL? {
        guard isValidID(serverID) else { return nil }
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = "server"
        comps.path = "/" + serverID + (screen.map { "/" + $0.rawValue } ?? "")
        return comps.url
    }

    static func target(from url: URL) -> Target? {
        guard url.scheme == scheme, url.host() == "server" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard (1...2).contains(parts.count), isValidID(parts[0]) else { return nil }
        guard parts.count == 2 else { return Target(serverID: parts[0]) }
        guard let screen = Screen(rawValue: parts[1]) else { return nil }
        return Target(serverID: parts[0], screen: screen)
    }

    /// Crafty's server ids are UUIDs; letters, digits and `-` cover them without letting anything else through.
    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
