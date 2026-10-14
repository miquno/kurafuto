import SwiftUI

/// Server configuration from Crafty's "Config" tab: name, start command, autostart, crash detection, logs, delete.
struct ServerSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Binding var server: Server
    @State private var draft: Server?
    @State private var confirmDelete = false
    @State private var deleteText = ""

    var body: some View {
        Form {
            Group {
                if let binding = Binding($draft) {
                    Section("General") {
                        TextField("Name", text: binding.serverName)
                        LabeledContent("Type", value: server.type.label)
                        LabeledContent("Server ID") { Text(server.id).font(.mono(.caption2)).textSelection(.enabled) }
                    }
                    Section("Startup") {
                        TextField("Start command", text: Binding(binding.executionCommand, replacingNilWith: ""), axis: .vertical)
                            .monospaced().font(.footnote)
                        TextField("Stop command", text: binding.stopCommand).monospaced()
                        Toggle("Start automatically with panel", isOn: binding.autoStart)
                        Stepper("Start delay: \(binding.wrappedValue.autoStartDelay) s",
                                value: binding.autoStartDelay, in: 0...600, step: 5)
                        Toggle("Detect crashes & restart", isOn: binding.crashDetection)
                    }
                    Section("Network") {
                        TextField("IP", text: binding.serverIP).monospaced()
                        TextField("Port", value: binding.serverPort, format: .number.grouping(.never)).keyboardType(.numberPad)
                    }
                    Section("Logs") {
                        Stepper("Delete logs after \(binding.wrappedValue.logsDeleteAfter) days (0 = never)",
                                value: binding.logsDeleteAfter, in: 0...365)
                    }
                    Section {
                        Button("Delete Server", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Permanently deletes the server, its files and schedules.")
                    }
                }
            }
            .themedRows()
        }
        .themedBackground()
        .entrance()
        .navigationTitle("Configuration")
        .toolbar {
            Button("Save") {
                guard let d = draft else { return }
                Task { try? await app.service.updateServer(d); server = d }
            }.disabled(draft == server)
        }
        .alert("Permanently delete server?", isPresented: $confirmDelete) {
            TextField("Server name to confirm", text: $deleteText)
            Button("Delete", role: .destructive) {
                guard deleteText == server.serverName else { return }
                Task { try? await app.service.deleteServer(id: server.id); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Type “\(server.serverName)” to confirm.") }
        .onAppear { draft = server }
    }
}
