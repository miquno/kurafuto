import SwiftUI
import WidgetKit

/// Home Screen widgets use the look the user picked in the app; Lock Screen widgets are tinted by iOS.
struct ServerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let server = entry.server {
                switch family {
                case .accessoryCircular: PlayersRing(server: server)
                case .accessoryRectangular: ServerLines(server: server, updated: snapshot.updated)
                default: ServerTile(server: server, snapshot: snapshot)
                }
            } else {
                EmptyWidget(family: family)
            }
        }
        .privacySensitive(entry.snapshot?.isPrivate ?? false)
        .widgetURL(entry.server.flatMap { ServerLink.url(serverID: $0.id) })
        .containerBackground(for: .widget) { WidgetBackground(snapshot: entry.snapshot, family: family) }
    }
}

struct PanelWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.servers.isEmpty {
                ServerList(snapshot: snapshot)
            } else {
                EmptyWidget(family: .systemMedium)
            }
        }
        .privacySensitive(entry.snapshot?.isPrivate ?? false)
        .containerBackground(for: .widget) { WidgetBackground(snapshot: entry.snapshot, family: .systemMedium) }
    }
}

// MARK: - Home Screen

/// Small: one server with a large player count.
private struct ServerTile: View {
    let server: WidgetSnapshot.Server
    let snapshot: WidgetSnapshot

    var body: some View {
        let mode = snapshot.mode
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                StatusMark(status: server.status, snapshot: snapshot)
                Text(server.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 4)
            PlayerFigure(server: server, mode: mode)
            Text("Players online").font(.caption).foregroundStyle(Palette.secondaryText(mode))
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Text(server.status.label)
                Text(verbatim: "·")
                Text(asOf: snapshot.updated)
            }
            .font(.caption2)
            .foregroundStyle(server.status == .crashed ? Palette.danger(mode) : Palette.secondaryText(mode))
            .lineLimit(1)
        }
        .foregroundStyle(Palette.primaryText(mode))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Medium: the panel's servers, crashed ones first; each row opens its server.
private struct ServerList: View {
    let snapshot: WidgetSnapshot
    private static let rows = 4

    var body: some View {
        let mode = snapshot.mode
        let online = snapshot.servers.filter { $0.status == .online }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.panelName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(online)/\(snapshot.servers.count) online").font(.caption).foregroundStyle(Palette.secondaryText(mode))
                Text(asOf: snapshot.updated).font(.caption).foregroundStyle(Palette.secondaryText(mode))
            }
            ForEach(snapshot.servers.prefix(Self.rows)) { server in
                let row = HStack(spacing: 8) {
                    StatusMark(status: server.status, snapshot: snapshot)
                    Text(server.name).lineLimit(1)
                    Spacer(minLength: 8)
                    PlayerCell(server: server, mode: mode)
                }
                .font(.footnote)
                if let url = ServerLink.url(serverID: server.id) { Link(destination: url) { row } } else { row }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.primaryText(mode))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "4/20" in the data font, or the reason there are no players.
private struct PlayerCell: View {
    let server: WidgetSnapshot.Server
    let mode: ThemeMode

    var body: some View {
        switch server.status {
        case .online:
            Text(verbatim: "\(server.online)/\(server.max)").font(.mono(.footnote))
                .accessibilityLabel("Players: \(server.online) of \(server.max)")
        case .crashed:
            Text(server.status.label).foregroundStyle(Palette.danger(mode))
        case .offline, .starting, .updating:
            Text(server.status.label).foregroundStyle(Palette.secondaryText(mode))
        }
    }
}

private struct PlayerFigure: View {
    let server: WidgetSnapshot.Server
    let mode: ThemeMode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "\(server.online)").font(.mono(.largeTitle, weight: .semibold))
            Text(verbatim: "/\(server.max)").font(.mono(.subheadline)).foregroundStyle(Palette.secondaryText(mode))
        }
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Players: \(server.online) of \(server.max)")
    }
}

private struct StatusMark: View {
    let status: ServerStatus
    let snapshot: WidgetSnapshot

    var body: some View {
        Circle()
            .fill(Palette.color(for: status, mode: snapshot.mode, accent: snapshot.accent.color(for: snapshot.mode)))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Lock Screen

/// Circular: players as a ring around the count.
private struct PlayersRing: View {
    let server: WidgetSnapshot.Server

    var body: some View {
        Gauge(value: Double(server.online), in: 0...Double(max(server.max, 1))) {
            Image(systemName: "person.2.fill")
        } currentValueLabel: {
            Text(verbatim: "\(server.online)").font(.system(.title3, design: .rounded).weight(.semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel(Text(verbatim: server.name))
        .accessibilityValue(Text("Players: \(server.online) of \(server.max)"))
    }
}

/// Rectangular: name, status with players, and the time of the values.
private struct ServerLines: View {
    let server: WidgetSnapshot.Server
    let updated: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(server.name).font(.headline).widgetAccentable().lineLimit(1)
            HStack(spacing: 4) {
                Text(server.status.label)
                if server.status == .online {
                    Text(verbatim: "·")
                    Image(systemName: "person.2.fill").imageScale(.small)
                    Text(verbatim: "\(server.online)/\(server.max)")
                        .accessibilityLabel("Players: \(server.online) of \(server.max)")
                }
            }
            .font(.subheadline)
            .lineLimit(1)
            Text(asOf: updated).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared

private struct EmptyWidget: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "server.rack").font(.title2).accessibilityLabel("Open Kurafuto to show your servers.")
        case .accessoryRectangular:
            Text("Open Kurafuto to show your servers.").font(.caption)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "cube.transparent.fill").font(.title2).foregroundStyle(Palette.secondaryText(.dark))
                    .accessibilityHidden(true)
                Text("Open Kurafuto to show your servers.").font(.footnote)
                    .foregroundStyle(Palette.primaryText(.dark))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct WidgetBackground: View {
    let snapshot: WidgetSnapshot?
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: Color.clear
        default: Palette.surface(snapshot?.mode ?? .dark)
        }
    }
}

private extension Text {
    /// When the values were loaded: the time today, the date before that. Fixed text, because the widget
    /// is only redrawn when the app writes new values.
    init(asOf date: Date) {
        if Calendar.current.isDateInToday(date) {
            self.init(date, format: .dateTime.hour().minute())
        } else {
            self.init(date, format: .dateTime.day().month(.abbreviated))
        }
    }
}

#Preview("Small", as: .systemSmall) {
    ServerWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
    SnapshotEntry(date: .now, snapshot: nil)
}

#Preview("Medium", as: .systemMedium) {
    PanelWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview("Circular", as: .accessoryCircular) {
    ServerWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
}

#Preview("Rectangular", as: .accessoryRectangular) {
    ServerWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
}
