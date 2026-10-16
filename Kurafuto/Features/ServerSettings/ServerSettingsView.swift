import SwiftUI

/// Server configuration from Crafty's "Config" tab: name, start and stop, crash detection, network, logs, delete.
/// Saves send only the changed fields (`ServerConfigPatch`). Start command, IP, port and the status page are
/// superuser-only on the panel, so other users see them read-only.
struct ServerSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Binding var server: Server
    @State private var draft: Server?
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var deleteFiles = false
    @State private var deleteText = ""
    @State private var actionError: Error?

    /// Unknown rights keep the fields editable; the panel enforces them and its error is shown.
    private var isSuperuser: Bool { app.access?.isSuperuser ?? true }

    private var changes: ServerConfigPatch? { draft.map { ServerConfigPatch(from: server, to: $0) } }

    var body: some View {
        Form {
            Group {
                if let binding = Binding($draft) {
                    sections(binding)
                }
            }
            .themedRows()
        }
        .themedBackground()
        .entrance()
        .navigationTitle("Configuration")
        .toolbar {
            Button(saving ? "…" : "Save") { Task { await save() } }
                .disabled(saving || changes?.isEmpty ?? true || draft.flatMap(ServerConfigPatch.problem(for:)) != nil)
        }
        .alert(deleteFiles ? "Delete server and files?" : "Remove server from panel?", isPresented: $confirmDelete) {
            TextField("Server name to confirm", text: $deleteText)
            Button(deleteFiles ? "Delete" : "Remove", role: .destructive) {
                guard deleteText == server.serverName else { return }
                Task {
                    guard await app.lock.authorize(String(localized: "Delete \(server.serverName)")) else { return }
                    if await $actionError.capture({ try await app.service.deleteServer(id: server.id, deleteFiles: deleteFiles) }) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteFiles
                 ? "The server folder with worlds and backups is deleted for good. Type “\(server.serverName)” to confirm."
                 : "The server folder stays on the panel's disk. Type “\(server.serverName)” to confirm.")
        }
        .errorAlert($actionError)
        .onAppear { if draft == nil { draft = server } }
    }

    @ViewBuilder
    private func sections(_ d: Binding<Server>) -> some View {
        Section("General") {
            TextField("Name", text: d.serverName)
            LabeledContent("Type", value: server.type.label)
            LabeledContent("Server ID") { Text(server.id).font(.mono(.caption2)).textSelection(.enabled) }
        }
        Section {
            if isSuperuser {
                TextField("Start command", text: Binding(d.executionCommand, replacingNilWith: ""), axis: .vertical)
                    .font(.mono(.footnote)).textInputAutocapitalization(.never).autocorrectionDisabled()
            } else if let command = server.executionCommand {
                LabeledContent("Start command") { Text(command).font(.mono(.caption2)).textSelection(.enabled) }
            }
            LabeledContent("Stop command") {
                TextField("Stop command", text: d.stopCommand)
                    .font(.mono(.footnote)).multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Toggle("Start automatically with panel", isOn: d.autoStart)
            Stepper("Start delay: \(d.wrappedValue.autoStartDelay) s", value: d.autoStartDelay, in: 0...600, step: 5)
            if let timeout = d.wrappedValue.shutdownTimeout {
                Stepper("Shutdown timeout: \(timeout) s",
                        value: Binding(get: { timeout }, set: { d.wrappedValue.shutdownTimeout = $0 }), in: 60...300, step: 10)
            }
        } header: {
            Text("Startup")
        } footer: {
            Text("The panel kills the server when it has not stopped within the shutdown timeout.")
        }
        Section {
            Toggle("Detect crashes & restart", isOn: d.crashDetection)
            if d.wrappedValue.ignoredExits != nil {
                LabeledContent("Ignored exit codes") {
                    TextField("0", text: Binding(d.ignoredExits, replacingNilWith: ""))
                        .font(.mono(.footnote)).multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                }
            }
        } header: {
            Text("Crash Detection")
        } footer: {
            Text("Exit codes that count as a normal stop, separated by commas.")
        }
        Section {
            if isSuperuser {
                LabeledContent("IP") {
                    TextField("127.0.0.1", text: d.serverIP)
                        .font(.mono(.footnote)).multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                LabeledContent("Port") {
                    TextField("25565", value: d.serverPort, format: .number.grouping(.never))
                        .font(.mono(.footnote)).multilineTextAlignment(.trailing).keyboardType(.numberPad)
                }
            } else {
                LabeledContent("Address") { Text(verbatim: "\(server.serverIP):\(server.serverPort)").font(.mono(.footnote)) }
            }
            if let count = d.wrappedValue.countPlayers {
                Toggle("Count players in panel total", isOn: Binding(get: { count }, set: { d.wrappedValue.countPlayers = $0 }))
            }
            if isSuperuser, let show = d.wrappedValue.showStatus {
                Toggle("Show on public status page", isOn: Binding(get: { show }, set: { d.wrappedValue.showStatus = $0 }))
            }
        } header: {
            Text("Network")
        } footer: {
            Text("IP and port are where the panel reads player counts and version; they do not change the server's own settings.")
        }
        Section("Logs") {
            Stepper(d.wrappedValue.logsDeleteAfter == 0 ? "Keep logs forever" : "Delete logs after \(d.wrappedValue.logsDeleteAfter) days",
                    value: d.logsDeleteAfter, in: 0...365)
        }
        if let problem = ServerConfigPatch.problem(for: d.wrappedValue) {
            Section { Text(problem).font(.footnote).foregroundStyle(Theme.warning) }
        }
        Section {
            Button("Remove from Panel", role: .destructive) { deleteFiles = false; deleteText = ""; confirmDelete = true }
            Button("Delete Server and Files", role: .destructive) { deleteFiles = true; deleteText = ""; confirmDelete = true }
        } footer: {
            Text("Both remove the server's schedules. Removing keeps its folder and backups on the panel's disk; deleting erases them.")
        }
    }

    private func save() async {
        guard let changes, !changes.isEmpty else { return }
        saving = true
        if await $actionError.capture({ try await app.service.updateServer(id: server.id, changes: changes) }) {
            server = changes.applied(to: server)
            draft = server
        }
        saving = false
    }
}

#Preview {
    NavigationStack { ServerSettingsView(server: .constant(MockData.servers[0])) }.environment(AppState.preview)
}
