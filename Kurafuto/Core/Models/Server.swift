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
