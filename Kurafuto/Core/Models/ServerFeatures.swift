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
    /// Backup config for backup schedules.
    var backupID: String? = nil
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
        case backupID = "action_id"
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
        // The schema only accepts a string here, so the key is left out otherwise.
        if action == .backup, let backupID { try c.encode(backupID, forKey: .backupID) }
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

/// Values the panel's schedule form sends. Backups also need a backup config (`action_id`).
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

// MARK: - Backups  (/api/v2/servers/{id}/backups, …/backups/backup/{backupID}[/files])

/// A backup configuration ("backup policy" in the web panel). `GET …/backups` returns them as an object
/// keyed by id, without the `{status,data}` envelope.
struct BackupConfig: Identifiable, Decodable, Hashable {
    var id: String
    var name: String
    var location: String
    /// 0 keeps every archive.
    var maxBackups: Int
    var compress: Bool
    var shutdown: Bool          // stop server before backup
    var beforeCommand: String
    var afterCommand: String
    var excludedPaths: [String]
    var isDefault: Bool
    var kind: Kind

    enum Kind: String, Decodable {
        case zip = "zip_vault"
        case snapshot
    }

    init(id: String, name: String, location: String, maxBackups: Int = 0, compress: Bool = false, shutdown: Bool = false,
         beforeCommand: String = "", afterCommand: String = "", excludedPaths: [String] = [], isDefault: Bool = false,
         kind: Kind = .zip) {
        self.id = id; self.name = name; self.location = location; self.maxBackups = maxBackups
        self.compress = compress; self.shutdown = shutdown; self.beforeCommand = beforeCommand
        self.afterCommand = afterCommand; self.excludedPaths = excludedPaths; self.isDefault = isDefault; self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case id = "backup_id", name = "backup_name", location = "backup_location", maxBackups = "max_backups"
        case compress, shutdown, before, after, excluded = "excluded_dirs", isDefault = "default", kind = "backup_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        location = (try? c.decode(String.self, forKey: .location)) ?? ""
        maxBackups = (try? c.decode(Int.self, forKey: .maxBackups)) ?? 0
        compress = (try? c.decode(Bool.self, forKey: .compress)) ?? false
        shutdown = (try? c.decode(Bool.self, forKey: .shutdown)) ?? false
        beforeCommand = (try? c.decode(String.self, forKey: .before)) ?? ""
        afterCommand = (try? c.decode(String.self, forKey: .after)) ?? ""
        // Stored as one comma-separated string.
        excludedPaths = ((try? c.decode(String.self, forKey: .excluded)) ?? "")
            .split(separator: ",").map(String.init).filter { !$0.isEmpty }
        isDefault = (try? c.decode(Bool.self, forKey: .isDefault)) ?? false
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .zip
    }

