import SwiftUI

/// Live console with command input, quick commands and history.
struct ConsoleView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var lines: [LogLine] = []
    @State private var input = ""
    @State private var history: [String] = []
    @State private var autoScroll = true
    @State private var filter = ""
    @FocusState private var focused: Bool

    private let quick = ["list", "save-all", "weather clear", "time set day", "say Hello!", "whitelist list"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(line.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .background(Theme.console)
                .onChange(of: lines.count) {
                    if autoScroll, let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(quick, id: \.self) { cmd in
                        Button(cmd) { Task { await send(cmd) } }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.horizontal).padding(.vertical, 6)
            }

            HStack {
                Text(">").monospaced().foregroundStyle(Theme.accent)
                TextField("Command without /", text: $input)
                    .monospaced().textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { Task { await send(input) } }
                Menu {
                    ForEach(history.reversed().prefix(10), id: \.self) { h in Button(h) { input = h } }
                } label: { Image(systemName: "clock.arrow.circlepath") }
                .disabled(history.isEmpty)
                Button { Task { await send(input) } } label: { Image(systemName: "paperplane.fill") }
                    .disabled(input.isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter, prompt: "Filter")
        .toolbar {
            Toggle(isOn: $autoScroll) { Image(systemName: "arrow.down.to.line") }
            ShareLink(item: lines.map(\.text).joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
        }
        .task {
            for await line in app.service.consoleStream(serverID: server.id) { lines.append(line) }
        }
    }

    private var visible: [LogLine] {
        filter.isEmpty ? lines : lines.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    private func color(_ l: LogLine.Level) -> Color {
        switch l {
        case .info: .white.opacity(0.85)
        case .warn: .yellow
        case .error: .red
        case .command: Theme.accent
        case .chat: .cyan
        }
    }

    private func send(_ cmd: String) async {
        let c = cmd.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        input = ""
        history.append(c)
        try? await app.service.sendCommand(c, serverID: server.id)
    }
}

/// Log file (latest.log) instead of stdout – with a problems-only filter.
struct LogsView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var state: Loadable<[String]> = .idle
    @State private var onlyProblems = false

    var body: some View {
        LoadableView(state: state, retry: load) { lines in
            List(lines.filter { !onlyProblems || $0.contains("WARN") || $0.contains("ERROR") }, id: \.self) {
                Text($0).font(.system(.caption2, design: .monospaced))
            }
            .listStyle(.plain)
        }
        .navigationTitle("Logs")
        .toolbar { Toggle("Warnings only", isOn: $onlyProblems) }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { state = .loaded(try await app.service.logs(serverID: server.id, fromFile: true)) }
        catch { state = .failed(error) }
    }
}

#Preview {
    NavigationStack { ConsoleView(server: MockData.servers[0]) }.environment(AppState.preview)
}
