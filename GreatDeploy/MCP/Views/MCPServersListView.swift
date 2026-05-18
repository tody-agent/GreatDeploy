import SwiftUI

struct MCPServersListView: View {
    @EnvironmentObject var bundleStore: MCPBundleStore
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var editingServer: MCPServerDefinition?
    @State private var showingDeleteConfirmation = false
    @State private var serverToDelete: MCPServerDefinition?

    var activeBundle: MCPBundle? {
        bundleStore.activeBundle
    }

    var filteredServers: [MCPServerDefinition] {
        guard let bundle = activeBundle else { return [] }
        if searchText.isEmpty { return bundle.servers }
        return bundle.servers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.displayName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        Group {
            if activeBundle == nil {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    toolbarView
                    Divider()
                    serverListView
                    Divider()
                    summaryBarView
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            MCPServerEditorView(
                server: editingServer,
                bundleId: activeBundle?.id ?? UUID()
            )
            .environmentObject(bundleStore)
        }
        .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let server = serverToDelete, let bundle = activeBundle {
                    try? bundleStore.removeServer(id: server.id, from: bundle.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(serverToDelete?.name ?? "")'?")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No MCP bundles configured")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Create a bundle to start managing MCP servers")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbarView: some View {
        HStack {
            Text("MCP Servers")
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Button(action: { editingServer = nil; showingEditor = true }) {
                Label("Add Server", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var serverListView: some View {
        Group {
            if filteredServers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No servers match your search")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredServers) { server in
                            serverRow(server)
                            if server.id != filteredServers.last?.id {
                                Divider().padding(.leading, 60)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func serverRow(_ server: MCPServerDefinition) -> some View {
        HStack(spacing: 16) {
            Circle()
                .fill(server.enabled ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: server.transport.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(server.displayName ?? server.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(server.transport.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
                if let cmd = server.command {
                    Text(cmd)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !server.secretEnvKeys.isEmpty {
                Image(systemName: "key.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            Button(action: { editingServer = server; showingEditor = true }) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: { serverToDelete = server; showingDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .opacity(server.enabled ? 1 : 0.5)
    }

    private var summaryBarView: some View {
        HStack {
            if let bundle = activeBundle {
                Text("\(bundle.servers.count) server\(bundle.servers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bundle.enabledClients.count) client\(bundle.enabledClients.count == 1 ? "" : "s") enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
