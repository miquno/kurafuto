import Foundation
import WidgetKit

/// Keeps the widget snapshot in step with what the Servers tab last loaded.
enum WidgetSync {
    /// Live load values (CPU, RAM, their trends) refresh the widgets at most this often; a change of status,
    /// players or backups is written right away.
    static let refreshInterval: TimeInterval = 300

    static func snapshot(panelName: String, servers: [Server], stats: [String: ServerStats], history: [String: [StatSample]],
                         backups: [String: WidgetSnapshot.Backup], isPrivate: Bool, mode: ThemeMode, accent: AccentPreset,
                         now: Date = .now) -> WidgetSnapshot {
        let rows = servers.map { server in
            let s = stats[server.id]
            let running = s?.running == true
            let samples = history[server.id] ?? []
            return WidgetSnapshot.Server(
                id: server.id, name: server.serverName, status: s?.status ?? .offline,
                online: s?.online ?? 0, max: s?.max ?? 0, version: s?.version,
                cpu: running ? s?.cpu : nil, memBytes: running ? s?.memBytes : nil, memLimitBytes: server.maxMemoryBytes,
                cpuTrend: WidgetSnapshot.trend(samples.map(\.cpu)), memTrend: WidgetSnapshot.trend(samples.map(\.memBytes)),
                players: (s?.players ?? []).prefix(WidgetSnapshot.maxPlayers).map { String($0.prefix(32)) },
                lastBackup: backups[server.id])
        }
        return WidgetSnapshot(panelName: panelName, servers: WidgetSnapshot.ordered(rows), updated: now,
                              isPrivate: isPrivate, mode: mode, accent: accent)
    }

    static func needsWrite(old: WidgetSnapshot?, new: WidgetSnapshot) -> Bool {
        guard let old else { return true }
        return !isSame(old.essentials, new.essentials) || new.updated.timeIntervalSince(old.updated) >= refreshInterval
    }

    private static func isSame<T: Equatable>(_ a: T, _ b: T) -> Bool { a == b }

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

    /// Kinds of the widgets the user has placed, so the app only loads what they show.
    static func installedKinds() async -> Set<String> {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(returning: Set(((try? result.get()) ?? []).map(\.kind)))
            }
        }
    }
}
