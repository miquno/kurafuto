import Foundation

/// Body of `POST /api/v2/auth/login`. `totp` must be left out when empty:
/// Crafty 4.11 rejects `"totp": null` as incorrect credentials.
struct LoginRequest: Encodable {
    let username: String
    let password: String
    let totp: String?
}

/// Real implementation against Crafty Controller 4 (API v2).
///
/// ✅ = documented in the official openapi-spec.yml
/// ⚠️ = exists in the panel (used by the web UI) but NOT in the spec → verify against the source
///      (gitlab.com/crafty-controller/crafty-4, app/classes/web/routes/api) and adjust paths if needed.
final class LiveCraftyService: CraftyService, @unchecked Sendable {
    let client: APIClient

    init(client: APIClient) { self.client = client }

    private typealias Empty = APIClient.Empty

    // MARK: Auth ✅
    func login(username: String, password: String, totp: String?) async throws -> String {
        struct Res: Decodable { let token: String }
        let res: Res = try await client.request(.post, "/api/v2/auth/login",
                                                body: .json(LoginRequest(username: username, password: password, totp: totp)))
        client.token = res.token
        return res.token
    }
    func invalidateAllSessions() async throws {
        let _: Empty = try await client.request(.post, "/api/v2/auth/invalidate_tokens")
    }
    func healthCheck() async throws -> Bool {
        let _: Empty = try await client.request(.get, "/api/v2/crafty/check"); return true
    }

    // MARK: Servers ✅
    func servers() async throws -> [Server] { try await client.request(.get, "/api/v2/servers") }
    func server(id: String) async throws -> Server { try await client.request(.get, "/api/v2/servers/\(id)") }
    func stats(serverID: String) async throws -> ServerStats { try await client.request(.get, "/api/v2/servers/\(serverID)/stats") }

