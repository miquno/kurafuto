import SwiftUI

/// Mirrors the Crafty dashboard: all servers with status, players, CPU/RAM and quick actions.
/// Layout: the busiest running server as a featured card with gauges, the rest as a compact list,
/// and the featured server's latest console lines.
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @State private var state: Loadable<[Server]> = .idle
    @State private var stats: [String: ServerStats] = [:]
    @State private var consoleTail: [String] = []
    @State private var search = ""
    @State private var showCreate = false
    @State private var confirm: ConfirmAction?

    var body: some View {
        NavigationStack {
            LoadableView(state: state, retry: load) { servers in
                ScrollView {
                    VStack(spacing: 16) {
                        header(servers).entrance(0)
                        if servers.count > 3 { searchField.entrance(1) }
                        content(servers)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await load() }
            }
            .themedBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle(app.activeInstance?.name ?? "Servers")
            .navigationDestination(for: Server.self) { ServerDetailView(server: $0) }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) { CreateServerView() }
            .confirmationDialog(confirm?.title ?? "", isPresented: .constant(confirm != nil), titleVisibility: .visible,
                                presenting: confirm) { c in
                Button(c.buttonLabel, role: .destructive) { Task { await c.perform(); confirm = nil } }
                Button("Cancel", role: .cancel) { confirm = nil }
            } message: { Text($0.message) }
            .task { await load() }
            .task { await pollStats() }
        }
    }

    // MARK: Sections

    private func header(_ servers: [Server]) -> some View {
        let online = servers.filter { stats[$0.id]?.running == true }.count
        let players = stats.values.reduce(0) { $0 + $1.online }
        let crashed = stats.values.filter(\.crashed).count
        return HStack(spacing: 12) {
            IconTile(symbol: "server.rack", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.activeInstance?.name ?? "Servers")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                (Text("\(online)/\(servers.count) online · \(players) players")
                    + Text(crashed > 0 ? " · \(crashed) crashed" : "").foregroundStyle(Theme.danger))
                    .font(.mono(.caption))
                    .foregroundStyle(Theme.secondaryText)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: online + players + crashed)
            }
            Spacer(minLength: 8)
            if app.isMock {
                Text("DEMO")
                    .font(.mono(.caption2, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Theme.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Theme.warning)
                    .accessibilityLabel("Demo mode, all data is sample data")
            }
            Button { showCreate = true } label: {
                Image(systemName: "plus").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create server")
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField("Search servers", text: $search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }

    @ViewBuilder private func content(_ servers: [Server]) -> some View {
        let visible = filtered(servers)
        if servers.isEmpty {
            ContentUnavailableView {
                Label("No Servers", systemImage: "server.rack")
            } description: {
                Text("Create your first server on this panel.")
            } actions: {
                Button("Create Server") { showCreate = true }
                    .buttonStyle(InstrumentButtonStyle()).frame(width: 180)
            }
            .entrance(1)
        } else if visible.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            let hero = featured(visible)
            FeaturedServerCard(server: hero, stats: stats[hero.id])
                .contextMenu { contextMenu(hero) }
                .entrance(2)

            let rest = visible.filter { $0.id != hero.id }
            if !rest.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { index, server in
                        NavigationLink(value: server) {
                            ServerRow(server: server, stats: stats[server.id])
                        }
                        .buttonStyle(.plain)
                        .contextMenu { contextMenu(server) }
                        .overlay(alignment: .top) {
                            if index > 0 { Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 44) }
                        }
                        .entrance(3 + index)
                    }
                }
                .card(padding: 0)
            }

            if !consoleTail.isEmpty, stats[hero.id]?.running == true {
                NavigationLink { ConsoleView(server: hero) } label: {
                    ConsoleTail(serverName: hero.serverName, lines: consoleTail)
                }
                .buttonStyle(.plain)
                .entrance(3 + rest.count)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder private func contextMenu(_ server: Server) -> some View {
        ForEach([ServerAction.start, .restart, .stop, .backup, .kill], id: \.self) { action in
            Button(role: action.isDestructive ? .destructive : nil) {
                if action.isDestructive {
                    confirm = ConfirmAction(title: "\(action.label) \(server.serverName)?",
                                            message: "Connected players will be disconnected.",
                                            buttonLabel: action.label) { await run(action, server) }
                } else { Task { await run(action, server) } }
            } label: { Label(action.label, systemImage: action.symbol) }
        }
    }

    /// The running server with the most players; otherwise the first one.
    private func featured(_ servers: [Server]) -> Server {
        let running = servers.filter { stats[$0.id]?.running == true }
        return running.max { (stats[$0.id]?.online ?? 0) < (stats[$1.id]?.online ?? 0) } ?? servers[0]
    }

    private func filtered(_ s: [Server]) -> [Server] {
        search.isEmpty ? s : s.filter { $0.serverName.localizedCaseInsensitiveContains(search) }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let servers = try await app.service.servers()
            state = .loaded(servers)
            await refreshStats(servers)
        } catch { state = .failed(error) }
    }

    private func refreshStats(_ servers: [Server]) async {
        let service = app.service
        await withTaskGroup(of: (String, ServerStats?).self) { group in
            for s in servers { group.addTask { (s.id, try? await service.stats(serverID: s.id)) } }
            for await (id, st) in group { if let st { stats[id] = st } }
        }
        await refreshConsoleTail(servers)
    }

    private func refreshConsoleTail(_ servers: [Server]) async {
        guard !servers.isEmpty else { return }
        let hero = featured(servers)
        guard stats[hero.id]?.running == true,
              let lines = try? await app.service.logs(serverID: hero.id, fromFile: false) else { return }
        withAnimation(.snappy) { consoleTail = Array(lines.suffix(3)) }
    }

    private func pollStats() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if let servers = state.value { await refreshStats(servers) }
        }
    }

    private func run(_ action: ServerAction, _ server: Server) async {
        try? await app.service.send(action, serverID: server.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await refreshStats([server])
    }
}

