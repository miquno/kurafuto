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

/// `GET /api/v2/users/@me/permissions` – panel-wide permissions (same shape on Crafty 4.7.0 and 4.11.0).
/// `permissions` is a bit string in `EnumPermissionsCrafty` order (see `Kind`). Superusers get "000"
/// here, so the superuser flag from `/users/@me` must be checked first (`PanelAccess`).
struct CraftyPermissions: Decodable, Hashable {
    /// Declaration order is the bit order.
    enum Kind: String, CaseIterable {
        case serverCreation = "SERVER_CREATION"
        case userConfig = "USER_CONFIG"
        case rolesConfig = "ROLES_CONFIG"
    }

    var mask: String
    var counters: [String: Int]
    var limits: [String: Int]

    enum CodingKeys: String, CodingKey { case mask = "permissions", counters, limits }

    init(mask: String, counters: [String: Int] = [:], limits: [String: Int] = [:]) {
        self.mask = mask; self.counters = counters; self.limits = limits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mask = (try? c.decode(String.self, forKey: .mask)) ?? ""
        counters = (try? c.decode([String: Int].self, forKey: .counters)) ?? [:]
        limits = (try? c.decode([String: Int].self, forKey: .limits)) ?? [:]
    }

    func has(_ kind: Kind) -> Bool {
        guard let index = Kind.allCases.firstIndex(of: kind), index < mask.count else { return false }
        return mask[mask.index(mask.startIndex, offsetBy: index)] == "1"
    }

    /// Mirrors Crafty's `can_add_in_crafty`: the bit is set and the user is below the limit, or the limit is -1.
    func canAdd(_ kind: Kind) -> Bool {
        guard has(kind) else { return false }
        let limit = limits[kind.rawValue] ?? 0
        return limit == -1 || (counters[kind.rawValue] ?? 0) < limit
    }
}

/// What the signed-in user may do on the panel as a whole. Per-server rights are not exposed by the
/// API for the signed-in user; the panel enforces them per request.
struct PanelAccess: Hashable {
    var isSuperuser: Bool
    var permissions: CraftyPermissions

    static let superuser = PanelAccess(isSuperuser: true, permissions: CraftyPermissions(mask: "000"))

    var canCreateServers: Bool { isSuperuser || permissions.canAdd(.serverCreation) }
    var canManageUsers: Bool { isSuperuser || permissions.has(.userConfig) }
    var canAddUsers: Bool { isSuperuser || permissions.canAdd(.userConfig) }
    var canManageRoles: Bool { isSuperuser || permissions.has(.rolesConfig) }
    var canAddRoles: Bool { isSuperuser || permissions.canAdd(.rolesConfig) }
    var showsAdmin: Bool { canManageUsers || canManageRoles }
}