    func send(_ action: ServerAction, serverID: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/\(action.rawValue)")
    }
    func sendCommand(_ command: String, serverID: String) async throws {
        // Per docs: send without the leading slash.
        let cmd = command.hasPrefix("/") ? String(command.dropFirst()) : command
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/stdin", body: .text(cmd))
    }
    func logs(serverID: String, fromFile: Bool) async throws -> [String] {
        let lines: [String] = try await client.request(.get, "/api/v2/servers/\(serverID)/logs",
                                                       query: [URLQueryItem(name: "file", value: fromFile ? "true" : "false")])
        return lines.map(\.unescapingCraftyLogHTML)
    }
    func updateServer(_ server: Server) async throws {
        let _: Empty = try await client.request(.patch, "/api/v2/servers/\(server.id)", body: .json(server))
    }
    func deleteServer(id: String) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/servers/\(id)")
    }
    func createServer(_ request: CreateServerRequest) async throws -> String {
        struct Res: Decodable { let new_server_id: String }
        let r: Res = try await client.request(.post, "/api/v2/servers", body: .json(request))
        return r.new_server_id
    }

    /// Polling fallback. TODO ⚠️: the Crafty web UI uses a WebSocket (`wss://host/ws?page=/panel/server_detail&...`)
    /// for the live console and stats – port the protocol from `app/classes/web/websocket_handler.py`.
    func consoleStream(serverID: String) -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            let task = Task {
                var lastCount = 0
                while !Task.isCancelled {
                    if let lines = try? await self.logs(serverID: serverID, fromFile: false) {
                        let newLines = lines.count >= lastCount ? Array(lines.dropFirst(lastCount)) : lines
                        newLines.forEach { continuation.yield(LogLine($0)) }
                        lastCount = lines.count
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Schedules – create/update/delete ✅, list ⚠️
    func schedules(serverID: String) async throws -> [Schedule] {
        try await client.request(.get, "/api/v2/servers/\(serverID)/tasks")
    }
    func createSchedule(_ schedule: Schedule, serverID: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/tasks", body: .json(schedule))
    }
    func updateSchedule(_ schedule: Schedule, serverID: String) async throws {
        let _: Empty = try await client.request(.patch, "/api/v2/servers/\(serverID)/tasks/\(schedule.id)", body: .json(schedule))
    }
    func deleteSchedule(id: Int, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/servers/\(serverID)/tasks/\(id)")
    }

    // MARK: Backups ⚠️ (triggering a backup works ✅ via action/backup_server)
    func backupConfigs(serverID: String) async throws -> [BackupConfig] {
        try await client.request(.get, "/api/v2/servers/\(serverID)/backups")
    }
    func backupFiles(serverID: String, configID: String) async throws -> [BackupFile] {
        try await client.request(.get, "/api/v2/servers/\(serverID)/backups/backup/\(configID)/files")
    }
    func restoreBackup(_ file: BackupFile, serverID: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/backups/backup/restore",
                                                body: .json(["filename": file.fileName]))
    }
    func deleteBackup(_ file: BackupFile, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/servers/\(serverID)/backups/backup/files",
                                                body: .json(["filename": file.fileName]))
    }

    // MARK: Files ⚠️ (new file endpoints since panel 4.7, e.g. files/copy, files/move)
    func listFiles(serverID: String, path: String) async throws -> [FileEntry] {
        throw CraftyError.notSupportedByPanelVersion("File manager – endpoints not verified yet")
    }
    func readFile(serverID: String, path: String) async throws -> String {
        throw CraftyError.notSupportedByPanelVersion("Reading files")
    }
    func writeFile(serverID: String, path: String, content: String) async throws {
        throw CraftyError.notSupportedByPanelVersion("Saving files")
    }
    func createFolder(serverID: String, path: String) async throws {
        throw CraftyError.notSupportedByPanelVersion("Creating folders")
    }
    func deleteFile(serverID: String, path: String) async throws {
        throw CraftyError.notSupportedByPanelVersion("Deleting files")
    }

    // MARK: Webhooks ✅
    func webhooks(serverID: String) async throws -> [Webhook] {
        let dict: [String: Webhook] = try await client.request(.get, "/api/v2/servers/\(serverID)/webhook")
        return dict.values.sorted { $0.id < $1.id }
    }
    func saveWebhook(_ webhook: Webhook, serverID: String) async throws {
        if webhook.id == 0 {
            let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/webhook", body: .json(webhook))
        } else {
            // Note: the spec uses /server/ (singular) here
            let _: Empty = try await client.request(.patch, "/api/v2/server/\(serverID)/webhook/\(webhook.id)", body: .json(webhook))
        }
    }
    func deleteWebhook(id: Int, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/server/\(serverID)/webhook/\(id)")
    }

    // MARK: Users & roles ✅
    func panelAccess() async throws -> PanelAccess {
        struct Me: Decodable { let superuser: Bool }
        async let me: Me = client.request(.get, "/api/v2/users/@me")
        async let permissions: CraftyPermissions = client.request(.get, "/api/v2/users/@me/permissions")
        return try await PanelAccess(isSuperuser: me.superuser, permissions: permissions)
    }
    func users() async throws -> [CraftyUser] { try await client.request(.get, "/api/v2/users") }
    func saveUser(_ user: CraftyUser, password: String?) async throws {
        if user.userID == 0 {
            let _: Empty = try await client.request(.post, "/api/v2/users", body: .json(user))
        } else {
            let _: Empty = try await client.request(.patch, "/api/v2/users/\(user.userID)", body: .json(user))
        }
    }
    func deleteUser(id: Int) async throws { let _: Empty = try await client.request(.delete, "/api/v2/users/\(id)") }
    func roles() async throws -> [Role] { try await client.request(.get, "/api/v2/roles") }
    func saveRole(_ role: Role) async throws {
        if role.roleID == 0 {
            let _: Empty = try await client.request(.post, "/api/v2/roles", body: .json(role))
        } else {
            let _: Empty = try await client.request(.patch, "/api/v2/roles/\(role.roleID)", body: .json(role))
        }
    }
    func deleteRole(id: Int) async throws { let _: Empty = try await client.request(.delete, "/api/v2/roles/\(id)") }

    // MARK: Panel ✅
    func hostStats() async throws -> HostStats {
        let text = try await client.rawText("/metrics/host")
        let m = OpenMetricsParser.parse(text)
        return HostStats(cpuPercent: m["CPU_Usage"] ?? 0, memPercent: m["Mem_Usage"] ?? 0, diskUsage: [], craftyVersion: "?")
    }
    func announcements() async throws -> [Announcement] { try await client.request(.get, "/api/v2/crafty/announcements") }
    func clearAnnouncement(id: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/crafty/announcements", body: .json(["id": id]))
    }
}

enum OpenMetricsParser {
    /// Minimal parser: "Name{labels} 1.23" → [Name: 1.23]
    static func parse(_ text: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let v = Double(parts[parts.count - 1]) else { continue }
            let name = parts[0].split(separator: "{").first.map(String.init) ?? String(parts[0])
            out[name] = v
        }
        return out
    }
}
