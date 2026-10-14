import SwiftUI

/// Server wizard: Java (Paper, Purpur, Fabric, Forge, NeoForge, Vanilla …) or Bedrock.
/// Crafty downloads the JAR itself from its "Big Bucket" (jars.arcadiatech.org).
struct CreateServerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var req = CreateServerRequest(name: "", kind: .java)
    @State private var busy = false
    @State private var error: String?

    private let jarTypes = ["paper", "purpur", "fabric", "forge", "neoforge", "vanilla", "spigot", "folia", "velocity", "waterfall"]
    private let versions = ["1.21.4", "1.21.3", "1.21.1", "1.20.6", "1.20.4", "1.20.1", "1.19.4", "1.18.2", "1.16.5", "1.12.2"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Server name", text: $req.name)
                Picker("Edition", selection: $req.kind) {
                    Text("Java").tag(CreateServerRequest.Kind.java)
                    Text("Bedrock").tag(CreateServerRequest.Kind.bedrock)
                }.pickerStyle(.segmented)

                if req.kind == .java {
                    Section("Software") {
                        Picker("Type", selection: $req.jarType) { ForEach(jarTypes, id: \.self) { Text($0.capitalized) } }
                        Picker("Version", selection: $req.version) { ForEach(versions, id: \.self) { Text($0) } }
                    }
                    Section("Resources") {
                        Stepper("Min RAM: \(req.memMinGB) GB", value: $req.memMinGB, in: 1...req.memMaxGB)
                        Stepper("Max RAM: \(req.memMaxGB) GB", value: $req.memMaxGB, in: req.memMinGB...64)
                        TextField("Port", value: $req.port, format: .number.grouping(.never)).keyboardType(.numberPad)
                    }
                } else {
                    Toggle(isOn: $req.agreeToEULA) {
                        Text("I accept the Minecraft EULA and the Mojang/Microsoft privacy policy")
                    }
                }

                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Create") { Task { await create() } }
                            .disabled(req.name.isEmpty || (req.kind == .bedrock && !req.agreeToEULA))
                    }
                }
            }
        }
    }

    private func create() async {
        busy = true; defer { busy = false }
        do { _ = try await app.service.createServer(req); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

#Preview { CreateServerView().environment(AppState.preview) }
