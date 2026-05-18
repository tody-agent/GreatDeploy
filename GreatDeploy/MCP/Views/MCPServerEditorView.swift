import SwiftUI

struct MCPServerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bundleStore: MCPBundleStore

    let server: MCPServerDefinition?
    let bundleId: UUID

    @State private var name = ""
    @State private var displayName = ""
    @State private var serverDescription = ""
    @State private var transport: TransportType = .stdio
    @State private var command = ""
    @State private var argsText = ""
    @State private var url = ""
    @State private var enabled = true
    @State private var envPairs: [EnvPair] = []
    @State private var tagsText = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    struct EnvPair: Identifiable {
        let id = UUID()
        var key = ""
        var value = ""
        var isSecret = false
    }

    var isEditing: Bool { server != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Server name", text: $name)
                    TextField("Display name (optional)", text: $displayName)
                    TextField("Description (optional)", text: $serverDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Transport") {
                    Picker("Transport", selection: $transport) {
                        ForEach(TransportType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if transport == .stdio {
                    Section("Command") {
                        TextField("Command (e.g., npx)", text: $command)
                        TextField("Args (space-separated)", text: $argsText)
                            .font(.system(.body, design: .monospaced))
                    }
                } else {
                    Section("URL") {
                        TextField("Server URL", text: $url)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("Environment Variables") {
                    envVariablesSection
                    Button(action: { envPairs.append(EnvPair()) }) {
                        Label("Add Variable", systemImage: "plus")
                    }
                }

                Section("Options") {
                    Toggle("Enabled", isOn: $enabled)
                    TextField("Tags (comma-separated)", text: $tagsText)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveServer()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear(perform: loadServer)
        }
        .frame(width: 500, height: 600)
    }

    private var envVariablesSection: some View {
        ForEach($envPairs) { $pair in
            HStack {
                TextField("Key", text: $pair.key)
                    .frame(width: 120)
                SecureField(pair.isSecret ? "Stored in Keychain" : "Value", text: $pair.value)
                Toggle("Secret", isOn: $pair.isSecret)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button(action: { envPairs.removeAll { $0.id == pair.id } }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadServer() {
        guard let server = server else { return }
        name = server.name
        displayName = server.displayName ?? ""
        self.serverDescription = server.serverDescription ?? ""
        transport = server.transport
        command = server.command ?? ""
        argsText = server.args.joined(separator: " ")
        url = server.url ?? ""
        enabled = server.enabled
        tagsText = server.tags.joined(separator: ", ")

        for key in server.secretEnvKeys {
            let value = KeychainService.shared.readMCPSecret(
                bundleId: bundleId,
                serverId: server.id,
                envKey: key
            ) ?? ""
            envPairs.append(EnvPair(key: key, value: value, isSecret: true))
        }
        for (key, value) in server.env where !server.secretEnvKeys.contains(key) {
            envPairs.append(EnvPair(key: key, value: value, isSecret: false))
        }
    }

    private func saveServer() {
        guard !name.isEmpty else { return }

        let args = argsText.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        var env: [String: String] = [:]
        var secretKeys: [String] = []
        for pair in envPairs where !pair.key.isEmpty {
            if pair.isSecret {
                secretKeys.append(pair.key)
            } else {
                env[pair.key] = pair.value
            }
        }

        let newServer = MCPServerDefinition(
            id: server?.id ?? UUID(),
            name: name,
            displayName: displayName.isEmpty ? nil : displayName,
            serverDescription: self.serverDescription.isEmpty ? nil : self.serverDescription,
            enabled: enabled,
            transport: transport,
            command: transport == .stdio ? (command.isEmpty ? nil : command) : nil,
            args: args,
            env: env,
            url: transport != .stdio ? (url.isEmpty ? nil : url) : nil,
            secretEnvKeys: secretKeys,
            tags: tags,
            updatedAt: Date()
        )

        do {
            if let _ = server {
                try bundleStore.updateServer(newServer, in: bundleId)
            } else {
                try bundleStore.addServer(newServer, to: bundleId)
            }

            for pair in envPairs where pair.isSecret && !pair.key.isEmpty {
                try KeychainService.shared.saveMCPSecret(
                    bundleId: bundleId,
                    serverId: newServer.id,
                    envKey: pair.key,
                    value: pair.value
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
