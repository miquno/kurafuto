import SwiftUI

/// User & role management (superusers only, or users with USER_CONFIG/ROLES_CONFIG permission).
struct AdminView: View {
    @Environment(AppState.self) private var app
    @State private var users: Loadable<[CraftyUser]> = .idle
    @State private var roles: [Role] = []
    @State private var servers: [Server] = []
    @State private var editUser: CraftyUser?
    @State private var editRole: Role?
    @State private var confirm: ConfirmAction?
    @State private var actionError: Error?

    private var myID: Int? { app.access?.userID }

    var body: some View {
        NavigationStack {
            LoadableView(state: users, retry: load) { list in
                List {
                    Group {
                        if app.canManageUsers {
                            Section("Users") {
                                ForEach(list) { u in
                                    Button { editUser = u } label: { userRow(u) }
                                        .swipeActions {
                                            if u.userID != myID {
                                                Button(role: .destructive) { confirmDelete(u) } label: { Label("Delete", systemImage: "trash") }
                                            }
                                        }
                                }
                            }
                        }
                        if app.canManageRoles {
                            Section("Roles") {
                                ForEach(roles) { r in
                                    Button { editRole = r } label: { roleRow(r) }
                                        .swipeActions {
                                            Button(role: .destructive) { confirmDelete(r) } label: { Label("Delete", systemImage: "trash") }
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
                            Button { editUser = .new() } label: { Label("New User", systemImage: "person.badge.plus") }
                        }
                        if app.canAddRoles {
                            Button { editRole = .new() } label: { Label("New Role", systemImage: "person.2.badge.gearshape") }
                        }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add user or role")
                }
            }
            .sheet(item: $editUser) { u in
                UserEditor(user: u, roles: roles, canGrantSuperuser: app.access?.isSuperuser ?? true,
                           isSelf: u.userID != 0 && u.userID == myID) { changes in
                    Task {
                        await $actionError.capture { try await app.service.saveUser(id: u.userID, changes: changes) }
                        await load()
                    }
                }
            }
            .sheet(item: $editRole) { r in
                RoleEditor(role: r, servers: servers) { saved in
                    Task {
                        await $actionError.capture { try await app.service.saveRole(saved) }
                        await load()
                    }
                }
            }
            .destructiveConfirmation($confirm)
            .errorAlert($actionError)
            // Reload once the rights are known: a user without ROLES_CONFIG must not request roles.
            .task(id: app.access) { await load() }
        }
    }

    private func userRow(_ u: CraftyUser) -> some View {
        HStack {
            IconTile(symbol: u.superuser ? "crown.fill" : "person.fill",
                     color: u.superuser ? Theme.warning : Theme.accent, size: 32)
            VStack(alignment: .leading) {
                Text(u.userID == myID ? String(localized: "\(u.username) (you)") : u.username)
                    .foregroundStyle(u.enabled ? .primary : Theme.secondaryText)
                Text(roleNames(u)).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if !u.enabled { Text("DISABLED").font(.mono(.caption2, weight: .semibold)).foregroundStyle(Theme.warning) }
        }
        .accessibilityElement(children: .combine)
    }

    private func roleRow(_ r: Role) -> some View {
        HStack {
            Text(r.roleName).foregroundStyle(.primary)
            Spacer()
            if r.mfaRequired {
                Image(systemName: "lock.shield").foregroundStyle(Theme.secondaryText).accessibilityLabel("Requires 2FA")
            }
            if let servers = r.servers {
                Text("\(servers.count) servers").font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func roleNames(_ u: CraftyUser) -> String {
        if u.superuser { return String(localized: "Superuser") }
        let known = roles.filter { u.roleIDs.contains($0.roleID) }.map(\.roleName)
        if !known.isEmpty { return known.joined(separator: ", ") }
        return u.roleIDs.isEmpty ? String(localized: "No role") : String(localized: "\(u.roleIDs.count) roles")
    }

    private func confirmDelete(_ u: CraftyUser) {
        confirm = ConfirmAction(title: String(localized: "Delete user?"),
                                message: String(localized: "\(u.username) can no longer sign in to the panel."),
                                buttonLabel: String(localized: "Delete")) {
            await $actionError.capture { try await app.service.deleteUser(id: u.userID) }
            await load()
        }
    }

    private func confirmDelete(_ r: Role) {
        confirm = ConfirmAction(title: String(localized: "Delete role?"),
                                message: String(localized: "Members of \(r.roleName) lose the server rights it gives."),
                                buttonLabel: String(localized: "Delete")) {
            await $actionError.capture { try await app.service.deleteRole(id: r.roleID) }
            await load()
        }
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
            users = .failed(CraftyError.forbidden(String(localized: "User management (superusers only)")))
        } catch { users = .failed(error) }
    }
}

struct UserEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: CraftyUser
    let roles: [Role]
    let canGrantSuperuser: Bool
    /// The panel refuses disabling oneself and, for non-superusers, changing one's own roles.
    let isSelf: Bool
    let onSave: (UserChanges) -> Void
    @State private var user: CraftyUser
    @State private var password = ""

    init(user: CraftyUser, roles: [Role], canGrantSuperuser: Bool, isSelf: Bool, onSave: @escaping (UserChanges) -> Void) {
        original = user; self.roles = roles; self.canGrantSuperuser = canGrantSuperuser; self.isSelf = isSelf
        self.onSave = onSave
        _user = State(initialValue: user)
    }

    private var isNew: Bool { original.userID == 0 }
    private var changes: UserChanges { UserChanges(from: isNew ? nil : original, to: user, password: password) }
    private var problem: String? { UserChanges.problem(for: user, password: password, isNew: isNew) }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        TextField("Username", text: Binding(get: { user.username }, set: { user.username = $0.lowercased() }))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField(isNew ? "Password" : "New password (optional)", text: $password)
                            .textContentType(.newPassword)
                    } footer: {
                        if let problem, !user.username.isEmpty || !password.isEmpty {
                            Text(problem).foregroundStyle(Theme.warning)
                        } else {
                            Text("Lowercase letters, digits and _; passwords need at least 8 characters.")
                        }
                    }
                    Section {
                        Toggle("Enabled", isOn: $user.enabled).disabled(isSelf)
                        if canGrantSuperuser {
                            Toggle("Superuser", isOn: $user.superuser).disabled(isSelf)
                        }
                        Picker("Language", selection: $user.lang) {
                            ForEach(languages, id: \.self) { Text(languageName($0)).tag($0) }
                        }
                    }
                    if !user.superuser {
                        Section {
                            if roles.isEmpty {
                                Text("No roles on this panel yet.").foregroundStyle(Theme.secondaryText)
                            }
                            ForEach(roles) { r in
                                Toggle(r.roleName, isOn: Binding(get: { user.roleIDs.contains(r.roleID) }, set: { on in
                                    if on { user.roleIDs.append(r.roleID) } else { user.roleIDs.removeAll { $0 == r.roleID } }
                                }))
                                .disabled(isSelf && !canGrantSuperuser)
                            }
                        } header: {
                            Text("Roles")
                        } footer: {
                            if isSelf && !canGrantSuperuser { Text("Only a superuser can change your own roles.") }
                        }
                    }
                    if let last = user.lastLogin {
                        Section("Activity") {
                            LabeledContent("Last login", value: last)
                            if let ip = user.lastIP { LabeledContent("IP") { Text(ip).font(.mono(.footnote)) } }
                        }
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle(isNew ? String(localized: "New User") : original.username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(changes); dismiss() }
                        .disabled(problem != nil || (!isNew && changes.isEmpty))
                }
            }
        }
    }

    /// The panel's translation files shared by 4.7.0 and 4.11.0; a language added later stays selectable.
    private var languages: [String] {
        let known = ["cs_CS", "de_DE", "en_EN", "es_ES", "fi_FI", "fr_FR", "fy_NL", "he_IL", "hr_HR", "hu_HU", "id_ID",
                     "it_IT", "ja_JP", "ko_KR", "lv_LV", "nl_BE", "nl_NL", "pl_PL", "pt_BR", "ru_RU", "sr_RS", "th_TH",
                     "tr_TR", "uk_UA", "zh_CN"]
        return known.contains(user.lang) ? known : known + [user.lang]
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
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
                    Section {
                        TextField("Role name", text: $role.roleName)
                        Toggle("Require 2FA for members", isOn: $role.mfaRequired)
                    } footer: {
                        if !role.roleName.isEmpty && !Role.isValidName(role.roleName) {
                            Text("Role names cannot contain , [ or ].").foregroundStyle(Theme.warning)
                        } else if role.roleID == 0 {
                            Text("The panel saves new role names in lowercase.")
                        }
                    }
                    if role.servers == nil {
                        Section {
                            Text("Only superusers can see and change which servers a role covers. Saving keeps them as they are.")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                    } else {
                        ForEach(servers) { s in serverSection(s) }
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle(role.roleID == 0 ? String(localized: "New Role") : role.roleName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(role); dismiss() }.disabled(!Role.isValidName(role.roleName))
                }
            }
        }
    }

    private func serverSection(_ s: Server) -> some View {
        Section(s.serverName) {
            let idx = role.servers?.firstIndex { $0.serverID == s.id }
            Toggle("Access", isOn: Binding(get: { idx != nil }, set: { on in
                if on { role.servers?.append(RoleServerPermission(serverID: s.id, permissions: "00100000")) }
                else { role.servers?.removeAll { $0.serverID == s.id } }
            }))
            if let i = idx {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading) {
                    ForEach(ServerPermission.allCases) { p in
                        Toggle(p.label, isOn: Binding(get: { role.servers?[i].has(p) ?? false },
                                                      set: { role.servers?[i].set(p, $0) }))
                            .toggleStyle(.button).controlSize(.small)
                            .accessibilityLabel("\(p.label) on \(s.serverName)")
                    }
                }
            }
        }
    }
}

#Preview { AdminView().environment(AppState.preview) }
