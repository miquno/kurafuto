import SwiftUI

/// Mirrors the Crafty dashboard: all servers with status, players, CPU/RAM and quick actions.
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @State private var state: Loadable<[Server]> = .idle
    @State private var stats: [String: ServerStats] = [:]
    @State private var search = ""
    @State private var showCreate = false
    @State private var confirm: ConfirmAction?

    var body: some View {
        NavigationStack {
            LoadableView(state: state, retry: load) { servers in
                List {
                    if app.isMock {
                        Label("Demo mode – all data is sample data", systemImage: "theatermasks")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    summary(servers)
                    Section("Servers") {
                        ForEach(filtered(servers)) { server in
                            NavigationLink(value: server) {
                                ServerRow(server: server, stats: stats[server.id])
                            }
                            .swipeActions(edge: .leading) { quickActions(server) }
                            .contextMenu { contextMenu(server) }
                        }
                    }
                }
                .searchable(text: $search, prompt: "Search servers")
                .refreshable { await load() }
            }
            .navigationTitle(app.activeInstance?.name ?? "Servers")
            .navigationDestination(for: Server.self) { ServerDetailView(server: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Create server")
                }
            }
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

    private func summary(_ servers: [Server]) -> some View {
        let online = servers.filter { stats[$0.id]?.running == true }.count
        let players = stats.values.reduce(0) { $0 + $1.online }
        return Section {
            HStack(spacing: 12) {
                SummaryTile(value: "\(online)/\(servers.count)", label: "online", symbol: "power")
                SummaryTile(value: "\(players)", label: "players", symbol: "person.3.fill")
                SummaryTile(value: "\(stats.values.filter(\.crashed).count)", label: "crashed", symbol: "exclamationmark.triangle.fill")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private func quickActions(_ server: Server) -> some View {
        if stats[server.id]?.running == true {
            Button { Task { await run(.restart, server) } } label: { Label("Restart", systemImage: "arrow.clockwise") }.tint(.orange)
        } else {
            Button { Task { await run(.start, server) } } label: { Label("Start", systemImage: "play.fill") }.tint(.green)
        }
    }

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

struct SummaryTile: View {
    let value: String, label: String, symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

struct ServerRow: View {
    let server: Server
    let stats: ServerStats?

    var body: some View {
        HStack(spacing: 12) {
            ServerIcon(base64: stats?.icon, type: server.type)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.serverName).font(.headline)
                HStack(spacing: 8) {
                    if let s = stats { StatusBadge(status: s.status) }
                    Text(stats?.version ?? server.type.label).font(.caption).foregroundStyle(.secondary)
                }
                if let s = stats, s.running {
                    HStack(spacing: 12) {
                        Label("\(s.online)/\(s.max)", systemImage: "person.fill")
                        Label(String(format: "%.0f%%", s.cpu), systemImage: "cpu")
                        Label(s.mem, systemImage: "memorychip")
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ServerIcon: View {
    let base64: String?
    let type: ServerType
    var body: some View {
        Group {
            if let b = base64, let d = Data(base64Encoded: b), let img = UIImage(data: d) {
                Image(uiImage: img).resizable().interpolation(.none)
            } else {
                Image(systemName: type.symbol).font(.title2).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accent.opacity(0.12))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview { DashboardView().environment(AppState.preview) }
