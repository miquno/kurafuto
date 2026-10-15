import AppIntents
import SwiftUI
import WidgetKit

@main
struct KurafutoWidgets: WidgetBundle {
    var body: some Widget {
        ServerWidget()
        PanelWidget()
    }
}

/// One server: status and players on the Home Screen (small) and the Lock Screen (circular, rectangular).
struct ServerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "dev.miquno.kurafuto.server", intent: SelectServerIntent.self, provider: SnapshotProvider()) { entry in
            ServerWidgetView(entry: entry)
        }
        .configurationDisplayName("Server")
        .description("Status and players of one server.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

/// Every server of the panel, crashed ones first.
struct PanelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.miquno.kurafuto.panel", provider: SnapshotProvider()) { entry in
            PanelWidgetView(entry: entry)
        }
        .configurationDisplayName("Servers")
        .description("Status and players of every server on your panel.")
        .supportedFamilies([.systemMedium])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var serverID: String?

    var server: WidgetSnapshot.Server? { snapshot?.server(id: serverID) }
}

/// Reads the snapshot the app wrote. The app reloads the widgets when it changes, so there is one entry and no schedule.
struct SnapshotProvider: AppIntentTimelineProvider, TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    // AppIntentTimelineProvider (ServerWidget)
    func snapshot(for configuration: SelectServerIntent, in context: Context) async -> SnapshotEntry {
        entry(serverID: configuration.server?.id, preview: context.isPreview)
    }

    func timeline(for configuration: SelectServerIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        Timeline(entries: [entry(serverID: configuration.server?.id, preview: false)], policy: .never)
    }

    // TimelineProvider (PanelWidget)
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entry(serverID: nil, preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [entry(serverID: nil, preview: false)], policy: .never))
    }

    /// The gallery shows sample servers until the app has written a snapshot.
    private func entry(serverID: String?, preview: Bool) -> SnapshotEntry {
        let stored = WidgetSnapshotStore.shared.load()
        return SnapshotEntry(date: .now, snapshot: stored ?? (preview ? .sample : nil), serverID: serverID)
    }
}

struct SelectServerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Server"
    static let description = IntentDescription("Choose the server this widget shows.")

    @Parameter(title: "Server")
    var server: ServerEntity?
}

/// A server from the snapshot; the widget's configuration lists the servers the app last saw.
struct ServerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Server"
    static let defaultQuery = ServerQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ServerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ServerEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ServerEntity] { all() }

    private func all() -> [ServerEntity] {
        (WidgetSnapshotStore.shared.load()?.servers ?? []).map { ServerEntity(id: $0.id, name: $0.name) }
    }
}
