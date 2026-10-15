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
    @State private var actionError: Error?

    var body: some View {
        List {
            Group {
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
                            await $actionError.capture { try await app.service.send(.backup, serverID: server.id) }
                            running = false
                            await loadFiles()
                        }
                    } label: {
                        HStack {
                            Label("Back Up Now", systemImage: "externaldrive.badge.plus").foregroundStyle(Theme.storage)
                            Spacer()
                            if running { ProgressView() }
                        }
                    }
                }

                Section("Archives") {
                    switch files {
                    case .loaded(let list):
                        ForEach(list) { f in
                            HStack(spacing: 12) {
                                IconTile(symbol: "archivebox.fill", color: Theme.storage, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.created, format: .dateTime.day().month().hour().minute()).font(.headline)
                                    Text("\(f.fileName) · \(f.size.byteString)").font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    confirm = ConfirmAction(title: "Delete backup?", message: f.fileName, buttonLabel: "Delete") {
                                        await $actionError.capture { try await app.service.deleteBackup(f, serverID: server.id) }
                                        await loadFiles()
                                    }
                                } label: { Label("Delete", systemImage: "trash") }
                                Button {
                                    confirm = ConfirmAction(title: "Restore backup?",
                                                            message: "The current world will be replaced by \(f.fileName). The server will be stopped for this.",
                                                            buttonLabel: "Restore") {
                                        await $actionError.capture { try await app.service.restoreBackup(f, serverID: server.id) }
                                    }
                                } label: { Label("Restore", systemImage: "clock.arrow.circlepath") }.tint(Theme.warning)
                            }
                        }
                    case .failed(let e): Text(e.panelProblem.message(for: e)).foregroundStyle(Theme.danger)
                    default: ProgressView()
                    }
                }
            }
            .themedRows()
        }
        .themedBackground()
        .entrance()
        .navigationTitle("Backups")
        .destructiveConfirmation($confirm)
        .errorAlert($actionError)
        .task {
            // Without configs the default one is tried; if the panel is unreachable, the archive list shows why.
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
