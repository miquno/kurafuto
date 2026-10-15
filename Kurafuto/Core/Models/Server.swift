import Foundation

/// Mirrors `components.schemas.Server` from the Crafty API v2 (openapi-spec.yml).
struct Server: Identifiable, Codable, Hashable {
    var id: String { serverID }

    let serverID: String
    var serverName: String
    var created: String?
    var path: String?
    var backupPath: String?
    var executable: String?
    var logPath: String?
    var executionCommand: String?
    var autoStart: Bool
    var autoStartDelay: Int
    var crashDetection: Bool
    var stopCommand: String
    var executableUpdateURL: String?
    var serverIP: String
    var serverPort: Int
    var logsDeleteAfter: Int
    var type: ServerType
    var shutdownTimeout: Int?
    /// Comma-separated exit codes that crash detection treats as a normal stop.
    var ignoredExits: String?
    var countPlayers: Bool?
    var showStatus: Bool?

    enum CodingKeys: String, CodingKey {
        case serverID = "server_id"
        case serverName = "server_name"
        case created, path
        case backupPath = "backup_path"
        case executable
        case logPath = "log_path"
        case executionCommand = "execution_command"
        case autoStart = "auto_start"
        case autoStartDelay = "auto_start_delay"
        case crashDetection = "crash_detection"
        case stopCommand = "stop_command"
        case executableUpdateURL = "executable_update_url"
        case serverIP = "server_ip"
        case serverPort = "server_port"
        case logsDeleteAfter = "logs_delete_after"
        case type
        case shutdownTimeout = "shutdown_timeout"
        case ignoredExits = "ignored_exits"
        case countPlayers = "count_players"
        case showStatus = "show_status"
    }
}

/// Body for `PATCH /api/v2/servers/{id}`: only the fields that changed. The panel validates with
/// `additionalProperties: false`, and with a smaller schema for non-superusers, so the whole server never goes along.
struct ServerConfigPatch: Encodable, Equatable {
    var serverName: String?
    var executionCommand: String?
    var stopCommand: String?
    var autoStart: Bool?
    var autoStartDelay: Int?
    var crashDetection: Bool?
    var shutdownTimeout: Int?
    var ignoredExits: String?
    var serverIP: String?
    var serverPort: Int?
    var countPlayers: Bool?
    var showStatus: Bool?
    var logsDeleteAfter: Int?

    enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case executionCommand = "execution_command"
        case stopCommand = "stop_command"
        case autoStart = "auto_start"
        case autoStartDelay = "auto_start_delay"
        case crashDetection = "crash_detection"
        case shutdownTimeout = "shutdown_timeout"
        case ignoredExits = "ignored_exits"
        case serverIP = "server_ip"
        case serverPort = "server_port"
        case countPlayers = "count_players"
        case showStatus = "show_status"
        case logsDeleteAfter = "logs_delete_after"
    }

    init(from old: Server, to new: Server) {
        func changed<T: Equatable>(_ key: KeyPath<Server, T>) -> T? { old[keyPath: key] == new[keyPath: key] ? nil : new[keyPath: key] }
        serverName = changed(\.serverName).map { $0.trimmingCharacters(in: .whitespaces) }
        executionCommand = changed(\.executionCommand) ?? nil
        stopCommand = changed(\.stopCommand)
        autoStart = changed(\.autoStart)
        autoStartDelay = changed(\.autoStartDelay)
        crashDetection = changed(\.crashDetection)
        shutdownTimeout = changed(\.shutdownTimeout) ?? nil
        ignoredExits = (changed(\.ignoredExits) ?? nil).map(Self.normalizedExits)
        serverIP = changed(\.serverIP).map { $0.trimmingCharacters(in: .whitespaces) }
        serverPort = changed(\.serverPort)
        countPlayers = changed(\.countPlayers) ?? nil
        showStatus = changed(\.showStatus) ?? nil
        logsDeleteAfter = changed(\.logsDeleteAfter)
    }

    init() {}

    var isEmpty: Bool { self == ServerConfigPatch() }

    /// Fields only superusers may change (`server_patch_schema`); for everyone else the panel rejects the whole request.
    var touchesSuperuserFields: Bool { executionCommand != nil || serverIP != nil || serverPort != nil || showStatus != nil }

    func applied(to server: Server) -> Server {
        var s = server
        if let serverName { s.serverName = serverName }
        if let executionCommand { s.executionCommand = executionCommand }
        if let stopCommand { s.stopCommand = stopCommand }
        if let autoStart { s.autoStart = autoStart }
        if let autoStartDelay { s.autoStartDelay = autoStartDelay }
        if let crashDetection { s.crashDetection = crashDetection }
        if let shutdownTimeout { s.shutdownTimeout = shutdownTimeout }
        if let ignoredExits { s.ignoredExits = ignoredExits }
        if let serverIP { s.serverIP = serverIP }
        if let serverPort { s.serverPort = serverPort }
        if let countPlayers { s.countPlayers = countPlayers }
        if let showStatus { s.showStatus = showStatus }
        if let logsDeleteAfter { s.logsDeleteAfter = logsDeleteAfter }
        return s
    }

    /// The panel compares the exit code as text against each comma-separated entry, so spaces must go.
    static func normalizedExits(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    /// Why the panel (or the server afterwards) would not accept this configuration, or nil.
    static func problem(for server: Server) -> String? {
        let name = server.serverName.trimmingCharacters(in: .whitespaces)
        if name.count < 2 || name.contains(where: { "/\\#".contains($0) }) {
            return "The name needs at least 2 characters and must not contain / \\ or #."
        }
        if server.executionCommand?.trimmingCharacters(in: .whitespaces).isEmpty ?? false { return "Enter a start command." }
        if server.stopCommand.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a stop command." }
        if server.serverIP.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the server IP." }
        if !(1...65535).contains(server.serverPort) { return "The port must be between 1 and 65535." }
        if let exits = server.ignoredExits,
           normalizedExits(exits).range(of: #"^(-?\d+(,-?\d+)*)?$"#, options: .regularExpression) == nil {
            return "Ignored exit codes are whole numbers separated by commas."
        }
        return nil
    }
}

extension Server {
    /// The Java heap limit from `-Xmx` in the start command, the ceiling of the RAM chart.
    var maxMemoryBytes: Double? {
        guard let command = executionCommand,
              let match = command.firstMatch(of: /-Xmx(\d+)([kKmMgG]?)/), let value = Double(match.1) else { return nil }
        switch match.2.lowercased() {
        case "k": return value * 1024
        case "m": return value * 1024 * 1024
        case "g": return value * 1024 * 1024 * 1024
        default: return value
        }
    }
}

enum ServerType: String, Codable, CaseIterable {
    case minecraftJava = "minecraft-java"
    case minecraftBedrock = "minecraft-bedrock"
    case steamCMD = "steam_cmd"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServerType(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .minecraftJava: "Java"
        case .minecraftBedrock: "Bedrock"
        case .steamCMD: "SteamCMD"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .minecraftJava: "cup.and.saucer.fill"
        case .minecraftBedrock: "square.stack.3d.up.fill"
        case .steamCMD: "gamecontroller.fill"
        case .unknown: "questionmark.square"
        }
    }
}

/// Actions for `POST /api/v2/servers/{id}/action/{action}`.
enum ServerAction: String, CaseIterable {
    case start = "start_server"
    case stop = "stop_server"
    case restart = "restart_server"
    case kill = "kill_server"
    case backup = "backup_server"
    case updateExecutable = "update_executable"
    case clone = "clone_server"

    var label: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        case .restart: "Restart"
        case .kill: "Force Kill"
        case .backup: "Create Backup"
        case .updateExecutable: "Update Server JAR"
        case .clone: "Clone Server"
        }
    }

    var symbol: String {
        switch self {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        case .kill: "xmark.octagon.fill"
        case .backup: "externaldrive.badge.plus"
        case .updateExecutable: "arrow.down.circle"
        case .clone: "plus.square.on.square"
        }
    }

    /// Actions that require confirmation before running.
    var isDestructive: Bool { self == .kill || self == .stop }
}
