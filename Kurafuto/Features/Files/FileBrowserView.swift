import SwiftUI

/// File manager: browse folders, edit text files, create folders, delete.
/// Uploads (plugins/mods/worlds) later via `.fileImporter` + the panel's chunked upload.
struct FileBrowserView: View {
    @Environment(AppState.self) private var app
    let server: Server
    let path: String
    @State private var state: Loadable<[FileEntry]> = .idle
    @State private var newFolder = ""
    @State private var showNewFolder = false
    @State private var showImporter = false
    @State private var confirm: ConfirmAction?
    @State private var actionError: Error?

    var body: some View {
        LoadableView(state: state, retry: load) { entries in
            List(entries.sorted { ($0.isDirectory ? 0 : 1, $0.name) < ($1.isDirectory ? 0 : 1, $1.name) }) { e in
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
            .overlay { if entries.isEmpty { ContentUnavailableView("Empty Folder", systemImage: "folder") } }
        }
        .navigationTitle(path.isEmpty ? "Files" : (path as NSString).lastPathComponent)
        .destructiveConfirmation($confirm)
        .errorAlert($actionError)
        .toolbar {
            Menu {
                Button { showNewFolder = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                Button { showImporter = true } label: { Label("Upload", systemImage: "square.and.arrow.up") }
            } label: { Image(systemName: "plus") }
            .accessibilityLabel("Add")
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolder)
            Button("Create") {
                Task {
                    await $actionError.capture { try await app.service.createFolder(serverID: server.id, path: path + "/" + newFolder) }
                    await load()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { _ in
            // TODO: wire up the panel's upload endpoint
        }
        .task { await load() }
    }

    private func row(_ e: FileEntry) -> some View {
        HStack {
            IconTile(symbol: e.isDirectory ? "folder.fill" : e.isEditableText ? "doc.text" : "doc",
                     color: e.isDirectory ? Theme.storage : Theme.secondaryText, size: 30)
            Text(e.name).font(.mono(.subheadline))
            Spacer()
            if let s = e.size { Text(s.byteString).font(.mono(.caption2)).foregroundStyle(Theme.secondaryText) }
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

struct TextFileEditor: View {
    @Environment(AppState.self) private var app
    let server: Server
    let path: String
    @State private var state: Loadable<String> = .idle
    @State private var text = ""
    @State private var original = ""
    @State private var saving = false
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
            Button(saving ? "…" : "Save") {
                Task {
                    saving = true
                    if await $actionError.capture({ try await app.service.writeFile(serverID: server.id, path: path, content: text) }) {
                        original = text
                    }
                    saving = false
                }
            }.disabled(state.value == nil || text == original)
        }
        .errorAlert($actionError)
        .task { await load() }
    }

    private func load() async {
        do {
            let content = try await app.service.readFile(serverID: server.id, path: path)
            text = content; original = content
            state = .loaded(content)
        } catch { state = .failed(error) }
    }
}

/// Convenience editor for server.properties with toggles instead of raw text.
struct PropertiesEditorView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var state: Loadable<String> = .idle
    @State private var props: [(key: String, value: String)] = []
    @State private var dirty = false
    @State private var actionError: Error?

    var body: some View {
        LoadableView(state: state, retry: load) { _ in form }
        .navigationTitle("server.properties")
        .toolbar {
            Button("Save") {
                Task {
                    let out = "#Edited with Kurafuto\n" + props.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                    if await $actionError.capture({ try await app.service.writeFile(serverID: server.id, path: "server.properties", content: out) }) {
                        dirty = false
                    }
                }
            }.disabled(!dirty || state.value == nil)
        }
        .errorAlert($actionError)
        .task { await load() }
    }

    private var form: some View {
        Form {
            Group {
                ForEach(props.indices, id: \.self) { i in
                    let key = props[i].key
                    if props[i].value == "true" || props[i].value == "false" {
                        Toggle(isOn: Binding(get: { props[i].value == "true" },
                                             set: { props[i].value = $0 ? "true" : "false"; dirty = true })) {
                            Text(key).font(.mono(.footnote))
                        }
                    } else {
                        LabeledContent {
                            TextField(key, text: Binding(get: { props[i].value }, set: { props[i].value = $0; dirty = true }))
                                .multilineTextAlignment(.trailing).font(.mono(.footnote))
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

    private func load() async {
        do {
            let raw = try await app.service.readFile(serverID: server.id, path: "server.properties")
            props = raw.split(separator: "\n").compactMap { line in
                let l = line.trimmingCharacters(in: .whitespaces)
                guard !l.hasPrefix("#"), let eq = l.firstIndex(of: "=") else { return nil }
                return (String(l[..<eq]), String(l[l.index(after: eq)...]))
            }
            state = .loaded(raw)
        } catch { state = .failed(error) }
    }
}
