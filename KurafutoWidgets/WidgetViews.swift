import SwiftUI
import WidgetKit

// Layouts follow the maintainer's widget mocks. Home Screen widgets use the look picked in the app; Lock Screen
// widgets are tinted by iOS. The "KURAFUTO クラフト" mark only appears where the large widgets have room for it.

// MARK: - Widget roots

struct ServerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        WidgetFrame(entry: entry) { snapshot, look in
            if let server = entry.server {
                switch family {
                case .systemMedium: ServerPulse(server: server, snapshot: snapshot, look: look)
                case .systemLarge: ServerFocus(server: server, snapshot: snapshot, look: look)
                case .accessoryRectangular: ServerGlance(server: server, updated: snapshot.updated)
                case .accessoryInline: ServerInline(server: server)
                default: PlayerOrbit(server: server, snapshot: snapshot, look: look)
                }
            }
        }
        .widgetURL(entry.server.flatMap { ServerLink.url(serverID: $0.id) })
    }
}

struct LoadWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        WidgetFrame(entry: entry) { snapshot, look in
            if let server = entry.server {
                switch family {
                case .accessoryRectangular: LoadTrace(server: server)
                default: CPUPulse(server: server, snapshot: snapshot, look: look)
                }
            }
        }
        .widgetURL(entry.server.flatMap { ServerLink.url(serverID: $0.id, screen: .details) })
    }
}

struct PlayersWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        WidgetFrame(entry: entry) { snapshot, look in
            if let server = entry.server { FriendsOnline(server: server, snapshot: snapshot, look: look) }
        }
        .widgetURL(entry.server.flatMap { ServerLink.url(serverID: $0.id) })
    }
}

struct BackupWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        WidgetFrame(entry: entry) { _, look in
            if let server = entry.server { BackupStamp(server: server, look: look) }
        }
        .widgetURL(entry.server.flatMap { ServerLink.url(serverID: $0.id, screen: .details) })
    }
}

struct PanelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        WidgetFrame(entry: entry) { snapshot, look in
            switch family {
            case .systemLarge: PanelDashboard(snapshot: snapshot, look: look)
            case .accessoryCircular: PanelFraction(snapshot: snapshot)
            case .accessoryInline: PanelInline(snapshot: snapshot)
            default: ServerLedger(snapshot: snapshot, look: look)
            }
        }
    }
}

/// Background, empty state and the app lock's privacy for every widget.
private struct WidgetFrame<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry
    @ViewBuilder let content: (WidgetSnapshot, Look) -> Content

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.servers.isEmpty {
                content(snapshot, Look(snapshot))
            } else {
                EmptyWidget(family: family)
            }
        }
        .privacySensitive(entry.snapshot?.isPrivate ?? false)
        .containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline: Color.clear
            default: Palette.surface(entry.snapshot?.mode ?? .dark)
            }
        }
    }
}

// MARK: - Small

/// 02 · One server's players as a ring.
private struct PlayerOrbit: View {
    let server: WidgetSnapshot.Server
    let snapshot: WidgetSnapshot
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(server.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            ZStack {
                Circle().stroke(look.track, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: server.max > 0 ? min(Double(server.online) / Double(server.max), 1) : 0)
                    .stroke(look.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: "\(server.online)").font(.title2.weight(.semibold))
                    Text(verbatim: "/\(server.max)").font(.caption2).foregroundStyle(look.secondary)
                }
                .monospacedDigit()
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Players: \(server.online) of \(server.max)"))
            HStack {
                StatusLabel(status: server.status, look: look)
                Spacer(minLength: 4)
                Text(verbatim: Format.time(snapshot.updated)).foregroundStyle(look.secondary)
            }
            .font(.caption2)
        }
        .foregroundStyle(look.primary)
    }
}

