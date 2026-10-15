import Foundation

// MARK: - Schedules  (POST /api/v2/servers/{id}/tasks, PATCH/DELETE …/tasks/{taskID})

/// A panel schedule. Encodes to the body Crafty validates with `additionalProperties: false`
/// (`tasks/index.py`), so only the keys below may be sent.
struct Schedule: Identifiable, Encodable, Hashable {
    var id: Int
    var name: String
    var enabled: Bool
    var action: ScheduleAction
    var interval: Int
    var intervalType: IntervalType
    /// "HH:mm" in the panel's time zone; Crafty uses it only for `days`.
    var startTime: String = "00:00"
    var command: String?
    var parent: Int?           // Chained tasks: runs after "parent" + delay
    var oneTime: Bool
    var cronString: String?
    var delay: Int
    var nextRun: Date?

    enum CodingKeys: String, CodingKey {
        case name, enabled, action, interval
        case intervalType = "interval_type"
        case startTime = "start_time"
        case command, parent
        case oneTime = "one_time"
        case cronString = "cron_string"
        case delay
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(action, forKey: .action)
        try c.encode(interval, forKey: .interval)
        try c.encode(intervalType, forKey: .intervalType)
        try c.encode(startTime, forKey: .startTime)
        // The panel's task runner executes `command`: actions are queued as "<action>_server".
        try c.encode(action == .command ? command : "\(action.rawValue)_server", forKey: .command)
        try c.encode(intervalType == .reaction ? parent : nil, forKey: .parent)
        try c.encode(oneTime, forKey: .oneTime)
        try c.encode(intervalType == .cron ? cronString ?? "" : "", forKey: .cronString)
        try c.encode(intervalType == .reaction ? delay : 0, forKey: .delay)
    }

    var summary: String {
        switch intervalType {
        case .cron: "Cron: \(cronString ?? "")"
        case .reaction: "After parent task (+\(delay)s)"
        case .days: "Every \(interval) \(intervalType.label) at \(startTime)"
        case .minutes, .hours: "Every \(interval) \(intervalType.label)"
        }
    }
}

/// Values the panel's schedule form sends. Backups need a backup config (`action_id`) and arrive with the backups item.
enum ScheduleAction: String, Encodable, CaseIterable, Identifiable {
    case start, stop, restart, backup, command
    var id: String { rawValue }
    var label: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        case .restart: "Restart"
        case .backup: "Backup"
        case .command: "Command"
        }
    }
}

/// `interval_type` as validated by the panel; cron schedules send an empty string.
enum IntervalType: String, Encodable, CaseIterable, Identifiable {
    case minutes, hours, days, reaction
    case cron = ""
    var id: String { rawValue }
    var label: String {
        switch self {
        case .minutes: "minutes"
        case .hours: "hours"
        case .days: "days"
        case .reaction: "reaction"
        case .cron: "cron"
        }
    }
}

// MARK: - Backups

struct BackupConfig: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var maxBackups: Int
    var compress: Bool
    var shutdown: Bool          // stop server before backup
    var beforeCommand: String?
    var afterCommand: String?
    var excludedPaths: [String]
    var backupLocation: String
}

struct BackupFile: Identifiable, Codable, Hashable {
    var id: String { path }
    var path: String
    var size: Int64
    var created: Date
    var fileName: String { (path as NSString).lastPathComponent }
}

// MARK: - Webhooks (/api/v2/servers/{id}/webhook)

struct Webhook: Identifiable, Codable, Hashable {
    var id: Int
    var webhookType: WebhookType
    var name: String
    var url: String
    var botName: String
    var triggers: [WebhookTrigger]
    var body: String
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id = "webhook_id"
        case webhookType = "webhook_type"
        case name, url
        case botName = "bot_name"
        case triggers = "trigger"
        case body, enabled
    }
}

enum WebhookType: String, Codable, CaseIterable, Identifiable {
    case discord = "Discord"
    case slack = "Slack"
    case teams = "Teams"
    case mattermost = "Mattermost"
    case custom = "Custom"
    var id: String { rawValue }
}

