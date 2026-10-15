import AppIntents
import Foundation

/// Siri and Shortcuts actions for the active panel's servers. They run inside the app with the app's own client,
/// so the token never leaves the app; iOS only learns server names and ids (ADR 0010).
@MainActor
enum ServerShortcuts {
    /// The running app's state; set at launch, also when iOS starts the app in the background for an action.
    static var app: AppState?

    enum Failure: Error, Equatable, CustomLocalizedStringResourceConvertible {
        case noPanel
        case notConfirmed
        case eulaRequired(String)

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .noPanel: "Add your panel in Kurafuto first."
            case .notConfirmed: "Kurafuto could not confirm it's you. Open Kurafuto to stop the server."
            case .eulaRequired(let name): "Open Kurafuto and accept the Minecraft EULA for \(name) first."
            }
        }
    }

    /// The active panel's service. The demo counts as a panel only while it is open in the app.
    static func service(_ app: AppState? = app) throws -> CraftyService {
        guard let app, app.activeInstance != nil else { throw Failure.noPanel }
        return app.service
    }

    static func start(serverID: String, name: String, app: AppState? = app) async throws {
        do { try await service(app).send(.start, serverID: serverID) }
        catch CraftyError.eulaRequired { throw Failure.eulaRequired(name) }
    }

    /// The caller has asked for confirmation already; with the app lock on, Face ID or the passcode is needed too.
    static func stop(serverID: String, name: String, app: AppState? = app) async throws {
        let service = try service(app)
        if let lock = app?.lock, lock.isEnabled {
            guard await lock.authorize(String(localized: "Stop \(name)?")) else { throw Failure.notConfirmed }
        }
        try await service.send(.stop, serverID: serverID)
    }

    /// Live from the panel, not the widget snapshot. Nil while the server is not running.
    static func players(serverID: String, app: AppState? = app) async throws -> (online: Int, max: Int)? {
        let stats = try await service(app).stats(serverID: serverID)
        return stats.running ? (stats.online, stats.max) : nil
    }

    static func servers(app: AppState? = app) async throws -> [PanelServerEntity] {
        try await service(app).servers().map { PanelServerEntity(id: $0.id, name: $0.serverName) }
    }
}

/// A server of the active panel, as Siri and Shortcuts know it.
struct PanelServerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Server"
    static let defaultQuery = PanelServerQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PanelServerQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PanelServerEntity] {
        try await ServerShortcuts.servers().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PanelServerEntity] {
        try await ServerShortcuts.servers().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PanelServerEntity] {
        try await ServerShortcuts.servers()
    }
}

struct StartServerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Server"
    static let description = IntentDescription("Starts a server on your Crafty panel.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Server")
    var server: PanelServerEntity

    static var parameterSummary: some ParameterSummary { Summary("Start \(\.$server)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ServerShortcuts.start(serverID: server.id, name: server.name)
        return .result(dialog: "Starting \(server.name).")
    }
}

struct StopServerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Server"
    static let description = IntentDescription("Stops a server on your Crafty panel after you confirm.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Server")
    var server: PanelServerEntity

    static var parameterSummary: some ParameterSummary { Summary("Stop \(\.$server)") }

    private static let stopAction = ConfirmationActionName.custom(acceptLabel: "Stop", acceptAlternatives: [],
                                                                  denyLabel: "Cancel", denyAlternatives: [], destructive: true)

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if #available(iOS 18, *) {
            try await requestConfirmation(actionName: Self.stopAction,
                                          dialog: "Stop \(server.name)? Connected players will be disconnected.")
        } else {
            // iOS 17 only offers the generic "Run Stop Server?" question without a deprecated API.
            try await requestConfirmation()
        }
        try await ServerShortcuts.stop(serverID: server.id, name: server.name)
        return .result(dialog: "Stopping \(server.name).")
    }
}

struct PlayerCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Player Count"
    static let description = IntentDescription("Tells how many players are online on a server.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Server")
    var server: PanelServerEntity

    static var parameterSummary: some ParameterSummary { Summary("Players on \(\.$server)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let players = try await ServerShortcuts.players(serverID: server.id) else {
            return .result(value: 0, dialog: "\(server.name) is not running.")
        }
        return .result(value: players.online, dialog: "Players online on \(server.name): \(players.online) of \(players.max).")
    }
}

struct KurafutoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartServerIntent(), phrases: [
            "Start \(\.$server) in \(.applicationName)",
            "Start a server in \(.applicationName)",
        ], shortTitle: "Start Server", systemImageName: "play.fill")
        AppShortcut(intent: StopServerIntent(), phrases: [
            "Stop \(\.$server) in \(.applicationName)",
            "Stop a server in \(.applicationName)",
        ], shortTitle: "Stop Server", systemImageName: "stop.fill")
        AppShortcut(intent: PlayerCountIntent(), phrases: [
            "How many players are on \(\.$server) in \(.applicationName)",
            "Player count in \(.applicationName)",
        ], shortTitle: "Player Count", systemImageName: "person.2.fill")
    }
}
