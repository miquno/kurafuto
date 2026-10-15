import Foundation

/// Complete in-memory implementation of `CraftyService`.
/// - Simulates network latency, status transitions (start takes a few seconds) and a live console.
/// - `failureRate` > 0 produces random errors to exercise the error UI.
final class MockCraftyService: CraftyService, @unchecked Sendable {
    private let lock = NSLock()
    private var servers = MockData.servers
    private var stats = MockData.stats
    private var schedules: [String: [Schedule]] = [:]
    private var backups: [String: [BackupFile]] = [:]
    private var webhooks: [String: [Webhook]] = [:]
    private var files: [String: String] = ["server.properties": MockData.serverProperties]
    private var users = MockData.users
    private var roles = MockData.roles
    private var announcementList = MockData.announcements
    private var console: [String: [String]] = [:]

    var latency: Duration
    var failureRate: Double
    /// What `panelAccess()` reports; the demo signs in as a superuser.
    var grantedAccess: PanelAccess

    init(latency: Duration = .milliseconds(350), failureRate: Double = 0, access: PanelAccess = .superuser) {
        self.latency = latency
        self.failureRate = failureRate
        self.grantedAccess = access
    }

    private func simulate() async throws {
        try await Task.sleep(for: latency)
        if Double.random(in: 0..<1) < failureRate {
            throw CraftyError.transport(URLError(.timedOut))
        }
    }

    private func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    // MARK: Auth
    func login(username: String, password: String, totp: String?) async throws -> String {
        try await simulate()
        guard !password.isEmpty else { throw CraftyError.unauthorized }
        return "mock-token-\(username)"
    }
    func invalidateAllSessions() async throws { try await simulate() }
    func healthCheck() async throws -> Bool { try await simulate(); return true }

    // MARK: Servers
    func servers() async throws -> [Server] { try await simulate(); return sync { servers } }

    func server(id: String) async throws -> Server {
        try await simulate()
        guard let s = sync({ servers.first { $0.id == id } }) else { throw CraftyError.server(code: "NOT_FOUND", detail: nil) }
        return s
    }

    func stats(serverID: String) async throws -> ServerStats {
        try await simulate()
        return sync {
            var s = stats[serverID] ?? ServerStats(running: false, cpu: 0, mem: "0MB", memPercent: 0, online: 0, max: 20, players: [])
            if s.running { // add some movement to the values
                s.cpu = max(1, min(95, s.cpu + Double.random(in: -6...6)))
                s.memPercent = max(5, min(90, s.memPercent + Double.random(in: -2...2)))
                stats[serverID] = s
            }
            return s
        }
    }

