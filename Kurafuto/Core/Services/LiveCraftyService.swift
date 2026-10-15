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
        // Without a config id, 4.7.0 answers ok but the backup fails inside the panel.
        if action == .backup, let config = try? await backupConfigs(serverID: serverID).first {
            return try await startBackup(serverID: serverID, configID: config.id)
        }
        // Crafty answers start_server with ok and reports a missing EULA only over the WebSocket, so the socket
        // has to be connected (answered a ping) before the request goes out.
        guard action == .start,
              let socket = try? client.webSocket("/ws", query: CraftyConsoleFeed.socketQuery(serverID: serverID)) else {
            let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/\(action.rawValue)")
            return
        }
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        let connected = await Self.ping(socket)
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/\(action.rawValue)")
        if connected, await Self.panelAsksForEULA(socket, serverID: serverID) { throw CraftyError.eulaRequired }
    }
    func acceptEULA(serverID: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/eula")
    }

    /// The panel's command queue polls once per second, so the EULA request arrives within about two seconds.
    /// Console output from the server means it is starting and ends the wait early.
    private static func panelAsksForEULA(_ socket: URLSessionWebSocketTask, serverID: String) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                while let text = try? await receive(from: socket) {
                    if CraftyConsoleFeed.eulaRequest(fromSocketMessage: text) == serverID { return true }
                    if !CraftyConsoleFeed.lines(fromSocketMessage: text).isEmpty { return false }
                }
                return false
            }
            group.addTask { try? await Task.sleep(for: .seconds(4)); return false }
            let asked = await group.next() ?? false
            group.cancelAll()
            return asked
        }
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

    /// Backlog from `/logs`, then new lines over the panel WebSocket `/ws` ⚠️ (undocumented; see
    /// `CraftyConsoleFeed`). If the socket is refused, drops or stops answering pings, the stream keeps
    /// going by polling `/logs`.
    func consoleStream(serverID: String) -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            let task = Task {
                var shown = (try? await self.logs(serverID: serverID, fromFile: false)) ?? []
                shown.forEach { continuation.yield(LogLine($0)) }

                if let socket = try? self.client.webSocket("/ws", query: CraftyConsoleFeed.socketQuery(serverID: serverID)) {
                    socket.resume()
                    let keepAlive = Task { await Self.keepAlive(socket) }
                    while !Task.isCancelled, let message = try? await Self.receive(from: socket) {
                        let lines = CraftyConsoleFeed.lines(fromSocketMessage: message)
                        lines.forEach { continuation.yield(LogLine($0)) }
                        shown = CraftyConsoleFeed.remember(lines, after: shown)
                    }
                    keepAlive.cancel()
                    socket.cancel(with: .goingAway, reason: nil)
                }

                while !Task.isCancelled {
                    if let current = try? await self.logs(serverID: serverID, fromFile: false) {
                        CraftyConsoleFeed.newLines(after: shown, in: current).forEach { continuation.yield(LogLine($0)) }
                        shown = current
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func receive(from socket: URLSessionWebSocketTask) async throws -> String {
        let message = try await withTaskCancellationHandler {
            try await socket.receive()
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
        switch message {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }

    /// Crafty stays silent while a server is idle, so a dead connection only shows up through pings.
    private static func keepAlive(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, await ping(socket) else { return }
        }
    }

    /// True when the panel answered within the timeout. A ping is only sent after the handshake, so a pong
    /// also means the socket is connected. On timeout the socket is cancelled.
    private static func ping(_ socket: URLSessionWebSocketTask, timeout: Duration = .seconds(10)) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { done in socket.sendPing { done.resume(returning: $0 == nil) } }
            }
            group.addTask { try? await Task.sleep(for: timeout); return false }
            let first = await group.next() ?? false
            // Cancelling the socket also completes a pending ping, so the group can finish.
            if !first { socket.cancel(with: .goingAway, reason: nil) }
            group.cancelAll()
            return first
        }
    }

    // MARK: Schedules ✅ create/update/delete
    /// Crafty 4.7–4.11 cannot list schedules: `GET …/tasks` is an empty stub that answers 500, and
    /// `POST …/tasks` returns no id for disabled or chained schedules. Only the web panel lists them.
    func schedules(serverID: String) async throws -> [Schedule]? { nil }
    func createSchedule(_ schedule: Schedule, serverID: String) async throws {
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/tasks", body: .json(schedule))
    }
    func updateSchedule(_ schedule: Schedule, serverID: String) async throws {
        let _: Empty = try await client.request(.patch, "/api/v2/servers/\(serverID)/tasks/\(schedule.id)", body: .json(schedule))
    }
    func deleteSchedule(id: Int, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, "/api/v2/servers/\(serverID)/tasks/\(id)")
    }

    // MARK: Backups ✅ (routes from the panel source, verified on 4.7.0 and 4.11.0)
    /// Answers without the envelope: an object keyed by backup id.
    func backupConfigs(serverID: String) async throws -> [BackupConfig] {
        let configs: [String: BackupConfig] = try await client.requestUnwrapped(.get, "/api/v2/servers/\(serverID)/backups")
        return BackupConfig.sorted(configs.values)
    }
    func saveBackupConfig(_ config: BackupConfig, includeLocation: Bool, serverID: String) async throws {
        let body = BackupConfigBody(config: config, includeLocation: includeLocation)
        if config.id.isEmpty {
            let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/backups", body: .json(body))
        } else {
            let _: Empty = try await client.request(.patch, try Self.backupPath(serverID, config.id), body: .json(body))
        }
    }
    func deleteBackupConfig(id: String, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, try Self.backupPath(serverID, id))
    }
    /// `GET …/files` exists since 4.11 and lists only `*.zip` paths; 4.7 answers 405.
    func backupFiles(serverID: String, config: BackupConfig) async throws -> [BackupFile]? {
        guard config.kind == .zip else { return nil }
        struct Res: Decodable { let backups: [String] }
        do {
            let res: Res = try await client.requestUnwrapped(.get, try Self.backupPath(serverID, config.id) + "/files")
            return BackupFile.list(fromPaths: res.backups)
        } catch CraftyError.server(code: "METHOD_NOT_ALLOWED", _) {
            return nil
        }
    }
    func startBackup(serverID: String, configID: String) async throws {
        guard BackupConfig.isValidID(configID) else { throw CraftyError.invalidURL }
        let _: Empty = try await client.request(.post, "/api/v2/servers/\(serverID)/action/backup_server/\(configID)")
    }
    func restoreBackup(_ file: BackupFile, configID: String, inPlace: Bool, serverID: String) async throws {
        struct Body: Encodable { let filename: String; let inPlace: Bool }
        let _: Empty = try await client.request(.post, try Self.backupPath(serverID, configID),
                                                body: .json(Body(filename: file.name, inPlace: inPlace)))
    }
    func deleteBackup(_ file: BackupFile, configID: String, serverID: String) async throws {
        let _: Empty = try await client.request(.delete, try Self.backupPath(serverID, configID) + "/files",
                                                body: .json(["filename": file.name]))
    }

    private static func backupPath(_ serverID: String, _ configID: String) throws -> String {
        guard BackupConfig.isValidID(configID) else { throw CraftyError.invalidURL }
        return "/api/v2/servers/\(serverID)/backups/backup/\(configID)"
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
