import SwiftUI

/// Webhooks (Discord, Slack, Teams, Mattermost, custom) with triggers.
struct WebhooksView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var state: Loadable<[Webhook]> = .idle
    @State private var editing: Webhook?

    var body: some View {
        LoadableView(state: state, retry: load) { hooks in
            List {
                ForEach(hooks) { h in
                    Button { editing = h } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(h.name).font(.headline).foregroundStyle(.primary)
                                Spacer()
                                Text(h.webhookType.rawValue).font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            Text(h.triggers.map(\.label).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            if !h.enabled { Text("Disabled").font(.caption2).foregroundStyle(.orange) }
                        }
                    }
                }
                .onDelete { idx in
                    Task { for i in idx { try? await app.service.deleteWebhook(id: hooks[i].id, serverID: server.id) }; await load() }
                }
            }
            .overlay { if hooks.isEmpty { ContentUnavailableView("No Webhooks", systemImage: "bell.slash") } }
        }
        .navigationTitle("Webhooks")
        .toolbar {
            Button {
                editing = Webhook(id: 0, webhookType: .discord, name: "", url: "", botName: "Server Bot",
                                  triggers: [.serverStart, .serverStop], body: "", enabled: true)
            } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { h in
            WebhookEditor(webhook: h) { saved in
                Task { try? await app.service.saveWebhook(saved, serverID: server.id); await load() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { state = .loaded(try await app.service.webhooks(serverID: server.id)) } catch { state = .failed(error) }
    }
}

struct WebhookEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var webhook: Webhook
    let onSave: (Webhook) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $webhook.name)
                Picker("Service", selection: $webhook.webhookType) {
                    ForEach(WebhookType.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Webhook URL", text: $webhook.url).keyboardType(.URL).textInputAutocapitalization(.never)
                TextField("Bot name", text: $webhook.botName)
                Section("Triggers") {
                    ForEach(WebhookTrigger.allCases) { t in
                        Toggle(t.label, isOn: Binding(get: { webhook.triggers.contains(t) }, set: { on in
                            if on { webhook.triggers.append(t) } else { webhook.triggers.removeAll { $0 == t } }
                        }))
                    }
                }
                Section("Message") {
                    TextEditor(text: $webhook.body).frame(minHeight: 80)
                    Text("Placeholders: {server_name}, {event_type}, {user}").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Enabled", isOn: $webhook.enabled)
            }
            .navigationTitle(webhook.id == 0 ? "New Webhook" : webhook.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(webhook); dismiss() }.disabled(webhook.name.isEmpty || webhook.url.isEmpty)
                }
            }
        }
    }
}
