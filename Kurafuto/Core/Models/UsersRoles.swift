import Foundation

/// A panel user. `GET /users` lists only the public fields; roles, last login and manager come from
/// `GET /users/{id}`, which `LiveCraftyService.users()` loads for every listed user.
struct CraftyUser: Identifiable, Decodable, Hashable {
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
        case roles
    }

    /// `GET /users/{id}` sends full role rows; only their ids matter here.
    private struct RoleRef: Decodable { let roleID: Int; enum CodingKeys: String, CodingKey { case roleID = "role_id" } }

    init(userID: Int, username: String, enabled: Bool, superuser: Bool, lang: String, created: String? = nil,
         lastLogin: String? = nil, lastIP: String? = nil, roleIDs: [Int]) {
        self.userID = userID; self.username = username; self.enabled = enabled; self.superuser = superuser
        self.lang = lang; self.created = created; self.lastLogin = lastLogin; self.lastIP = lastIP; self.roleIDs = roleIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(Int.self, forKey: .userID)
        username = try c.decode(String.self, forKey: .username)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        superuser = (try? c.decode(Bool.self, forKey: .superuser)) ?? false
        lang = (try? c.decode(String.self, forKey: .lang)) ?? "en_EN"
        created = try? c.decode(String.self, forKey: .created)
        lastLogin = (try? c.decode(String.self, forKey: .lastLogin)).flatMap { $0.isEmpty ? nil : $0 }
        lastIP = (try? c.decode(String.self, forKey: .lastIP)).flatMap { $0.isEmpty ? nil : $0 }
        roleIDs = ((try? c.decode([RoleRef].self, forKey: .roles)) ?? []).map(\.roleID)
    }

    static func new() -> CraftyUser {
        CraftyUser(userID: 0, username: "", enabled: true, superuser: false, lang: "en_EN", roleIDs: [])
    }
}

/// Body for `POST /users` (with the password) and `PATCH /users/{id}` (only what changed). Both are
/// validated with `additionalProperties: false`; `superuser` is only sent when it changes, because the
/// panel refuses it from non-superusers.
struct UserChanges: Encodable, Equatable {
    var username: String?
    var password: String?
    var enabled: Bool?
    var superuser: Bool?
    var lang: String?
    var roles: [Int]?

    /// The panel's username rule (`user_jsonschema_props`): lowercase letters, digits and `_`, 3 to 20 characters.
    static func isValidUsername(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9_]{3,20}$"#, options: .regularExpression) != nil && !["system"].contains(name)
    }
    static let minimumPasswordLength = 8

    init() {}

    /// `old` nil means a new user: everything is sent, the password is required.
    init(from old: CraftyUser?, to new: CraftyUser, password: String) {
        let roles = new.superuser ? [] : new.roleIDs.sorted()
        if let old {
            if old.username != new.username { username = new.username }
            if old.enabled != new.enabled { enabled = new.enabled }
            if old.superuser != new.superuser { superuser = new.superuser }
            if old.lang != new.lang { lang = new.lang }
            if old.roleIDs.sorted() != roles { self.roles = roles }
        } else {
            username = new.username; enabled = new.enabled; lang = new.lang; self.roles = roles
            if new.superuser { superuser = true }
        }
        if !password.isEmpty { self.password = password }
    }

    var isEmpty: Bool { self == UserChanges() }

    /// Why the panel would refuse this user, or nil.
    static func problem(for user: CraftyUser, password: String, isNew: Bool) -> String? {
        if !isValidUsername(user.username) { return "Usernames use 3–20 lowercase letters, digits or _." }
        if isNew && password.isEmpty { return "Enter a password." }
        if !password.isEmpty && password.count < minimumPasswordLength { return "Passwords need at least 8 characters." }
        return nil
    }
}

