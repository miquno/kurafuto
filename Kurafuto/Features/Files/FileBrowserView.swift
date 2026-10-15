import SwiftUI

/// File manager: browse folders, edit text files, create folders, delete.
/// Paths always come from the panel's own listing; new names are checked with `ServerPath.isValidName`.
struct FileBrowserView: View {
    @Environment(AppState.self) private var app
    let server: Server
    let path: String
    @State private var state: Loadable<[FileEntry]> = .idle
    @State private var newFolder = ""
    @State private var showNewFolder = false
    @State private var confirm: ConfirmAction?
    @State private var actionError: Error?

    var body: some View {
        LoadableView(state: state, retry: load) { entries in
            List(entries) { e in
                Group {
                    if e.isDirectory {
                        NavigationLink { FileBrowserView(server: server, path: e.path) } label: { row(e) }
                    } else if e.isEditableText {
                        NavigationLink { TextFileEditor(server: server, path: e.path) } label: { row(e) }
                    } else {
                        row(e)
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .entrance()
            .refreshable { await load() }
            .overlay { if entries.isEmpty { ContentUnavailableView("Empty Folder", systemImage: "folder") } }
        }
        .navigationTitle(path.isEmpty ? "Files" : (path as NSString).lastPathComponent)
        .destructiveConfirmation($confirm)
        .errorAlert($actionError)
        .toolbar {
            Button { newFolder = ""; showNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                .accessibilityLabel("New folder")
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolder)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Create") {
                let name = newFolder.trimmingCharacters(in: .whitespaces)
                Task {
                    await $actionError.capture { try await app.service.createFolder(serverID: server.id, parent: path, name: name) }
                    await load()
                }
            }
            .disabled(!ServerPath.isValidName(newFolder.trimmingCharacters(in: .whitespaces)))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A single name, without / or \\.")
        }
        .task { await load() }
    }

    private func row(_ e: FileEntry) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: e.isDirectory ? "folder.fill" : e.isEditableText ? "doc.text" : "doc",
                     color: e.isDirectory ? Theme.storage : Theme.secondaryText, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.mono(.subheadline))
                let details = [e.size, e.modified].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                confirm = ConfirmAction(title: e.isDirectory ? "Delete folder?" : "Delete file?",
                                        message: e.isDirectory ? "\(e.name) and everything in it will be deleted." : e.name,
                                        buttonLabel: "Delete") {
                    await $actionError.capture { try await app.service.deleteFile(serverID: server.id, path: e.path) }
                    await load()
                }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func load() async {
        do { state = .loaded(try await app.service.listFiles(serverID: server.id, path: path)) }
        catch { state = .failed(error) }
    }
}

/// Saves send the modification time the file was read with; when the file changed on the panel since,
/// the user chooses between overwriting it and reloading it.
private extension View {
    func fileChangedAlert(isPresented: Binding<Bool>, overwrite: @escaping () -> Void, reload: @escaping () -> Void) -> some View {
        alert("File Changed on the Panel", isPresented: isPresented) {
            Button("Overwrite", role: .destructive, action: overwrite)
            Button("Reload", action: reload)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Someone changed this file after you opened it. Overwrite their changes with yours, or reload and lose your edits?")
        }
    }
}

struct TextFileEditor: View {
    @Environment(AppState.self) private var app
    let server: Server
    let path: String
    @State private var state: Loadable<PanelFile> = .idle
    @State private var text = ""
    @State private var saving = false
    @State private var changedOnPanel = false
    @State private var actionError: Error?

    var body: some View {
        // Only a loaded file can be saved: an empty editor after a failed read must never overwrite it.
        LoadableView(state: state, retry: load) { _ in
            TextEditor(text: $text)
                .font(.mono(.footnote))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(.horizontal, 8)
        }
        .themedBackground()
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(saving ? "…" : "Save") { Task { await save() } }
                .disabled(saving || state.value == nil || text == state.value?.content)
        }
        .errorAlert($actionError)
        .fileChangedAlert(isPresented: $changedOnPanel, overwrite: { Task { await save(overwrite: true) } },
                          reload: { Task { await load() } })
        .task { await load() }
    }

    private func save(overwrite: Bool = false) async {
        guard let file = state.value else { return }
        saving = true
        do {
            let epoch = try await app.service.writeFile(serverID: server.id, path: path, content: text,
                                                        modifiedEpoch: file.modifiedEpoch, overwrite: overwrite)
            state = .loaded(PanelFile(content: text, modifiedEpoch: epoch))
        } catch CraftyError.fileChanged {
            changedOnPanel = true
        } catch {
            actionError = error
        }
        saving = false
    }

    private func load() async {
        do {
            let file = try await app.service.readFile(serverID: server.id, path: path)
            text = file.content
            state = .loaded(file)
        } catch { state = .failed(error) }
    }
}

/// Convenience editor for server.properties with toggles instead of raw text. Only values change;
/// comments and order stay as the server wrote them.
struct PropertiesEditorView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var state: Loadable<PanelFile> = .idle
    @State private var props = ServerProperties("")
    @State private var search = ""
    @State private var saving = false
    @State private var changedOnPanel = false
    @State private var actionError: Error?

    private static let path = "server.properties"

    var body: some View {
        LoadableView(state: state, retry: load) { _ in form }
            .navigationTitle("server.properties")
            .searchable(text: $search, prompt: "Find property")
            .toolbar {
                Button(saving ? "…" : "Save") { Task { await save() } }
                    .disabled(saving || state.value == nil || props == ServerProperties(state.value?.content ?? ""))
            }
            .errorAlert($actionError)
            .fileChangedAlert(isPresented: $changedOnPanel, overwrite: { Task { await save(overwrite: true) } },
                              reload: { Task { await load() } })
            .task { await load() }
    }

    private var form: some View {
        Form {
            Group {
                ForEach(props.entries.filter { search.isEmpty || $0.key.localizedCaseInsensitiveContains(search) }, id: \.key) { entry in
                    let key = entry.key
                    if entry.value == "true" || entry.value == "false" {
                        Toggle(isOn: Binding(get: { props[key] == "true" }, set: { props[key] = $0 ? "true" : "false" })) {
                            Text(key).font(.mono(.footnote))
                        }
                    } else {
                        LabeledContent {
                            TextField(key, text: Binding(get: { props[key] ?? "" }, set: { props[key] = $0 }))
                                .multilineTextAlignment(.trailing).font(.mono(.footnote))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        } label: {
                            Text(key).font(.mono(.footnote))
                        }
                    }
                }
                Section { Text("Changes take effect after a restart.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            }
            .themedRows()
        }
        .themedBackground()
        .entrance()
    }

    private func save(overwrite: Bool = false) async {
        guard let file = state.value else { return }
        saving = true
        do {
            let content = props.text
            let epoch = try await app.service.writeFile(serverID: server.id, path: Self.path, content: content,
                                                        modifiedEpoch: file.modifiedEpoch, overwrite: overwrite)
            state = .loaded(PanelFile(content: content, modifiedEpoch: epoch))
        } catch CraftyError.fileChanged {
            changedOnPanel = true
        } catch {
            actionError = error
        }
        saving = false
    }

    private func load() async {
        do {
            let file = try await app.service.readFile(serverID: server.id, path: Self.path)
            props = ServerProperties(file.content)
            state = .loaded(file)
        } catch { state = .failed(error) }
    }
}

#Preview("Files") {
    NavigationStack { FileBrowserView(server: MockData.servers[0], path: "") }.environment(AppState.preview)
}

#Preview("server.properties") {
    NavigationStack { PropertiesEditorView(server: MockData.servers[0]) }.environment(AppState.preview)
}