/// The dashboard's large card: status, players and CPU/RAM/world gauges of one server.
struct FeaturedServerCard: View {
    let server: Server
    let stats: ServerStats?

    var body: some View {
        NavigationLink(value: server) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            StatusDot(status: status, size: 6)
                            Text(statusLine).font(.mono(.caption2, weight: .semibold))
                        }
                        .foregroundStyle(Theme.color(for: status))
                        Text(server.serverName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(stats?.version ?? server.type.label) · :\(String(server.serverPort))")
                            .font(.mono(.caption))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    PlayerCount(online: stats?.online ?? 0, max: stats?.max ?? 0, large: true)
                }
                HStack(spacing: 10) {
                    GaugeTile(title: "CPU", value: stats?.cpu ?? 0, color: Theme.cpu, delay: 0.25)
                    GaugeTile(title: "RAM", value: stats?.memPercent ?? 0, color: Theme.ram,
                              caption: stats?.running == true ? stats?.mem : nil, delay: 0.35)
                    ValueTile(title: "World", value: stats?.worldSize ?? "–", color: Theme.storage)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 18)
        }
        .buttonStyle(.plain)
    }

    private var status: ServerStatus { stats?.status ?? .offline }

    private var statusLine: String {
        guard status == .online, let since = stats?.started.flatMap(ServerStats.startTime) else {
            return status.label.uppercased()
        }
        return "ONLINE · SINCE \(since.formatted(date: .omitted, time: .shortened))"
    }
}

struct PlayerCount: View {
    let online: Int
    let max: Int
    var large = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(online)")
                .font(.mono(large ? .title : .subheadline, weight: .semibold))
                .contentTransition(.numericText(value: Double(online)))
                .animation(.snappy, value: online)
            Text("/\(max)")
                .font(.mono(large ? .subheadline : .caption))
                .foregroundStyle(Theme.secondaryText)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(online) of \(max) players")
    }
}

struct ServerRow: View {
    let server: Server
    let stats: ServerStats?

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: stats?.status ?? .offline)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.serverName).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(meta)
                    .font(.mono(.caption2))
                    .foregroundStyle(stats?.status == .crashed ? Theme.danger : Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let s = stats { PlayerCount(online: s.online, max: s.max) }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue((stats?.status ?? .offline).label)
    }

    /// Online servers show live values; the status word is carried by the dot and the accessibility value.
    private var meta: String {
        let version = stats?.version ?? server.type.label
        guard let s = stats else { return version }
        switch s.status {
        case .online: return "\(version) · cpu \(Int(s.cpu.rounded()))% · \(s.mem)"
        case .offline: return "stopped · \(version)"
        case .starting: return "starting · \(version)"
        case .updating: return "updating · \(version)"
        case .crashed: return "crashed · \(version)"
        }
    }
}

/// The featured server's latest console lines, linking to the full console.
struct ConsoleTail: View {
    let serverName: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(serverName) · console").foregroundStyle(Theme.secondaryText)
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .foregroundStyle(Theme.consoleText)
                    .lineLimit(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .font(.mono(.caption2))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.console, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the console")
    }
}

struct ServerIcon: View {
    let base64: String?
    let type: ServerType
    var body: some View {
        if let b = base64, let d = Data(base64Encoded: b), let img = UIImage(data: d) {
            Image(uiImage: img).resizable().interpolation(.none)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        } else {
            IconTile(symbol: type.symbol, size: 44)
        }
    }
}

extension ServerStats {
    /// Crafty reports `started` as "yyyy-MM-dd HH:mm:ss" in the panel's local time.
    static func startTime(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: raw)
    }
}

#Preview { DashboardView().environment(AppState.preview) }