/// A role. `GET /roles` has no servers; `GET /roles/{id}/servers` adds them, but only for superusers,
/// so `servers` is nil when they are unknown.
struct Role: Identifiable, Decodable, Hashable {
    var id: Int { roleID }
    var roleID: Int
    var roleName: String
    var manager: Int?
    var mfaRequired: Bool
    var servers: [RoleServerPermission]?

    enum CodingKeys: String, CodingKey {
        case roleID = "role_id"
        case roleName = "role_name"
        case manager
        case mfaRequired = "mfa_required"
    }

    init(roleID: Int, roleName: String, manager: Int?, mfaRequired: Bool, servers: [RoleServerPermission]?) {
        self.roleID = roleID; self.roleName = roleName; self.manager = manager; self.mfaRequired = mfaRequired; self.servers = servers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roleID = try c.decode(Int.self, forKey: .roleID)
        roleName = (try? c.decode(String.self, forKey: .roleName)) ?? ""
        manager = try? c.decode(Int.self, forKey: .manager)
        mfaRequired = (try? c.decode(Bool.self, forKey: .mfaRequired)) ?? false
        servers = nil
    }

    static func new() -> Role { Role(roleID: 0, roleName: "", manager: nil, mfaRequired: false, servers: []) }

    /// The panel's role name rule: not empty, no `,`, `[` or `]`.
    static func isValidName(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !name.contains(where: { ",[]".contains($0) })
    }
}

/// Body for `POST /roles` and `PATCH /roles/{id}` (`additionalProperties: false`). Creating needs both
/// `servers` and `mfa_required` (the panel reads them without a default); servers stay out of a patch
/// when they are unknown, so the panel keeps them. `manager` is never sent: only superusers may set it.
struct RoleBody: Encodable {
    let role: Role

    enum CodingKeys: String, CodingKey { case name, servers, mfaRequired = "mfa_required" }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role.roleName.trimmingCharacters(in: .whitespaces), forKey: .name)
        if let servers = role.servers ?? (role.roleID == 0 ? [] : nil) {
            try c.encode(servers.filter { RoleServerPermission.isValidMask($0.permissions) }, forKey: .servers)
        }
        try c.encode(role.mfaRequired, forKey: .mfaRequired)
    }
}

/// Crafty stores per-server permissions as a bit string in `EnumPermissionsServer` order, e.g. "10100110".
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

    /// The role schemas accept exactly eight `0`/`1` characters.
    static func isValidMask(_ mask: String) -> Bool {
        mask.count == ServerPermission.allCases.count && mask.allSatisfy { $0 == "0" || $0 == "1" }
    }

    mutating func set(_ p: ServerPermission, _ on: Bool) {
        var chars = Array(permissions.padding(toLength: ServerPermission.allCases.count, withPad: "0", startingAt: 0))
        chars[p.rawValue] = on ? "1" : "0"
        permissions = String(chars)
    }
}

/// Bit order of Crafty's `EnumPermissionsServer`, identical in 4.7.0 and 4.11.0 and checked on both panels
/// by granting one bit at a time. PLAYERS guards no API route; on 4.7.0 the console buffer needs LOGS, on
/// 4.11.0 TERMINAL.
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
    /// The signed-in user, so the app does not offer what the panel refuses for oneself
    /// (disabling or deleting one's own account, changing one's own roles).
    var userID: Int? = nil

    static let superuser = PanelAccess(isSuperuser: true, permissions: CraftyPermissions(mask: "000"))

    var canCreateServers: Bool { isSuperuser || permissions.canAdd(.serverCreation) }
    var canManageUsers: Bool { isSuperuser || permissions.has(.userConfig) }
    var canAddUsers: Bool { isSuperuser || permissions.canAdd(.userConfig) }
    var canManageRoles: Bool { isSuperuser || permissions.has(.rolesConfig) }
    var canAddRoles: Bool { isSuperuser || permissions.canAdd(.rolesConfig) }
    var showsAdmin: Bool { canManageUsers || canManageRoles }
}
