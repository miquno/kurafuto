import Foundation
import WidgetKit

/// Keeps the widget snapshot in step with what the Servers tab last loaded.
enum WidgetSync {
    /// An unchanged panel only refreshes the widgets' "as of" time this often, so polling does not reload them every 5 s.
    static let refreshInterval: TimeInterval = 300

    static func snapshot(panelName: String, servers: [Server], stats: [String: ServerStats], isPrivate: Bool,
                         mode: ThemeMode, accent: AccentPreset, now: Date = .now) -> WidgetSnapshot {
        let rows = servers.map { server in
            let s = stats[server.id]
            return WidgetSnapshot.Server(id: server.id, name: server.serverName, status: s?.status ?? .offline,
                                         online: s?.online ?? 0, max: s?.max ?? 0)
        }
        return WidgetSnapshot(panelName: panelName, servers: WidgetSnapshot.ordered(rows), updated: now,
                              isPrivate: isPrivate, mode: mode, accent: accent)
    }

    static func needsWrite(old: WidgetSnapshot?, new: WidgetSnapshot) -> Bool {
        guard var old else { return true }
        let age = new.updated.timeIntervalSince(old.updated)
        old.updated = new.updated
        return old != new || age >= refreshInterval
    }

    static func publish(_ snapshot: WidgetSnapshot, to store: WidgetSnapshotStore = .shared) {
        guard needsWrite(old: store.load(), new: snapshot) else { return }
        // A failed write leaves the widgets on their older values, which show their own time; nothing for the user to do.
        guard (try? store.save(snapshot)) != nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// After signing out or switching panels, so no widget keeps showing the previous panel.
    static func clear(_ store: WidgetSnapshotStore = .shared) {
        store.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
