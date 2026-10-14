import SwiftUI

/// App settings: switch panels, Face ID, sign out, legal.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage("faceID") private var faceID = false
    @AppStorage("pollSeconds") private var pollSeconds = 5.0
    @State private var confirmLogoutAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Panels") {
                    ForEach(app.instanceStore.instances) { inst in
                        Button { app.switchTo(inst) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(inst.name).foregroundStyle(.primary)
                                    Text(inst.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if inst.id == app.activeInstance?.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                    Button("Add Panel") { app.activeInstance = nil }
                }

                Section("Security") {
                    Toggle("Lock with Face ID", isOn: $faceID)
                    Button("Sign Out All Sessions", role: .destructive) { confirmLogoutAll = true }
                    Button("Sign Out of This Panel", role: .destructive) { app.signOut() }
                }

                Section("Refresh") {
                    Stepper("Live values every \(Int(pollSeconds)) s", value: $pollSeconds, in: 2...60)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                    Link("Website", destination: AppLinks.website)
                    Link("Source Code", destination: AppLinks.sourceCode)
                    Text("Unofficial app. Not affiliated with or endorsed by Arcadia Technology (Crafty Controller), Mojang or Microsoft.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("End all sessions for this user?", isPresented: $confirmLogoutAll, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { try? await app.service.invalidateAllSessions(); app.signOut() }
                }
            }
        }
    }
}

enum AppLinks {
    static let sourceCode = URL(string: "https://github.com/miquno/kurafuto") ?? URL(filePath: "/")
    static let privacyPolicy = URL(string: "https://getkurafuto.app/privacy/") ?? URL(filePath: "/")
    static let website = URL(string: "https://getkurafuto.app") ?? URL(filePath: "/")
}
