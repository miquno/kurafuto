import SwiftUI

/// User & role management (superusers only, or users with USER_CONFIG/ROLES_CONFIG permission).
struct AdminView: View {
    @Environment(AppState.self) private var app
    @State private var users: Loadable<[CraftyUser]> = .idle
    @State private var roles: [Role] = []
    @State private var servers: [Server] = []
    @State private var editUser: CraftyUser?
    @State private var editRole: Role?

    var body: some View {
        NavigationStack {
            LoadableView(state: users, retry: load) { list in
                List {
                    Group {
                        if app.canManageUsers {
                            Section("Users") {
                                ForEach(list) { u in
                                    Button { editUser = u } label: {
                                        HStack {
                                            IconTile(symbol: u.superuser ? "crown.fill" : "person.fill",
                                                     color: u.superuser ? Theme.warning : Theme.accent, size: 32)
                                            VStack(alignment: .leading) {
                                                Text(u.username).foregroundStyle(u.enabled ? .primary : Theme.secondaryText)
                                                Text(roleNames(u)).font(.caption).foregroundStyle(Theme.secondaryText)
                                            }
                                            Spacer()
                                            if !u.enabled { Text("DISABLED").font(.mono(.caption2, weight: .semibold)).foregroundStyle(Theme.warning) }
                                        }
                                    }
                                }
                            }
                        }
                        if app.canManageRoles {
                            Section("Roles") {
                                ForEach(roles) { r in
                                    Button { editRole = r } label: {
                                        HStack {
                                            Text(r.roleName).foregroundStyle(.primary)
                                            Spacer()
                                            if r.mfaRequired { Image(systemName: "lock.shield").foregroundStyle(Theme.secondaryText) }
                                            Text("\(r.servers.count) servers").font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .themedRows()
                }
                .themedBackground()
                .entrance()
                .refreshable { await load() }
            }
            .navigationTitle("Admin")
            .toolbar {
                if app.canAddUsers || app.canAddRoles {
                    Menu {
                        if app.canAddUsers {
                            Button("New User") {
                                editUser = CraftyUser(userID: 0, username: "", enabled: true, superuser: false, lang: "en_EN", roleIDs: [])
                            }
                        }
                        if app.canAddRoles {
                            Button("New Role") {
                                editRole = Role(roleID: 0, roleName: "", manager: nil, mfaRequired: false, servers: [])
                            }
                        }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add user or role")
                }
            }
            .sheet(item: $editUser) { u in
                UserEditor(user: u, roles: roles) { saved, pw in
                    Task { try? await app.service.saveUser(saved, password: pw); await load() }
                }
            }
            .sheet(item: $editRole) { r in
                RoleEditor(role: r, servers: servers) { saved in
                    Task { try? await app.service.saveRole(saved); await load() }
                }
            }
            // Reload once the rights are known: a user without ROLES_CONFIG must not request roles.
            .task(id: app.access) { await load() }
        }
    }

    private func roleNames(_ u: CraftyUser) -> String {
        if u.superuser { return "Superuser" }
        let n = roles.filter { u.roleIDs.contains($0.roleID) }.map(\.roleName)
        return n.isEmpty ? "No role" : n.joined(separator: ", ")
    }

    private func load() async {
        let service = app.service
        let (loadUsers, loadRoles) = (app.canManageUsers, app.canManageRoles)
        do {
            async let u = loadUsers ? service.users() : []
            async let r = loadRoles ? service.roles() : []
            async let s = service.servers()
            users = .loaded(try await u)
            roles = try await r
            servers = try await s
        } catch CraftyError.forbidden {
            users = .failed(CraftyError.forbidden("User management (superusers only)"))
        } catch { users = .failed(error) }
    }
}

struct UserEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var user: CraftyUser
    let roles: [Role]
    let onSave: (CraftyUser, String?) -> Void
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    TextField("Username", text: $user.username).textInputAutocapitalization(.never)
                    SecureField(user.userID == 0 ? "Password" : "New password (optional)", text: $password)
                    Toggle("Enabled", isOn: $user.enabled)
                    Toggle("Superuser", isOn: $user.superuser)
                    Picker("Language", selection: $user.lang) {
                        Text("English").tag("en_EN"); Text("Deutsch").tag("de_DE")
                    }
                    if !user.superuser {
                        Section("Roles") {
                            ForEach(roles) { r in
                                Toggle(r.roleName, isOn: Binding(get: { user.roleIDs.contains(r.roleID) }, set: { on in
                                    if on { user.roleIDs.append(r.roleID) } else { user.roleIDs.removeAll { $0 == r.roleID } }
                                }))
                            }
                        }
                    }
                    if let last = user.lastLogin {
                        Section("Activity") {
                            LabeledContent("Last login", value: last)
                            if let ip = user.lastIP { LabeledContent("IP", value: ip) }
                        }
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle(user.userID == 0 ? "New User" : user.username)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(user, password.isEmpty ? nil : password); dismiss() }
                        .disabled(user.username.isEmpty || (user.userID == 0 && password.count < 8))
                }
            }
        }
    }
}

/// Role editor with a permission matrix (server × permission).
struct RoleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var role: Role
    let servers: [Server]
    let onSave: (Role) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    TextField("Role name", text: $role.roleName)
                    Toggle("Require 2FA for members", isOn: $role.mfaRequired)
                    ForEach(servers) { s in
                        Section(s.serverName) {
                            let idx = index(for: s)
                            Toggle("Access", isOn: Binding(get: { idx != nil }, set: { on in
                                if on { role.servers.append(RoleServerPermission(serverID: s.id, permissions: "00100000")) }
                                else { role.servers.removeAll { $0.serverID == s.id } }
                            }))
                            if let i = idx {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading) {
                                    ForEach(ServerPermission.allCases) { p in
                                        Toggle(p.label, isOn: Binding(get: { role.servers[i].has(p) },
                                                                      set: { role.servers[i].set(p, $0) }))
                                            .toggleStyle(.button).controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle(role.roleID == 0 ? "New Role" : role.roleName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(role); dismiss() }.disabled(role.roleName.isEmpty)
                }
            }
        }
    }

    private func index(for s: Server) -> Int? { role.servers.firstIndex { $0.serverID == s.id } }
}

#Preview { AdminView().environment(AppState.preview) }
