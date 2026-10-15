import Foundation

/// Central interface to the Crafty API. The UI ONLY knows this protocol –
/// so everything can be built, tested and previewed with `MockCraftyService`.
protocol CraftyService: AnyObject, Sendable {
    // Auth
    func login(username: String, password: String, totp: String?) async throws -> String
    func invalidateAllSessions() async throws
    func healthCheck() async throws -> Bool

    // Servers
    func servers() async throws -> [Server]
    func server(id: String) async throws -> Server
    func stats(serverID: String) async throws -> ServerStats
    /// Throws `CraftyError.eulaRequired` when the panel refuses to start a Java server without an accepted EULA.
    func send(_ action: ServerAction, serverID: String) async throws
    /// Accepts the Minecraft EULA for a server; the panel starts the server right after.
    func acceptEULA(serverID: String) async throws
    func sendCommand(_ command: String, serverID: String) async throws
    func logs(serverID: String, fromFile: Bool) async throws -> [String]
    func updateServer(_ server: Server) async throws
    func deleteServer(id: String) async throws
    func createServer(_ request: CreateServerRequest) async throws -> String

    /// Live console. Live implementation: WebSocket `/ws` (undocumented) with fallback to polling `logs`.
    func consoleStream(serverID: String) -> AsyncStream<LogLine>

    // Schedules
    /// Nil when the panel cannot list schedules: Crafty 4.7–4.11 has no list endpoint.
    func schedules(serverID: String) async throws -> [Schedule]?
    func createSchedule(_ schedule: Schedule, serverID: String) async throws
    func updateSchedule(_ schedule: Schedule, serverID: String) async throws
    func deleteSchedule(id: Int, serverID: String) async throws

    // Backups
    func backupConfigs(serverID: String) async throws -> [BackupConfig]
    func backupFiles(serverID: String, configID: String) async throws -> [BackupFile]
    func restoreBackup(_ file: BackupFile, serverID: String) async throws
    func deleteBackup(_ file: BackupFile, serverID: String) async throws

    // Files
    func listFiles(serverID: String, path: String) async throws -> [FileEntry]
    func readFile(serverID: String, path: String) async throws -> String
    func writeFile(serverID: String, path: String, content: String) async throws
    func createFolder(serverID: String, path: String) async throws
    func deleteFile(serverID: String, path: String) async throws

    // Webhooks
    func webhooks(serverID: String) async throws -> [Webhook]
    func saveWebhook(_ webhook: Webhook, serverID: String) async throws
    func deleteWebhook(id: Int, serverID: String) async throws

    // Users & roles (superuser, or USER_CONFIG / ROLES_CONFIG)
    func panelAccess() async throws -> PanelAccess
    func users() async throws -> [CraftyUser]
    func saveUser(_ user: CraftyUser, password: String?) async throws
    func deleteUser(id: Int) async throws
    func roles() async throws -> [Role]
    func saveRole(_ role: Role) async throws
    func deleteRole(id: Int) async throws

    // Panel
    func hostStats() async throws -> HostStats
    func announcements() async throws -> [Announcement]
    func clearAnnouncement(id: String) async throws
}

enum CraftyError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden(String)
    case server(code: String, detail: String?)
    case decoding(Error)
    case transport(Error)
    case untrustedCertificate(sha256: String)
    case notSupportedByPanelVersion(String)
    case eulaRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid address."
        case .unauthorized: "Session expired. Please sign in again."
        case .forbidden(let what): "Permission denied: \(what)"
        case .server(let code, let detail): "Panel error \(code)\(detail.map { ": \($0)" } ?? "")"
        case .decoding(let e): "Could not read response: \(e.localizedDescription)"
        case .transport(let e): "Connection failed: \(e.localizedDescription)"
        case .untrustedCertificate: "The certificate is self-signed. Verify the fingerprint and trust it?"
        case .notSupportedByPanelVersion(let f): "\(f) is not supported by this panel version."
        case .eulaRequired: "The Minecraft EULA must be accepted before this server can start."
        }
    }
}

/// What went wrong, as far as the user can act on it.
enum PanelProblem: Equatable {
    case offline, sessionExpired, permissionDenied, other
}

extension Error {
    var panelProblem: PanelProblem {
        switch self as? CraftyError {
        case .unauthorized: return .sessionExpired
        case .forbidden: return .permissionDenied
        case .transport(let underlying): return underlying.isOffline ? .offline : .other
        default: return isOffline ? .offline : .other
        }
    }

    private var isOffline: Bool {
        guard let code = (self as? URLError)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed].contains(code)
    }
}
