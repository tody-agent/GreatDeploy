import SwiftUI

struct MCPListView: View {
    @State private var servers: [MCPServerConfig] = []
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var newServerName = ""
    @State private var newServerCommand = ""
    @State private var newServerArgs = ""
    @State private var isLoading = true

    private let mcpService = MCPConfigService.shared

    var filteredServers: [MCPServerConfig] {
        if searchText.isEmpty { return servers }
        return servers.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if isLoading {
                loadingView
            } else if servers.isEmpty {
                emptyStateView
            } else {
                serversListView
            }
        }
        .onAppear(perform: loadServers)
        .sheet(isPresented: $showingAddSheet) { addServerSheet }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MCP Servers")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("\(servers.count) servers configured globally")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button(action: { showingAddSheet = true }) {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Text("Loading MCP servers...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No MCP Servers")
                .font(.title3)
                .fontWeight(.medium)
            Text("MCP connects AI to external tools like databases,\nAPIs, and file systems.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: { showingAddSheet = true }) {
                Label("Add First Server", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var serversListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredServers) { server in
                    serverRow(server)
                    if server.id != filteredServers.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func serverRow(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "server.rack")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(server.command) \(server.args.joined(separator: " "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: { deleteServer(server) }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var addServerSheet: some View {
        VStack(spacing: 20) {
            Text("Add MCP Server")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                TextField("e.g., filesystem, postgres", text: $newServerName)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Command")
                TextField("e.g., npx", text: $newServerCommand)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Args (space-separated)")
                TextField("e.g., -y @modelcontextprotocol/server", text: $newServerArgs)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Cancel") { showingAddSheet = false; clearForm() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Add") { addServer() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newServerName.isEmpty || newServerCommand.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func loadServers() {
        isLoading = true
        servers = (try? mcpService.getMCPServers()) ?? []
        isLoading = false
    }

    private func addServer() {
        let server = MCPServerConfig(
            name: newServerName,
            command: newServerCommand,
            args: newServerArgs.split(separator: " ").map(String.init),
            env: [:]
        )
        do {
            try mcpService.setMCPServer(server)
            servers.append(server)
            clearForm()
            showingAddSheet = false
        } catch {}
    }

    private func deleteServer(_ server: MCPServerConfig) {
        do {
            try mcpService.removeMCPServer(named: server.name)
            servers.removeAll { $0.id == server.id }
        } catch {}
    }

    private func clearForm() {
        newServerName = ""
        newServerCommand = ""
        newServerArgs = ""
    }
}