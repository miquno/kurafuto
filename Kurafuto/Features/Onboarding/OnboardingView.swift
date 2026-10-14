import SwiftUI

/// First launch: enter the panel address, sign in (password + optional 2FA/TOTP) or paste an API token.
/// Alternatively "Try the demo" with mock data – also important for App Review (Apple needs a test account!).
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var name = "My Server"
    @State private var address = "https://"
    @State private var username = ""
    @State private var password = ""
    @State private var totp = ""
    @State private var apiToken = ""
    @State private var useToken = false
    @State private var busy = false
    @State private var error: String?
    @State private var certToTrust: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 44)).foregroundStyle(Theme.accent)
                        Text("Your servers. In your pocket.").font(.title2.bold())
                        Text("Connect to your self-hosted Crafty Controller panel (version 4.x).")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Panel") {
                    TextField("Name", text: $name)
                    TextField("Address, e.g. https://192.168.1.20:8443", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }

                Section {
                    Picker("Sign-in method", selection: $useToken) {
                        Text("Account").tag(false)
                        Text("API Token").tag(true)
                    }.pickerStyle(.segmented)

                    if useToken {
                        SecureField("API token from Panel → Users → API Keys", text: $apiToken)
                    } else {
                        TextField("Username", text: $username)
                            .textContentType(.username).textInputAutocapitalization(.never)
                        SecureField("Password", text: $password).textContentType(.password)
                        TextField("2FA code (if enabled)", text: $totp)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    }
                } footer: {
                    Text("Credentials are stored only on this device in the Keychain and are sent exclusively to your panel.")
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }

                Section {
                    Button { Task { await connect() } } label: {
                        HStack { Spacer(); if busy { ProgressView() } else { Text("Connect").bold() }; Spacer() }
                    }
                    .disabled(busy || URL(string: address)?.host == nil)

                    Button("Try the Demo with Sample Data") { app.startDemo() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Welcome")
            .alert("Self-Signed Certificate", isPresented: .constant(certToTrust != nil)) {
                Button("Trust") { Task { await connect(trusting: certToTrust) } }
                Button("Cancel", role: .cancel) { certToTrust = nil }
            } message: {
                Text("Compare this fingerprint with your panel's certificate:\n\n\(certToTrust ?? "")")
            }
        }
    }

    private func connect(trusting sha: String? = nil) async {
        certToTrust = nil
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)) else { return }
        busy = true; error = nil
        defer { busy = false }

        let client = APIClient(baseURL: url, pinnedSHA256: sha)
        let service = LiveCraftyService(client: client)
        do {
            let token: String
            if useToken {
                client.token = apiToken
                _ = try await service.servers()   // validate token
                token = apiToken
            } else {
                token = try await service.login(username: username, password: password, totp: totp.isEmpty ? nil : totp)
            }
            let inst = Instance(name: name, baseURL: url, username: username,
                                authMethod: useToken ? .apiToken : .password, pinnedCertificateSHA256: sha)
            app.instanceStore.upsert(inst, token: token)
            app.switchTo(inst)
        } catch CraftyError.untrustedCertificate(let fingerprint) {
            certToTrust = fingerprint
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview { OnboardingView().environment(AppState.preview) }