/// 03 · CPU of the last hour.
private struct CPUPulse: View {
    let server: WidgetSnapshot.Server
    let snapshot: WidgetSnapshot
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(server.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("CPU · last hour").font(.caption2).foregroundStyle(look.secondary)
            Text(verbatim: server.cpu.map(Format.percent) ?? "–")
                .font(.system(.title, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            if server.cpu == nil {
                StatusLabel(status: server.status, look: look).font(.caption)
            }
            Spacer(minLength: 0)
            Sparkline(values: server.cpuTrend, color: look.accent).frame(height: 26)
            Text("As of \(Format.time(snapshot.updated))").font(.caption2).foregroundStyle(look.secondary)
        }
        .foregroundStyle(look.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 05 · The newest backup archive.
private struct BackupStamp: View {
    let server: WidgetSnapshot.Server
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Backup").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "archivebox").foregroundStyle(look.accent).accessibilityHidden(true)
            }
            Text(server.name).font(.caption2).foregroundStyle(look.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if let backup = server.lastBackup {
                Text(verbatim: Format.backupTime(backup.date))
                    .font(.system(.title, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 5) {
                    Circle().fill(look.online).frame(width: 6, height: 6)
                    Text("Backed up").foregroundStyle(look.online)
                }
                .font(.caption)
                Spacer(minLength: 0)
                Text(backup.configName).font(.caption2).foregroundStyle(look.secondary).lineLimit(1)
            } else {
                Text(verbatim: "–").font(.system(.title, weight: .semibold))
                Text("No backup listed").font(.caption).foregroundStyle(look.secondary)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(look.primary)
    }
}

// MARK: - Medium

/// 07 · CPU and RAM side by side.
private struct ServerPulse: View {
    let server: WidgetSnapshot.Server
    let snapshot: WidgetSnapshot
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(server.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: Format.time(snapshot.updated)).font(.caption).foregroundStyle(look.secondary)
            }
            HStack {
                StatusLabel(status: server.status, look: look)
                Spacer(minLength: 8)
                Text(Format.players(server)).foregroundStyle(look.secondary)
            }
            .font(.caption)
            Spacer(minLength: 0)
            if server.cpu != nil {
                HStack(alignment: .bottom, spacing: 14) {
                    Metric(label: Text(verbatim: "CPU"), value: server.cpu.map(Format.percent) ?? "–",
                           trend: server.cpuTrend, look: look)
                    Rectangle().fill(look.divider).frame(width: 1)
                    Metric(label: server.memLimitBytes.map { Text("RAM · of \(Format.gigabytes($0))") } ?? Text(verbatim: "RAM"),
                           value: server.memBytes.map(Format.gigabytes) ?? "–", trend: server.memTrend, look: look)
                }
            } else {
                Text("The server is not running.").font(.footnote).foregroundStyle(look.secondary)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(look.primary)
    }
}

/// 08 · Every server in one line each.
private struct ServerLedger: View {
    let snapshot: WidgetSnapshot
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.panelName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: Format.time(snapshot.updated)).font(.caption).foregroundStyle(look.secondary)
            }
            ForEach(snapshot.servers.prefix(4)) { server in
                ServerRowLink(server: server) {
                    HStack(spacing: 8) {
                        Text(server.name).lineLimit(1)
                            .foregroundStyle(server.status == .crashed ? look.danger : look.primary)
                        Spacer(minLength: 8)
                        Text(server.status.label)
                            .foregroundStyle(server.status == .crashed ? look.danger : look.secondary)
                        if server.status != .crashed {
                            Text(verbatim: server.status == .online ? "\(server.online)/\(server.max)" : "–")
                                .fontWeight(.semibold).monospacedDigit()
                        }
                    }
                    .font(.footnote)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(look.primary)
    }
}

/// 09 · Who is online, as initials.
private struct FriendsOnline: View {
    let server: WidgetSnapshot.Server
    let snapshot: WidgetSnapshot
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(server.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(verbatim: "\(server.online)").font(.system(.largeTitle, weight: .semibold))
                        Text(verbatim: "/ \(server.max)").font(.subheadline).foregroundStyle(look.secondary)
                    }
                    .monospacedDigit()
                    Text("Players online").font(.caption).foregroundStyle(look.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Players: \(server.online) of \(server.max)"))
                Spacer(minLength: 8)
                Initials(names: server.players, look: look)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline) {
                if server.players.isEmpty {
                    Text(server.status == .online ? "Nobody is online." : "The server is not running.")
                } else {
                    Text(verbatim: server.players.formatted(.list(type: .and, width: .narrow))).privacySensitive()
                }
                Spacer(minLength: 8)
                Text(verbatim: Format.time(snapshot.updated))
            }
            .font(.caption2).foregroundStyle(look.secondary).lineLimit(1)
        }
        .foregroundStyle(look.primary)
    }
}

// MARK: - Large

/// 11 · The whole panel.
private struct PanelDashboard: View {
    let snapshot: WidgetSnapshot
    let look: Look

