import SwiftUI

/// Shown when the panel rejects the stored token (expired, or all sessions were signed out).
/// Signs in to the same panel again and replaces the token in the Keychain.
struct SignInAgainView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var totp = ""
    @State private var apiToken = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        if usesToken {
                            SecureField("API token from Panel → Users → API Keys", text: $apiToken)
                        } else {
                            TextField("Username", text: $username)
                                .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField("Password", text: $password).textContentType(.password)
                            TextField("2FA code (if enabled)", text: $totp)
                                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        }
                    } header: {
                        Text(app.activeInstance?.name ?? String(localized: "Panel"))
                    } footer: {
                        Text("Your session on this panel has ended, for example because it expired or all sessions were signed out. Sign in again to continue.")
                    }

                    if let error {
                        Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger) }
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle("Sign In Again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Sign In") { Task { await signIn() } }
                            .disabled(usesToken ? apiToken.isEmpty : username.isEmpty || password.isEmpty)
                    }
                }
            }
            .onAppear { username = app.activeInstance?.username ?? "" }
        }
    }

    private var usesToken: Bool { app.activeInstance?.authMethod == .apiToken }

    private func signIn() async {
        guard var instance = app.activeInstance else { return }
        busy = true; error = nil
        defer { busy = false }
        let client = APIClient(baseURL: instance.baseURL, pinnedSHA256: instance.pinnedCertificateSHA256)
        let service = LiveCraftyService(client: client)
        do {
            let token: String
            if usesToken {
                client.token = apiToken
                _ = try await service.servers()   // validate token
                token = apiToken
            } else {
                token = try await service.login(username: username, password: password, totp: totp.isEmpty ? nil : totp)
                instance.username = username
            }
            app.reauthenticate(instance, token: token)
        } catch {
            self.error = error.panelProblem == .sessionExpired ? String(localized: "The panel rejected this token.") : error.localizedDescription
        }
    }
}

#Preview { SignInAgainView().environment(AppState.preview) }
