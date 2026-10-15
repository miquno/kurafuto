import Foundation

/// What the widgets show: the active panel's servers as the app last saw them, and the look to draw them in.
/// Only names, status and player counts – never the panel address, the username, a token or player names.
/// The app writes it (`WidgetSync`); the widget extension only reads it and never contacts the panel.
struct WidgetSnapshot: Codable, Equatable {
    struct Server: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var status: ServerStatus
        var online: Int
        var max: Int
    }

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

    /// For the widget gallery and placeholders before the app has written anything.
    static let sample = WidgetSnapshot(
        panelName: "Homelab",
        servers: [Server(id: "sample-crashed", name: "ATM10 Modpack", status: .crashed, online: 0, max: 8),
                  Server(id: "sample-survival", name: "Survival SMP", status: .online, online: 4, max: 20),
                  Server(id: "sample-creative", name: "Creative World", status: .online, online: 2, max: 10),
                  Server(id: "sample-bedrock", name: "Bedrock Friends", status: .offline, online: 0, max: 10)],
        updated: .now, isPrivate: false, mode: .dark, accent: AccentRole.accent.defaultPreset)
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

/// `kurafuto://server/<id>`: a widget opens the app on one server. Anyone can open such a link, so the app
/// only selects a server it already lists and never runs an action from it.
enum ServerLink {
    static let scheme = "kurafuto"

    static func url(serverID: String) -> URL? {
        guard isValidID(serverID) else { return nil }
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = "server"
        comps.path = "/" + serverID
        return comps.url
    }

    static func serverID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "server" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let id = parts.first, isValidID(id) else { return nil }
        return id
    }

    /// Crafty's server ids are UUIDs; letters, digits and `-` cover them without letting anything else through.
    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