enum WebhookTrigger: String, Codable, CaseIterable, Identifiable {
    case serverStart = "start_server"
    case serverStop = "stop_server"
    case serverRestart = "restart_server"
    case serverCrash = "server_crash"
    case backupServer = "backup_server"
    case jarUpdate = "jar_update"
    case sendCommand = "send_command"
    case kill = "kill"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .serverStart: "Server started"
        case .serverStop: "Server stopped"
        case .serverRestart: "Restart"
        case .serverCrash: "Crash"
        case .backupServer: "Backup"
        case .jarUpdate: "JAR update"
        case .sendCommand: "Command sent"
        case .kill: "Kill"
        }
    }
}

// MARK: - Files

struct FileEntry: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64?
    var modified: Date?

    var isEditableText: Bool {
        guard !isDirectory else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["properties", "txt", "json", "yml", "yaml", "toml", "cfg", "conf", "log", "ini", "sh", "bat", "mcmeta", ""].contains(ext)
    }
}

// MARK: - Logs / Console

struct LogLine: Identifiable, Hashable {
    let id = UUID()
    var text: String
    var level: Level

    enum Level { case info, warn, error, command, chat }

    init(_ text: String) {
        self.text = text
        if text.contains("ERROR") || text.contains("SEVERE") { level = .error }
        else if text.contains("WARN") { level = .warn }
        else if text.hasPrefix(">") { level = .command }
        else if text.contains("<") && text.contains(">") { level = .chat }
        else { level = .info }
    }
}

// MARK: - Players (derived from stats + console commands)

struct Player: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var isOnline: Bool
    var isOp: Bool = false
    var isBanned: Bool = false
    var isWhitelisted: Bool = false
}

// MARK: - Announcements (/api/v2/crafty/announcements)

struct Announcement: Identifiable, Codable, Hashable {
    var id: String
    var date: String
    var title: String
    var desc: String
    var link: String?
}

// MARK: - Create server (POST /api/v2/servers)

struct CreateServerRequest: Encodable {
    var name: String
    var kind: Kind
    var jarCategory: String = "mc_java_servers"
    var jarType: String = "paper"       // paper, purpur, fabric, forge, vanilla, ...
    var version: String = "1.21.4"
    var memMinGB: Int = 1
    var memMaxGB: Int = 2
    var port: Int = 25565
    var agreeToEULA: Bool = false

    enum Kind: String, CaseIterable { case java, bedrock }

    /// Builds the nested body exactly as described in the OpenAPI spec.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        try c.encode(name, forKey: "name")
        switch kind {
        case .java:
            try c.encode("minecraft_java", forKey: "monitoring_type")
            try c.encode(["host": AnyEncodable("127.0.0.1"), "port": AnyEncodable(port)], forKey: "minecraft_java_monitoring_data")
            try c.encode("minecraft_java", forKey: "create_type")
            try c.encode([
                "create_type": AnyEncodable("download_jar"),
                "download_jar_create_data": AnyEncodable([
                    "category": AnyEncodable(jarCategory),
                    "type": AnyEncodable(jarType),
                    "version": AnyEncodable(version),
                    "mem_min": AnyEncodable(memMinGB),
                    "mem_max": AnyEncodable(memMaxGB),
                    "server_properties_port": AnyEncodable(port),
                    "agree_to_eula": AnyEncodable(agreeToEULA),
                ]),
            ], forKey: "minecraft_java_create_data")
        case .bedrock:
            try c.encode("minecraft_bedrock", forKey: "monitoring_type")
            try c.encode(["host": AnyEncodable("127.0.0.1"), "port": AnyEncodable(19132)], forKey: "minecraft_bedrock_monitoring_data")
            try c.encode("minecraft_bedrock", forKey: "create_type")
            try c.encode([
                "create_type": AnyEncodable("download_exe"),
                "download_exe_create_data": AnyEncodable(["agree_to_eula": AnyEncodable(agreeToEULA)]),
            ], forKey: "minecraft_bedrock_create_data")
        }
    }
}

struct DynamicKey: CodingKey, ExpressibleByStringLiteral {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    init(stringLiteral value: String) { stringValue = value }
}

struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeFn = value.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
