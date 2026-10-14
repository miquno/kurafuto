import SwiftUI

/// Backup manager: multiple backup configs, list of archives, restore/delete, back up now.
struct BackupsView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var configs: [BackupConfig] = []
    @State private var selected: String = "default"
    @State private var files: Loadable<[BackupFile]> = .idle
    @State private var confirm: ConfirmAction?
    @State private var running = false

    var body: some View {
        List {
            if configs.count > 1 {
                Picker("Configuration", selection: $selected) {
                    ForEach(configs) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if let c = configs.first(where: { $0.id == selected }) {
                Section("Settings") {
                    LabeledContent("Destination", value: c.backupLocation).font(.caption)
                    LabeledContent("Max backups", value: "\(c.maxBackups)")
                    LabeledContent("Compressed", value: c.compress ? "Yes" : "No")
                    LabeledContent("Stop server", value: c.shutdown ? "Yes" : "No")
                    if !c.excludedPaths.isEmpty {
                        LabeledContent("Excluded", value: c.excludedPaths.joined(separator: ", "))
                    }
                }
            }

            Section {
                Button {
                    Task {
                        running = true
                        try? await app.service.send(.backup, serverID: server.id)
                        running = false
                        await loadFiles()
                    }
                } label: {
                    HStack { Label("Back Up Now", systemImage: "externaldrive.badge.plus"); Spacer(); if running { ProgressView() } }
                }
            }

            Section("Archives") {
                switch files {
                case .loaded(let list):
                    ForEach(list) { f in
                        VStack(alignment: .leading) {
                            Text(f.created, format: .dateTime.day().month().hour().minute()).font(.headline)
                            Text("\(f.fileName) · \(f.size.byteString)").font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                confirm = ConfirmAction(title: "Delete backup?", message: f.fileName, buttonLabel: "Delete") {
                                    try? await app.service.deleteBackup(f, serverID: server.id); await loadFiles()
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                            Button {
                                confirm = ConfirmAction(title: "Restore backup?",
                                                        message: "The current world will be replaced by \(f.fileName). The server will be stopped for this.",
                                                        buttonLabel: "Restore") {
                                    try? await app.service.restoreBackup(f, serverID: server.id)
                                }
                            } label: { Label("Restore", systemImage: "clock.arrow.circlepath") }.tint(.orange)
                        }
                    }
                case .failed(let e): Text(e.localizedDescription).foregroundStyle(.red)
                default: ProgressView()
                }
            }
        }
        .navigationTitle("Backups")
        .confirmationDialog(confirm?.title ?? "", isPresented: .constant(confirm != nil), titleVisibility: .visible,
                            presenting: confirm) { c in
            Button(c.buttonLabel, role: .destructive) { Task { await c.perform(); confirm = nil } }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { Text($0.message) }
        .task {
            configs = (try? await app.service.backupConfigs(serverID: server.id)) ?? []
            selected = configs.first?.id ?? "default"
            await loadFiles()
        }
        .onChange(of: selected) { Task { await loadFiles() } }
    }

    private func loadFiles() async {
        do { files = .loaded(try await app.service.backupFiles(serverID: server.id, configID: selected)) }
        catch { files = .failed(error) }
    }
}
