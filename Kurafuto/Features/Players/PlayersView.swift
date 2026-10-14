import SwiftUI

/// Player management. Crafty has no dedicated API endpoints for this –
/// everything goes through console commands (stdin) plus reading ops.json / whitelist.json / banned-players.json.
struct PlayersView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var online: [String] = []
    @State private var newName = ""
    @State private var toast: String?

    var body: some View {
        List {
            Section("Online (\(online.count))") {
                if online.isEmpty {
                    Text("Nobody online").foregroundStyle(.secondary)
                }
                ForEach(online, id: \.self) { name in
                    HStack {
                        PlayerInitialsAvatar(name: name)
                        Text(name)
                        Spacer()
                        Menu {
                            Button("Make Operator") { cmd("op \(name)") }
                            Button("Remove Operator") { cmd("deop \(name)") }
                            Button("Creative Mode") { cmd("gamemode creative \(name)") }
                            Button("Survival Mode") { cmd("gamemode survival \(name)") }
                            Button("Teleport to Me") { cmd("tp \(name) \(app.activeInstance?.username ?? "")") }
                            Divider()
                            Button("Kick", role: .destructive) { cmd("kick \(name)") }
                            Button("Ban", role: .destructive) { cmd("ban \(name)") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }

            Section {
                TextField("Player name", text: $newName).textInputAutocapitalization(.never)
                HStack {
                    Button("Whitelist +") { cmd("whitelist add \(newName)") }
                    Button("Whitelist −") { cmd("whitelist remove \(newName)") }
                    Button("Unban") { cmd("pardon \(newName)") }
                }
                .buttonStyle(.bordered)
                .disabled(newName.isEmpty)
            } header: { Text("Whitelist & Bans") } footer: {
                Text("Sent to your server as a console command.")
            }
        }
        .navigationTitle("Players")
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.footnote).padding(10).background(.thinMaterial, in: Capsule()).padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            while !Task.isCancelled {
                online = (try? await app.service.stats(serverID: server.id).players) ?? []
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func cmd(_ c: String) {
        Task {
            try? await app.service.sendCommand(c, serverID: server.id)
            withAnimation { toast = "Sent: \(c)" }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toast = nil }
        }
    }
}

/// Local placeholder avatar. Skin services are deliberately not used: they would send player names
/// and the user's IP address to a third party (see docs/decisions/0002-no-data-collection.md).
struct PlayerInitialsAvatar: View {
    let name: String
    var body: some View {
        Text(name.prefix(2).uppercased())
            .font(.caption.weight(.bold).monospaced())
            .foregroundStyle(Theme.accent)
            .frame(width: 32, height: 32)
            .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}
