import Foundation

/// Snapshot data for MCP sync rollback.
/// Captures the existing content of each client's config file before sync.
struct MCPSyncSnapshot: Sendable {
    /// Map of client kind → existing file content (for rollback)
    let clientContents: [MCPClientKind: String?]

    /// Map of client kind → previously synced names (for orphan tracking)
    let previousStates: [MCPClientKind: MCPSyncState]
}

/// Adapter for MCP sync integration with SwitchEngine.
/// This is the LAST adapter in the switch chain (GitHub → Cloudflare → MCP).
/// Reason: MCP config is easiest to recover (just re-write config files).
@MainActor
final class MCPSyncAdapter {

    private let bundleStore: MCPBundleStore
    private let keychainService: KeychainService
    private let fileSystem: FileSystem

    init(
        bundleStore: MCPBundleStore,
        keychainService: KeychainService,
        fileSystem: FileSystem
    ) {
        self.bundleStore = bundleStore
        self.keychainService = keychainService
        self.fileSystem = fileSystem
    }

    /// Convenience initializer for production use.
    convenience init() {
        self.init(
            bundleStore: MCPBundleStore(),
            keychainService: KeychainService.shared,
            fileSystem: MacFileSystem()
        )
    }

    /// Captures current state of ALL enabled client configs for rollback.
    func snapshot(for bundle: MCPBundle) -> MCPSyncSnapshot {
        var contents: [MCPClientKind: String?] = [:]
        var states: [MCPClientKind: MCPSyncState] = [:]

        for client in bundle.enabledClients {
            let adapter = client.makeAdapter()
            let path = adapter.configPath()

            if let path = path, fileSystem.exists(path) {
                contents[client] = try? String(contentsOf: path, encoding: .utf8)
            } else {
                contents[client] = nil
            }

            states[client] = bundleStore.syncState(for: client) ?? MCPSyncState(clientId: client)
        }

        return MCPSyncSnapshot(clientContents: contents, previousStates: states)
    }

    /// Syncs bundle to all enabled clients.
    /// Returns results for each client.
    func sync(bundle: MCPBundle) async -> [MCPSyncResult] {
        var results: [MCPSyncResult] = []
        let enabledServers = bundle.enabledServers

        for client in bundle.enabledClients {
            let adapter = client.makeAdapter()
            let startTime = Date()

            if !adapter.detect() {
                results.append(MCPSyncResult(
                    client: client,
                    success: true,
                    serversWritten: 0,
                    warnings: ["Client not installed"]
                ))
                continue
            }

            do {
                let enrichedServers = try injectSecrets(enabledServers, for: bundle.id)

                let existingContent: String?
                if let path = adapter.configPath(), fileSystem.exists(path) {
                    existingContent = try String(contentsOf: path, encoding: .utf8)
                } else {
                    existingContent = nil
                }

                let syncState = bundleStore.syncState(for: client) ?? MCPSyncState(clientId: client)
                let previouslySyncedNames = syncState.previouslySyncedNames

                try adapter.writeServers(
                    enrichedServers,
                    existingContent: existingContent,
                    previouslySyncedNames: previouslySyncedNames
                )

                let readBack = try adapter.readServers()
                let readBackNames = Set(readBack.map { $0.name.lowercased() })
                let expectedNames = Set(enrichedServers.map { $0.name.lowercased() })

                if !expectedNames.isSubset(of: readBackNames) {
                    if let path = adapter.configPath(), let content = existingContent {
                        try fileSystem.atomicWrite(
                            Data(content.utf8),
                            to: path
                        )
                    }
                    results.append(MCPSyncResult(
                        client: client,
                        success: false,
                        error: "Verification failed: servers not found after write"
                    ))
                    continue
                }

                let newState = MCPSyncState(
                    clientId: client,
                    lastSyncedAt: Date(),
                    lastSyncedServerNames: enrichedServers.map(\.name),
                    previouslySyncedNames: previouslySyncedNames.union(expectedNames)
                )
                bundleStore.updateSyncState(newState)

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                results.append(MCPSyncResult(
                    client: client,
                    success: true,
                    serversWritten: enrichedServers.count,
                    durationMs: duration
                ))

            } catch {
                let snap = snapshot(for: bundle)
                if let path = adapter.configPath(),
                   case let content?? = snap.clientContents[client] {
                    try? fileSystem.atomicWrite(Data(content.utf8), to: path)
                }

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                results.append(MCPSyncResult(
                    client: client,
                    success: false,
                    error: error.localizedDescription,
                    durationMs: duration
                ))
            }
        }

        return results
    }

    /// Reverts all clients to their pre-sync state.
    func revert(to snapshot: MCPSyncSnapshot) async {
        for (client, content) in snapshot.clientContents {
            let adapter = client.makeAdapter()
            guard let path = adapter.configPath() else { continue }

            if let content = content {
                try? fileSystem.atomicWrite(Data(content.utf8), to: path)
            } else {
                try? FileManager.default.removeItem(at: path)
            }
        }

        for (_, state) in snapshot.previousStates {
            bundleStore.updateSyncState(state)
        }
    }

    /// Injects secrets from Keychain into server env maps.
    func injectSecrets(
        _ servers: [MCPServerDefinition],
        for bundleId: UUID
    ) throws -> [MCPServerDefinition] {
        servers.map { server in
            var enriched = server
            for key in server.secretEnvKeys {
                if let value = keychainService.readMCPSecret(
                    bundleId: bundleId,
                    serverId: server.id,
                    envKey: key
                ) {
                    enriched.env[key] = value
                }
            }
            return enriched
        }
    }
}
