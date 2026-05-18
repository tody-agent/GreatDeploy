import SwiftUI

/// Menu bar section for quick MCP sync access.
/// Embed this in MenuBarContentView to show MCP sync status and actions.
struct MCPMenuSection: View {
    @EnvironmentObject var bundleStore: MCPBundleStore
    @State private var lastSyncInfo: String = "Never synced"
    @State private var isQuickSyncing = false

    var body: some View {
        Group {
            Divider()

            Text("MCP")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)

            Button(action: { Task { await quickSync() } }) {
                Label("Sync Now", systemImage: isQuickSyncing ? "" : "arrow.triangle.2.circlepath")
            }
            .disabled(bundleStore.bundles.isEmpty || isQuickSyncing)

            Text(lastSyncInfo)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.leading, 16)

            if let bundle = bundleStore.activeBundle {
                Text("\(bundle.servers.count) servers \u{2192} \(bundle.enabledClients.count) clients")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 16)
            }
        }
    }

    private func quickSync() async {
        guard let bundle = bundleStore.activeBundle else { return }

        isQuickSyncing = true
        defer { isQuickSyncing = false }

        let adapter = MCPSyncAdapter(
            bundleStore: bundleStore,
            keychainService: KeychainService.shared,
            fileSystem: MacFileSystem()
        )
        let results = await adapter.sync(bundle: bundle)

        let successCount = results.filter { $0.success }.count
        let totalCount = results.count
        lastSyncInfo = "Last sync: \(successCount)/\(totalCount) clients"
    }
}