    /// The panel's routes only match ids of this shape; anything else must not end up in a URL.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// Default config first, then by name.
    static func sorted(_ configs: some Sequence<BackupConfig>) -> [BackupConfig] {
        configs.filter { isValidID($0.id) }.sorted {
            $0.isDefault != $1.isDefault ? $0.isDefault : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

/// Body for `POST …/backups` and `PATCH …/backups/backup/{id}`, validated with `additionalProperties: false`.
/// Only superusers may send `backup_location`; the panel picks it for everyone else.
struct BackupConfigBody: Encodable {
    let config: BackupConfig
    let includeLocation: Bool

    enum CodingKeys: String, CodingKey {
        case name = "backup_name", location = "backup_location", maxBackups = "max_backups"
        case compress, shutdown, before, after
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(config.name, forKey: .name)
        if includeLocation { try c.encode(config.location, forKey: .location) }
        try c.encode(config.maxBackups, forKey: .maxBackups)
        try c.encode(config.compress, forKey: .compress)
        try c.encode(config.shutdown, forKey: .shutdown)
        try c.encode(config.beforeCommand, forKey: .before)
        try c.encode(config.afterCommand, forKey: .after)
    }
}

/// A zip archive of a backup config. The panel lists only full paths; the name is the only part sent back.
struct BackupFile: Identifiable, Hashable {
    var id: String { name }
    /// `yyyy-MM-dd_HH-mm-ss.zip`, the only shape the panel restores.
    let name: String
    /// Wall-clock time of the panel's host, read from the name; kept in UTC so it shows unchanged.
    let created: Date

    init?(path: String, format: DateFormatter = BackupFile.nameFormat()) {
        let name = (path as NSString).lastPathComponent
        guard name.hasSuffix(".zip"), let date = format.date(from: String(name.dropLast(4))),
              format.string(from: date) + ".zip" == name else { return nil }
        self.name = name
        created = date
    }

    static func nameFormat() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }

    /// Newest first; drops anything that is not a panel-made archive name.
    static func list(fromPaths paths: [String]) -> [BackupFile] {
        let format = nameFormat()
        return paths.compactMap { BackupFile(path: $0, format: format) }.sorted { $0.created > $1.created }
    }
}

// MARK: - Webhooks (/api/v2/servers/{id}/webhook)

/// A webhook as the panel stores it. The panel sends it, not the app: Kurafuto only edits the entry.
struct Webhook: Identifiable, Hashable {
    /// 0 for a webhook that is not saved yet.
    var id: Int
    /// One of `providers` on a valid webhook; older rows may carry other names.
    var type: String
    var name: String
    var url: String
    var botName: String
    /// Trigger names in panel order; unknown ones are kept so a save does not drop them.
    var triggers: [String]
    /// Jinja2 template, e.g. `{{ server_name }}`.
    var body: String
    /// `#rrggbb`; Discord shows it as the embed color.
    var color: String
    var enabled: Bool

    /// `WebhookFactory._registry` in 4.7.0 and 4.11.0.
    static let providers = ["Discord", "Mattermost", "Slack", "Teams"]
    static let defaultColor = "#005cd1"
    /// The web panel limits both names to 30 characters.
    static let maxNameLength = 30

    static func new() -> Webhook {
        Webhook(id: 0, type: "Discord", name: "", url: "", botName: "Crafty Controller",
                triggers: [WebhookTrigger.serverStart.rawValue, WebhookTrigger.serverStop.rawValue],
                body: "{{ server_name }}: {{ event_type }}", color: defaultColor, enabled: true)
    }

    /// The panel stores `trigger` as one string with a trailing comma (`"start_server,stop_server,"`).
    static func triggers(fromPanel text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Why the panel would refuse this webhook, or nil when it can be saved.
    var problem: String? {
        let name = name.trimmingCharacters(in: .whitespaces), bot = botName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.count > Self.maxNameLength { return "Enter a name of up to 30 characters." }
        if !Self.providers.contains(type) { return "Choose a service." }
        if !WebhookURL.isValid(url) { return "Enter an http:// or https:// address with a host name or IP address." }
        if bot.isEmpty || bot.count > Self.maxNameLength { return "Enter a bot name of up to 30 characters." }
        if !Self.isValidColor(color) { return "Choose a color." }
        return nil
    }

    static func isValidColor(_ text: String) -> Bool {
        text.count == 7 && text.first == "#" && text.dropFirst().allSatisfy(\.isHexDigit)
    }
}

/// One entry of `GET …/webhook`, an object keyed by webhook id. Only the fields the app needs, decoded leniently.
struct WebhookRow: Decodable {
    let type: String
    let name: String
    let url: String
    let botName: String
    let trigger: String
    let body: String
    let color: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case type = "webhook_type", name, url, botName = "bot_name", trigger, body, color, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        botName = (try? c.decode(String.self, forKey: .botName)) ?? ""
        trigger = (try? c.decode(String.self, forKey: .trigger)) ?? ""
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        let color = (try? c.decode(String.self, forKey: .color)) ?? ""
        self.color = Webhook.isValidColor(color) ? color : Webhook.defaultColor
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? ((try? c.decode(Int.self, forKey: .enabled)) ?? 0 != 0)
    }

    /// Sorted by id; keys that are not positive numbers are dropped.
    static func list(_ rows: [String: WebhookRow]) -> [Webhook] {
        rows.compactMap { key, row in
            guard let id = Int(key), id > 0 else { return nil }
            return Webhook(id: id, type: row.type, name: row.name, url: row.url, botName: row.botName,
                           triggers: Webhook.triggers(fromPanel: row.trigger), body: row.body, color: row.color,
                           enabled: row.enabled)
        }
        .sorted { $0.id < $1.id }
    }
}

/// Body for `POST …/webhook` and `PATCH …/webhook/{id}`. Validated with `additionalProperties: false`, so the
/// id never goes along; `color` is required on create although the schema has a default (500 without it).
struct WebhookBody: Encodable {
    let webhook: Webhook

    enum CodingKeys: String, CodingKey {
        case type = "webhook_type", name, url, botName = "bot_name", trigger, body, color, enabled
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(webhook.type, forKey: .type)
        try c.encode(webhook.name.trimmingCharacters(in: .whitespaces), forKey: .name)
        try c.encode(webhook.url.trimmingCharacters(in: .whitespaces), forKey: .url)
        try c.encode(webhook.botName.trimmingCharacters(in: .whitespaces), forKey: .botName)
        try c.encode(webhook.triggers, forKey: .trigger)
        try c.encode(webhook.body, forKey: .body)
        try c.encode(webhook.color, forKey: .color)
        try c.encode(webhook.enabled, forKey: .enabled)
    }
}

/// Webhook targets. Mirrors the URL pattern Crafty 4.11 enforces (4.7 checks nothing), but requires the
/// scheme, because the panel cannot send to an address without one. Plain `http://` is allowed: the panel,
/// not the app, connects to it, and self-hosted chat servers on a LAN often have no certificate.
enum WebhookURL {
    private static let pattern = #"^https?://"#
        + #"((([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,})"#
        + #"|(((25[0-5]|(2[0-4]|1\d|[1-9])?\d)\.){3}(25[0-5]|(2[0-4]|1\d|[1-9])?\d))"#
        + #"|(\[[a-fA-F0-9:]+\]))"#
        + #"(:(6553[0-5]|655[0-2]\d|65[0-4]\d{2}|6[0-4]\d{3}|[1-5]\d{4}|[1-9]\d{0,3}))?"#
        + #"(/\S*)?$"#

    static func isValid(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// `WebhookFactory.get_monitored_events()` in 4.7.0 and 4.11.0.
enum WebhookTrigger: String, CaseIterable, Identifiable {
    case serverStart = "start_server"
    case serverStop = "stop_server"
    case crash = "crash_detected"
    case backup = "backup_server"
    case jarUpdate = "jar_update"
    case command = "send_command"
    case kill = "kill"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .serverStart: "Server started"
        case .serverStop: "Server stopped"
        case .crash: "Crash detected"
        case .backup: "Backup"
        case .jarUpdate: "Server JAR updated"
        case .command: "Command sent"
        case .kill: "Server killed"
        }
    }

    /// Template variables the panel fills in for this event, besides the common ones.
    var extraVariables: [String] {
        switch self {
        case .backup: ["backup_name", "backup_link", "backup_size", "backup_status", "backup_error"]
        case .command: ["command"]
        case .kill: ["reason"]
        default: []
        }
    }

    static let commonVariables = ["server_name", "server_id", "event_type", "source_type", "source_name", "time_formatted"]

    /// Label for a stored trigger name, also for names this app version does not know.
    static func label(for name: String) -> String { WebhookTrigger(rawValue: name)?.label ?? name }
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
