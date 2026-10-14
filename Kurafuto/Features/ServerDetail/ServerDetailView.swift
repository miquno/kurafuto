import SwiftUI
import Charts

/// Server detail page – mirrors the tabs in the Crafty panel:
/// Overview · Console · Logs · Schedules · Backups · Files · Players · Webhooks · Config
struct ServerDetailView: View {
    @Environment(AppState.self) private var app
    @State var server: Server
    @State private var stats: ServerStats?
    @State private var history: [StatPoint] = []
    @State private var busyAction: ServerAction?
    @State private var confirm: ConfirmAction?

    var body: some View {
        List {
            Section {
                header
                controls
            }
            if let s = stats, s.running { metrics(s) }

            Section("Manage") {
                nav("Console", "terminal.fill") { ConsoleView(server: server) }
                nav("Logs", "doc.text.magnifyingglass") { LogsView(server: server) }
                nav("Players", "person.3.fill", badge: stats?.online) { PlayersView(server: server) }
                nav("Schedules", "calendar.badge.clock") { SchedulesView(server: server) }
                nav("Backups", "externaldrive.fill") { BackupsView(server: server) }
                nav("Files", "folder.fill") { FileBrowserView(server: server, path: "") }
                nav("server.properties", "slider.horizontal.3") { PropertiesEditorView(server: server) }
                nav("Webhooks", "bell.badge.fill") { WebhooksView(server: server) }
                nav("Configuration", "gearshape.2.fill") { ServerSettingsView(server: $server) }
            }

            Section("Connection") {
                LabeledContent("Address") {
                    Text(verbatim: "\(app.activeInstance?.baseURL.host() ?? server.serverIP):\(server.serverPort)")
                        .textSelection(.enabled).monospaced()
                }
                if let world = stats?.worldName { LabeledContent("World", value: world) }
                if let size = stats?.worldSize { LabeledContent("World size", value: size) }
                if let started = stats?.started { LabeledContent("Started", value: started) }
            }
        }
        .navigationTitle(server.serverName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { Task { await run(.backup) } } label: { Label("Back Up Now", systemImage: ServerAction.backup.symbol) }
                Button { Task { await run(.updateExecutable) } } label: { Label("Update JAR", systemImage: ServerAction.updateExecutable.symbol) }
                Button { Task { await run(.clone) } } label: { Label("Clone", systemImage: ServerAction.clone.symbol) }
                Divider()
                Button(role: .destructive) {
                    confirm = ConfirmAction(title: "Kill process?", message: "Kill stops the server immediately without saving.",
                                            buttonLabel: "Kill") { await run(.kill) }
                } label: { Label("Kill", systemImage: ServerAction.kill.symbol) }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .confirmationDialog(confirm?.title ?? "", isPresented: .constant(confirm != nil), titleVisibility: .visible,
                            presenting: confirm) { c in
            Button(c.buttonLabel, role: .destructive) { Task { await c.perform(); confirm = nil } }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { Text($0.message) }
        .task { await poll() }
        .refreshable { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ServerIcon(base64: stats?.icon, type: server.type).scaleEffect(1.2).padding(4)
            VStack(alignment: .leading, spacing: 6) {
                if let s = stats { StatusBadge(status: s.status) }
                Text(stats?.desc?.strippingMinecraftFormatting ?? server.type.label)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            let running = stats?.running == true
            actionButton(.start, enabled: !running, color: .green)
            actionButton(.restart, enabled: running, color: .orange)
            actionButton(.stop, enabled: running, color: .red)
        }
        .buttonStyle(.borderless)
    }

    private func actionButton(_ a: ServerAction, enabled: Bool, color: Color) -> some View {
        Button {
            if a == .stop {
                confirm = ConfirmAction(title: "Stop server?", message: "\(stats?.online ?? 0) players will be disconnected.",
                                        buttonLabel: "Stop") { await run(a) }
            } else { Task { await run(a) } }
        } label: {
            VStack(spacing: 4) {
                if busyAction == a { ProgressView() } else { Image(systemName: a.symbol).font(.title3) }
                Text(a.label).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(color.opacity(enabled ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(enabled ? color : .secondary)
        }
        .disabled(!enabled || busyAction != nil)
    }

    private func metrics(_ s: ServerStats) -> some View {
        Section("Live") {
            HStack(spacing: 10) {
                MetricCard(title: "CPU", value: s.cpu, caption: String(format: "%.1f%%", s.cpu))
                MetricCard(title: "RAM", value: s.memPercent, caption: s.mem)
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if history.count > 2 {
                Chart(history) { p in
                    LineMark(x: .value("Time", p.date), y: .value("CPU", p.cpu)).foregroundStyle(by: .value("Metric", "CPU"))
                    LineMark(x: .value("Time", p.date), y: .value("RAM", p.mem)).foregroundStyle(by: .value("Metric", "RAM"))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 140)
            }
        }
    }

    private func nav<D: View>(_ title: String, _ symbol: String, badge: Int? = nil,
                              @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            Label(title, systemImage: symbol)
                .badge(badge ?? 0)
        }
    }

    private func refresh() async {
        guard let s = try? await app.service.stats(serverID: server.id) else { return }
        stats = s
        history.append(StatPoint(date: .now, cpu: s.cpu, mem: s.memPercent))
        if history.count > 60 { history.removeFirst() }
    }

    private func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(stats?.status == .starting ? 1 : 3))
        }
    }

    private func run(_ action: ServerAction) async {
        busyAction = action
        defer { busyAction = nil }
        do {
            try await app.service.send(action, serverID: server.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        await refresh()
    }
}

struct StatPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let mem: Double
}

extension String {
    /// Strips Minecraft formatting codes (§a, §l, …) from MOTDs.
    /// Important: NEVER render MOTDs as HTML (known stored-XSS issue in the web panel, issue #647).
    var strippingMinecraftFormatting: String {
        replacingOccurrences(of: "§[0-9a-fk-or]", with: "", options: .regularExpression)
    }
}

#Preview {
    NavigationStack { ServerDetailView(server: MockData.servers[0]) }.environment(AppState.preview)
}