    private var online: [WidgetSnapshot.Server] { snapshot.servers.filter { $0.status == .online } }
    private var busiest: WidgetSnapshot.Server? { online.filter { $0.cpu != nil }.max { $0.online < $1.online } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                BrandMark(look: look)
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.panelName).font(.title3.weight(.bold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("As of \(Format.time(snapshot.updated))").font(.caption2).foregroundStyle(look.secondary)
                }
            }
            HStack(alignment: .top) {
                Figure(label: Text("Servers online"), value: "\(online.count) / \(snapshot.servers.count)", look: look)
                Figure(label: Text("Players"), value: "\(snapshot.servers.reduce(0) { $0 + $1.online })", look: look)
                if let busiest, let cpu = busiest.cpu {
                    Figure(label: Text("\(busiest.name) CPU"), value: Format.percent(cpu), look: look)
                }
            }
            Rectangle().fill(look.divider).frame(height: 1)
            ForEach(snapshot.servers.filter { $0.status != .crashed }.prefix(4)) { server in
                ServerRowLink(server: server) {
                    VStack(spacing: 6) {
                        HStack {
                            Text(server.name).lineLimit(1)
                            Spacer(minLength: 8)
                            if server.status == .online {
                                Text(verbatim: "\(server.online)/\(server.max)").fontWeight(.semibold).monospacedDigit()
                            } else {
                                Text(server.status.label).foregroundStyle(look.secondary)
                            }
                        }
                        .font(.footnote)
                        if server.status == .online {
                            Meter(value: Double(server.online), total: Double(max(server.max, 1)), look: look)
                        }
                    }
                }
            }
            ForEach(snapshot.servers.filter { $0.status == .crashed }.prefix(2)) { server in
                HStack {
                    Text("\(server.name) crashed").lineLimit(1)
                    Spacer(minLength: 8)
                    if let url = ServerLink.url(serverID: server.id, screen: .details) {
                        Link(destination: url) { Text(verbatim: "\(String(localized: "Logs")) ↗") }
                    }
                }
                .font(.footnote)
                .foregroundStyle(look.danger)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(look.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(look.primary)
    }
}

/// 12 · One server with shortcuts into the app.
private struct ServerFocus: View {
    let server: WidgetSnapshot.Server
    let snapshot: WidgetSnapshot
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BrandMark(look: look)
                Spacer()
                StatusLabel(status: server.status, look: look).font(.caption)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.title3.weight(.bold)).lineLimit(1)
                Text(verbatim: [snapshot.panelName, server.version].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(look.secondary).lineLimit(1)
            }
            HStack(alignment: .top) {
                Figure(label: Text(verbatim: "CPU"), value: server.cpu.map(Format.percent) ?? "–", look: look)
                Figure(label: Text(verbatim: "RAM"), value: server.memBytes.map(Format.gigabytes) ?? "–", look: look)
            }
            Sparkline(values: server.cpuTrend, color: look.accent).frame(height: 44)
            HStack {
                Text("Last hour")
                Spacer()
                Text("As of \(Format.time(snapshot.updated))")
            }
            .font(.caption2).foregroundStyle(look.secondary)
            Rectangle().fill(look.divider).frame(height: 1)
            HStack {
                Text(Format.players(server)).font(.footnote.weight(.semibold))
                Spacer(minLength: 8)
                Initials(names: server.players, look: look)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if let url = ServerLink.url(serverID: server.id, screen: .console) {
                    Link(destination: url) {
                        Label("Console", systemImage: "apple.terminal")
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(look.onAccent)
                            .background(look.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                if let url = ServerLink.url(serverID: server.id, screen: .details) {
                    Link(destination: url) {
                        Text(verbatim: "\(String(localized: "Details")) ↗")
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(look.accent)
                            .background(look.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .font(.footnote.weight(.medium))
        }
        .foregroundStyle(look.primary)
    }
}

// MARK: - Lock Screen

/// 14 · Servers online as a fraction.
private struct PanelFraction: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let online = snapshot.servers.filter { $0.status == .online }.count
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "server.rack").font(.caption2)
                Text(verbatim: "\(online)/\(snapshot.servers.count)").font(.headline).monospacedDigit()
                Text("online").font(.system(size: 9))
            }
            .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(online)/\(snapshot.servers.count) online"))
    }
}

/// 16 · One server in three lines.
private struct ServerGlance: View {
    let server: WidgetSnapshot.Server
    let updated: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(server.name).font(.headline).widgetAccentable().lineLimit(1)
            Text(verbatim: "\(String(localized: Format.players(server))) · \(server.status.label)").font(.subheadline).lineLimit(1)
            Text("As of \(Format.time(updated))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 17 · CPU trend and RAM.
private struct LoadTrace: View {
    let server: WidgetSnapshot.Server

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(server.name).font(.headline).widgetAccentable().lineLimit(1)
                Spacer(minLength: 4)
                if let cpu = server.cpu {
                    Text("CPU \(Format.percent(cpu))").font(.caption)
                } else {
                    Text(server.status.label).font(.caption)
                }
            }
            Sparkline(values: server.cpuTrend, color: .primary).frame(height: 14)
            if let mem = server.memBytes {
                Text("RAM \(Format.gigabytes(mem))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 19 · Above the clock: one server.
private struct ServerInline: View {
    let server: WidgetSnapshot.Server

    var body: some View {
        Label {
            Text(verbatim: server.status == .online ? "\(server.name) · \(server.online)/\(server.max)"
                                                    : "\(server.name) · \(server.status.label)")
        } icon: {
            Image(systemName: server.status == .crashed ? "exclamationmark.triangle" : "circle.fill")
        }
    }
}

/// 20 · Above the clock: the panel.
private struct PanelInline: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let online = snapshot.servers.filter { $0.status == .online }.count
        Label {
            Text("\(snapshot.panelName) · \(online)/\(snapshot.servers.count) online")
        } icon: {
            Image(systemName: "server.rack")
        }
    }
}

// MARK: - Parts

/// Colors of the snapshot's look. Online is green as in the mocks; trends, bars and buttons use the accent.
private struct Look {
    let mode: ThemeMode
    let accent: Color

    init(_ snapshot: WidgetSnapshot) {
        mode = snapshot.mode
        accent = snapshot.accent.color(for: snapshot.mode)
    }

    var primary: Color { Palette.primaryText(mode) }
    var secondary: Color { Palette.secondaryText(mode) }
    var divider: Color { Palette.divider(mode) }
    var track: Color { Palette.track(mode) }
    var danger: Color { Palette.danger(mode) }
    var online: Color { AccentPreset.green.color(for: mode) }
    var onAccent: Color { mode == .light ? .white : Palette.background(.dark) }

    func color(for status: ServerStatus) -> Color {
        status == .online ? online : Palette.color(for: status, mode: mode, accent: accent)
    }
}

private struct StatusLabel: View {
    let status: ServerStatus
    let look: Look

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(look.color(for: status)).frame(width: 6, height: 6)
            Text(status.label).lineLimit(1)
        }
        .foregroundStyle(look.color(for: status))
    }
}

private struct BrandMark: View {
    let look: Look

