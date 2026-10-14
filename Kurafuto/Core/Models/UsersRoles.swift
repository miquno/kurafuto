import Foundation

/// `components.schemas.User`
struct CraftyUser: Identifiable, Codable, Hashable {
    var id: Int { userID }
    var userID: Int
    var username: String
    var enabled: Bool
    var superuser: Bool
    var lang: String
    var created: String?
    var lastLogin: String?
    var lastIP: String?
    var roleIDs: [Int]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username, enabled, superuser, lang, created
        case lastLogin = "last_login"
        case lastIP = "last_ip"
        case roleIDs = "roles"
    }
}

/// `components.schemas.Role`
struct Role: Identifiable, Codable, Hashable {
    var id: Int { roleID }
    var roleID: Int
    var roleName: String
    var manager: Int?
    var mfaRequired: Bool
    var servers: [RoleServerPermission]

    enum CodingKeys: String, CodingKey {
        case roleID = "role_id"
        case roleName = "role_name"
        case manager
        case mfaRequired = "mfa_required"
        case servers = "server"
    }
}

/// Crafty stores per-server permissions as a bitmask string, e.g. "10101101".
struct RoleServerPermission: Codable, Hashable {
    var serverID: String
    var permissions: String

    enum CodingKeys: String, CodingKey {
        case serverID = "server_id"
        case permissions
    }

    func has(_ p: ServerPermission) -> Bool {
        let chars = Array(permissions)
        return p.rawValue < chars.count && chars[p.rawValue] == "1"
    }

    mutating func set(_ p: ServerPermission, _ on: Bool) {
        var chars = Array(permissions.padding(toLength: ServerPermission.allCases.count, withPad: "0", startingAt: 0))
        chars[p.rawValue] = on ? "1" : "0"
        permissions = String(chars)
    }
}

/// Bit order according to Crafty's `EnumPermissionsServer` – verify against the source before release!
enum ServerPermission: Int, CaseIterable, Identifiable {
    case commands, terminal, logs, schedule, backup, files, config, players
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .commands: "Commands"
        case .terminal: "Terminal"
        case .logs: "Logs"
        case .schedule: "Schedules"
        case .backup: "Backups"
        case .files: "Files"
        case .config: "Config"
        case .players: "Players"
        }
    }
}

/// `GET /api/v2/users/{id}/permissions` – global Crafty permissions.
struct CraftyPermissions: Codable, Hashable {
    var serverCreation: Bool
    var userConfig: Bool
    var rolesConfig: Bool
    var serverCreationLimit: Int?
}
