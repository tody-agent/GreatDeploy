import SwiftUI

struct MCPClientsSyncView: View {
    @EnvironmentObject var bundleStore: MCPBundleStore
    @State private var isSyncing = false
    @State private var lastResults: [MCPSyncResult] = []
    @State private var showingSyncSummary = false

    var activeBundle: MCPBundle? {
        bundleStore.activeBundle
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            clientsListView
            Divider()
            syncButtonBar
        }
        .sheet(isPresented: $showingSyncSummary) {
            syncSummarySheet
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Client Sync")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Push MCP servers to your AI coding tools")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
    }

    private var clientsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(MCPClientKind.allCases, id: \.self) { client in
                    clientRow(client)
                    if client != MCPClientKind.allCases.last {
                        Divider().padding(.leading, 60)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func clientRow(_ client: MCPClientKind) -> some View {
        let isInstalled = client.isInstalled
        let isEnabled = activeBundle?.enabledClients.contains(client) ?? false
        let syncState = bundleStore.syncState(for: client)
        let lastSynced = syncState?.lastSyncedAt

        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isInstalled ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: client.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(isInstalled ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(client.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(isInstalled ? "Installed" : "Not installed")
                        .font(.caption)
                        .foregroundStyle(isInstalled ? .green : .gray)
                    if let lastSynced = lastSynced {
                        Text("\u{2022} Synced \(lastSynced.relativeDescription)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let state = syncState {
                        Text("\u{2022} \(state.lastSyncedServerNames.count) servers")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in toggleClient(client, enabled: newValue) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!isInstalled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .opacity(isInstalled ? 1 : 0.5)
    }

    private var syncButtonBar: some View {
        HStack {
            if let bundle = activeBundle {
                Text("\(bundle.enabledClients.count) client\(bundle.enabledClients.count == 1 ? "" : "s") enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { Task { await syncAll() } }) {
                Label(isSyncing ? "Syncing..." : "Sync All", systemImage: isSyncing ? "" : "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing || activeBundle == nil || activeBundle?.enabledClients.isEmpty == true)
        }
        .padding()
    }

    private var syncSummarySheet: some View {
        NavigationStack {
            Form {
                ForEach(lastResults, id: \.client) { result in
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? .green : .red)
                        Text(result.client.displayName)
                        Spacer()
                        if result.success {
                            Text("\(result.serversWritten) servers")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(result.error ?? "Unknown error")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sync Results")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSyncSummary = false }
                }
            }
        }
        .frame(width: 400, height: 300)
    }

    private func toggleClient(_ client: MCPClientKind, enabled: Bool) {
        guard var bundle = activeBundle else { return }
        if enabled {
            bundle.enabledClients.insert(client)
        } else {
            bundle.enabledClients.remove(client)
        }
        bundle.updatedAt = Date()
        try? bundleStore.updateBundle(bundle)
    }

    private func syncAll() async {
        guard let bundle = activeBundle else { return }

        isSyncing = true
        defer { isSyncing = false }

        let adapter = MCPSyncAdapter(
            bundleStore: bundleStore,
            keychainService: KeychainService.shared,
            fileSystem: MacFileSystem()
        )
        let results = await adapter.sync(bundle: bundle)

        lastResults = results
        showingSyncSummary = true
    }
}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