    var body: some View {
        Text(verbatim: "KURAFUTO  クラフト").font(.caption2.weight(.medium)).tracking(1.2)
            .foregroundStyle(look.secondary).lineLimit(1)
            .accessibilityHidden(true)
    }
}

private struct Figure: View {
    let label: Text
    let value: String
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            label.font(.caption2).foregroundStyle(look.secondary).lineLimit(1)
            Text(verbatim: value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct Metric: View {
    let label: Text
    let value: String
    let trend: [Double]
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            label.font(.caption2).foregroundStyle(look.secondary).lineLimit(1)
            Text(verbatim: value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Sparkline(values: trend, color: look.accent).frame(height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct Meter: View {
    let value: Double
    let total: Double
    let look: Look

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(look.track)
                Capsule().fill(look.accent).frame(width: max(geo.size.width * min(value / total, 1), 4))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// A line through the values, scaled to their own range; nothing until there are two.
private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if values.count > 1, let low = values.min(), let high = values.max() {
                let span = max(high - low, max(high * 0.05, 1e-9))
                Path { path in
                    for (i, v) in values.enumerated() {
                        let point = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1),
                                            y: geo.size.height * (1 - CGFloat((v - low) / span)))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Initials of up to four players, colored by name. Drawn locally; no skins are loaded.
private struct Initials: View {
    let names: [String]
    let look: Look
    private static let tints: [AccentPreset] = [.blue, .orange, .violet, .green, .pink, .cyan, .amber]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(names.prefix(4), id: \.self) { name in
                let tint = Self.tints[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.tints.count].color(for: look.mode)
                Text(verbatim: String(name.prefix(1)).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.16), in: Circle())
            }
        }
        .privacySensitive()
        .accessibilityHidden(true)
    }
}

/// Medium and large widgets can open each row on its own.
private struct ServerRowLink<Content: View>: View {
    let server: WidgetSnapshot.Server
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let url = ServerLink.url(serverID: server.id) {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }
}

private struct EmptyWidget: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "server.rack").font(.title3)
            }
            .accessibilityLabel(Text("Open Kurafuto to show your servers."))
        case .accessoryInline:
            Label { Text(verbatim: "Kurafuto") } icon: { Image(systemName: "server.rack") }
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

enum Format {
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    static func gigabytes(_ bytes: Double) -> String {
        let gb = bytes / 1_073_741_824
        return (gb >= 10 ? gb.rounded() : gb).formatted(.number.precision(.fractionLength(0...1))) + " GB"
    }

    /// The time of the values: today as a time, before that as a date. Fixed text, because the widget is only
    /// redrawn when the app writes new values.
    static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened)
                                             : date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Backup times are the panel host's wall clock, stored in UTC; shown unchanged like in the app.
    static func backupTime(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let wallClockNow = Date.now.addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT()))
        var style: Date.FormatStyle = utc.isDate(date, inSameDayAs: wallClockNow)
            ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated).hour().minute()
        style.timeZone = .gmt
        return date.formatted(style)
    }

    static func players(_ server: WidgetSnapshot.Server) -> LocalizedStringResource {
        "\(server.online)/\(server.max) players"
    }
}

#Preview("Server · small", as: .systemSmall) { ServerWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
    SnapshotEntry(date: .now, snapshot: nil)
}

#Preview("Server · medium", as: .systemMedium) { ServerWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
}

#Preview("Server · large", as: .systemLarge) { ServerWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
}

#Preview("Load", as: .systemSmall) { LoadWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
}

#Preview("Players", as: .systemMedium) { PlayersWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
}

#Preview("Backup", as: .systemSmall) { BackupWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
}

#Preview("Panel · medium", as: .systemMedium) { PanelWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview("Panel · large", as: .systemLarge) { PanelWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview("Lock", as: .accessoryRectangular) { ServerWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample, serverID: "sample-survival")
}