    func send(_ action: ServerAction, serverID: String) async throws {
        try await simulate()
        switch action {
        case .start, .restart:
            sync { stats[serverID]?.waitingStart = true; stats[serverID]?.crashed = false }
            appendConsole(serverID, "> \(action.rawValue)")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.sync {
                    self?.stats[serverID]?.waitingStart = false
                    self?.stats[serverID]?.running = true
                    self?.stats[serverID]?.started = MockData.startedString(.now)
                    self?.stats[serverID]?.cpu = 18
                    self?.stats[serverID]?.mem = "2.2GB"
                    self?.stats[serverID]?.memPercent = 27
                }
                self?.appendConsole(serverID, "[\(MockData.consoleTime(.now)) INFO]: Done (8.214s)! For help, type \"help\"")
            }
        case .stop, .kill:
            sync {
                stats[serverID]?.running = false
                stats[serverID]?.started = nil
                stats[serverID]?.online = 0
                stats[serverID]?.players = []
                stats[serverID]?.cpu = 0
                stats[serverID]?.mem = "0MB"
                stats[serverID]?.memPercent = 0
            }
            appendConsole(serverID, "[\(MockData.consoleTime(.now)) INFO]: Stopping server")
        case .backup:
            let file = BackupFile(path: "/crafty/backups/\(serverID)/\(Int(Date().timeIntervalSince1970)).zip",
                                  size: 2_410_000_000, created: .now)
            sync { backups[serverID, default: MockData.backupFiles].insert(file, at: 0) }
        case .clone:
            sync {
                if var copy = servers.first(where: { $0.id == serverID }) {
                    let newID = UUID().uuidString.lowercased()
                    copy = Server(serverID: newID, serverName: copy.serverName + " (Copy)", created: nil, path: nil,
                                  backupPath: nil, executable: copy.executable, logPath: nil,
                                  executionCommand: copy.executionCommand, autoStart: false, autoStartDelay: 10,
                                  crashDetection: copy.crashDetection, stopCommand: copy.stopCommand,
                                  executableUpdateURL: nil, serverIP: copy.serverIP, serverPort: copy.serverPort + 10,
                                  logsDeleteAfter: copy.logsDeleteAfter, type: copy.type)
                    servers.append(copy)
                    stats[newID] = ServerStats(running: false, cpu: 0, mem: "0MB", memPercent: 0, online: 0, max: 20, players: [])
                }
            }
        case .updateExecutable:
            sync { stats[serverID]?.updating = true }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.sync { self?.stats[serverID]?.updating = false }
            }
        }
    }

    func sendCommand(_ command: String, serverID: String) async throws {
        try await simulate()
        appendConsole(serverID, "> \(command)")
        let response: String = switch command.split(separator: " ").first.map(String.init) ?? "" {
        case "list":
            "[INFO]: There are \(sync { stats[serverID]?.online ?? 0 }) of a max of 20 players online"
        case "say": "[INFO]: [Server] \(command.dropFirst(4))"
        case "kick": "[INFO]: Kicked \(command.dropFirst(5)) from the game"
        case "op": "[INFO]: Made \(command.dropFirst(3)) a server operator"
        default: "[INFO]: Unknown or incomplete command"
        }
        appendConsole(serverID, response)
    }

    private func appendConsole(_ serverID: String, _ line: String) {
        sync { console[serverID, default: MockData.consoleLines].append(line) }
    }

    func logs(serverID: String, fromFile: Bool) async throws -> [String] {
        try await simulate()
        return sync { console[serverID] ?? MockData.consoleLines }
    }

    func consoleStream(serverID: String) -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                var seen = 0
                while !Task.isCancelled {
                    let lines = self.sync { self.console[serverID] ?? MockData.consoleLines }
                    for line in lines.dropFirst(seen) { continuation.yield(LogLine(line)) }
                    seen = lines.count
                    try? await Task.sleep(for: .seconds(Double.random(in: 2...5)))
                    if self.sync({ self.stats[serverID]?.running == true }) {
                        let now = MockData.consoleTime(.now)
                        self.appendConsole(serverID, "[\(now) " + (MockData.randomLines.randomElement() ?? "[INFO]: tick").dropFirst())
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func updateServer(_ server: Server) async throws {
        try await simulate()
        sync { if let i = servers.firstIndex(where: { $0.id == server.id }) { servers[i] = server } }
    }

    func deleteServer(id: String) async throws {
        try await simulate()
        sync { servers.removeAll { $0.id == id }; stats[id] = nil }
    }

    func createServer(_ request: CreateServerRequest) async throws -> String {
        try await Task.sleep(for: .seconds(2)) // simulate downloading the JAR
        let id = UUID().uuidString.lowercased()
        let jar = request.kind == .java ? "\(request.jarType)-\(request.version).jar" : "bedrock_server"
        sync {
            servers.append(MockData.server(id, request.name, jar, port: request.port,
                                           type: request.kind == .java ? .minecraftJava : .minecraftBedrock))
            stats[id] = ServerStats(running: false, cpu: 0, mem: "0MB", memPercent: 0, online: 0, max: 20,
                                    players: [], version: request.version, firstRun: true)
        }
        return id
    }

    // MARK: Schedules
    func schedules(serverID: String) async throws -> [Schedule] {
        try await simulate(); return sync { schedules[serverID] ?? MockData.schedules }
    }
    func createSchedule(_ schedule: Schedule, serverID: String) async throws {
        try await simulate()
        sync {
            var list = schedules[serverID] ?? MockData.schedules
            var s = schedule; s.id = (list.map(\.id).max() ?? 0) + 1
            list.append(s); schedules[serverID] = list
        }
    }
    func updateSchedule(_ schedule: Schedule, serverID: String) async throws {
        try await simulate()
        sync {
            var list = schedules[serverID] ?? MockData.schedules
            if let i = list.firstIndex(where: { $0.id == schedule.id }) { list[i] = schedule }
            schedules[serverID] = list
        }
    }
    func deleteSchedule(id: Int, serverID: String) async throws {
        try await simulate()
        sync { var l = schedules[serverID] ?? MockData.schedules; l.removeAll { $0.id == id }; schedules[serverID] = l }
    }

    // MARK: Backups
    func backupConfigs(serverID: String) async throws -> [BackupConfig] { try await simulate(); return MockData.backupConfigs }
    func backupFiles(serverID: String, configID: String) async throws -> [BackupFile] {
        try await simulate(); return sync { backups[serverID] ?? MockData.backupFiles }
    }
    func restoreBackup(_ file: BackupFile, serverID: String) async throws { try await Task.sleep(for: .seconds(2)) }
    func deleteBackup(_ file: BackupFile, serverID: String) async throws {
        try await simulate()
        sync { var l = backups[serverID] ?? MockData.backupFiles; l.removeAll { $0 == file }; backups[serverID] = l }
    }

    // MARK: Files
    func listFiles(serverID: String, path: String) async throws -> [FileEntry] {
        try await simulate()
        switch path {
        case "", "/": return MockData.rootFiles
        case "plugins": return MockData.pluginFiles
        default: return []
        }
    }
    func readFile(serverID: String, path: String) async throws -> String {
        try await simulate()
        return sync { files[path] ?? "# \(path)\n# (mock content)\n" }
    }
    func writeFile(serverID: String, path: String, content: String) async throws {
        try await simulate(); sync { files[path] = content }
    }
    func createFolder(serverID: String, path: String) async throws { try await simulate() }
    func deleteFile(serverID: String, path: String) async throws { try await simulate() }

    // MARK: Webhooks
    func webhooks(serverID: String) async throws -> [Webhook] {
        try await simulate(); return sync { webhooks[serverID] ?? MockData.webhooks }
    }
    func saveWebhook(_ webhook: Webhook, serverID: String) async throws {
        try await simulate()
        sync {
            var l = webhooks[serverID] ?? MockData.webhooks
            if let i = l.firstIndex(where: { $0.id == webhook.id }) { l[i] = webhook }
            else { var w = webhook; w.id = (l.map(\.id).max() ?? 0) + 1; l.append(w) }
            webhooks[serverID] = l
        }
    }
    func deleteWebhook(id: Int, serverID: String) async throws {
        try await simulate()
        sync { var l = webhooks[serverID] ?? MockData.webhooks; l.removeAll { $0.id == id }; webhooks[serverID] = l }
    }

    // MARK: Users & roles
    func panelAccess() async throws -> PanelAccess { try await simulate(); return sync { grantedAccess } }
    func users() async throws -> [CraftyUser] { try await simulate(); return sync { users } }
    func saveUser(_ user: CraftyUser, password: String?) async throws {
        try await simulate()
        sync {
            if let i = users.firstIndex(where: { $0.id == user.id }) { users[i] = user }
            else { var u = user; u.userID = (users.map(\.userID).max() ?? 0) + 1; users.append(u) }
        }
    }
    func deleteUser(id: Int) async throws { try await simulate(); sync { users.removeAll { $0.id == id } } }
    func roles() async throws -> [Role] { try await simulate(); return sync { roles } }
    func saveRole(_ role: Role) async throws {
        try await simulate()
        sync {
            if let i = roles.firstIndex(where: { $0.id == role.id }) { roles[i] = role }
            else { var r = role; r.roleID = (roles.map(\.roleID).max() ?? 0) + 1; roles.append(r) }
        }
    }
    func deleteRole(id: Int) async throws { try await simulate(); sync { roles.removeAll { $0.id == id } } }

    // MARK: Panel
    func hostStats() async throws -> HostStats {
        try await simulate()
        var h = MockData.host
        h.cpuPercent = Double.random(in: 20...45)
        return h
    }
    func announcements() async throws -> [Announcement] { try await simulate(); return sync { announcementList } }
    func clearAnnouncement(id: String) async throws {
        try await simulate(); sync { announcementList.removeAll { $0.id == id } }
    }
}
