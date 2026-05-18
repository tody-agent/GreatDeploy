import Foundation
import os.log

/// Actor-isolated MCP sync engine.
/// Orchestrates syncing a bundle's servers to multiple AI coding tool clients.
/// Thread-safe via actor isolation — no @MainActor dependency.
actor MCPSyncEngine {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.greatdeploy.GreatDeploy", category: "MCPSyncEngine")

    private let bundleStore: MCPBundleStore
    private let keychainService: KeychainService
    private let fileSystem: FileSystem
    private let auditLogger: AuditLogger
    private let makeAdapterFn: @Sendable (MCPClientKind) -> MCPClientAdapter

    nonisolated init(
        bundleStore: MCPBundleStore,
        keychainService: KeychainService = KeychainService.shared,
        fileSystem: FileSystem = MacFileSystem(),
        auditLogger: AuditLogger = AuditLogger.shared,
        makeAdapter: @escaping @Sendable (MCPClientKind) -> MCPClientAdapter = { $0.makeAdapter() }
    ) {
        self.bundleStore = bundleStore
        self.keychainService = keychainService
        self.fileSystem = fileSystem
        self.auditLogger = auditLogger
        self.makeAdapterFn = makeAdapter
    }

    /// Syncs a bundle's servers to the specified clients.
    /// Per-client flow (SEQUENTIAL for simple rollback semantics):
    /// 1. adapter = makeAdapterFn(client)
    /// 2. if !adapter.detect() → skip (success=true, written=0)
    /// 3. Inject secrets from Keychain → env (missing → warning)
    /// 4. Capture existingContent for rollback
    /// 5. Load previouslySyncedNames from MCPSyncState
    /// 6. adapter.writeServers(enriched, existingContent, previouslySyncedNames)
    /// 7. VERIFY: adapter.readServers() ⊇ enriched.names
    ///    → if fail → atomic-write existingContent back → result success=false
    /// 8. Update MCPSyncState (cumulative previouslySyncedNames)
    /// 9. Audit log (NO secrets — only server.name + envKey)
    func sync(
        bundle: MCPBundle,
        toClients clients: Set<MCPClientKind>
    ) async -> [MCPSyncResult] {
        var results: [MCPSyncResult] = []
        let enabledServers = bundle.servers.filter { $0.enabled }

        for client in clients {
            let adapter = makeAdapterFn(client)
            let startTime = Date()

            if !adapter.detect() {
                Self.logger.info("Client \(client.displayName, privacy: .public) not installed, skipping")
                results.append(MCPSyncResult(
                    client: client,
                    success: true,
                    serversWritten: 0,
                    warnings: ["Client not installed"]
                ))
                continue
            }

            let existingContent: String?
            if let path = adapter.configPath(), fileSystem.exists(path) {
                existingContent = try? String(contentsOf: path, encoding: .utf8)
            } else {
                existingContent = nil
            }

            do {
                let enrichedServers = try injectSecrets(enabledServers, for: bundle.id)

                let syncState = await bundleStore.syncState(for: client) ?? MCPSyncState(clientId: client)
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
                        try fileSystem.atomicWrite(Data(content.utf8), to: path)
                    }
                    let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                    let result = MCPSyncResult(
                        client: client,
                        success: false,
                        serversWritten: 0,
                        error: "Verification failed: servers not found after write",
                        durationMs: duration
                    )
                    results.append(result)
                    await auditLogger.logSyncFailure(client: client, bundle: bundle, error: result.error ?? "unknown")
                    continue
                }

                let newNames = Set(enrichedServers.map { $0.name.lowercased() })
                let newState = MCPSyncState(
                    clientId: client,
                    lastSyncedAt: Date(),
                    lastSyncedServerNames: enrichedServers.map(\.name),
                    previouslySyncedNames: previouslySyncedNames.union(newNames)
                )
                await bundleStore.updateSyncState(newState)

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                let result = MCPSyncResult(
                    client: client,
                    success: true,
                    serversWritten: enrichedServers.count,
                    durationMs: duration
                )
                results.append(result)
                await auditLogger.logSyncSuccess(client: client, bundle: bundle, serverCount: enrichedServers.count, durationMs: duration)

            } catch let error as KeychainService.KeychainError {
                Self.logger.warning("Keychain error during sync: \(error, privacy: .public)")
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                results.append(MCPSyncResult(
                    client: client,
                    success: false,
                    error: "Keychain error: \(error.localizedDescription)",
                    durationMs: duration
                ))
            } catch {
                if let path = adapter.configPath(), let content = existingContent {
                    try? fileSystem.atomicWrite(Data(content.utf8), to: path)
                }
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                results.append(MCPSyncResult(
                    client: client,
                    success: false,
                    error: error.localizedDescription,
                    durationMs: duration
                ))
                await auditLogger.logSyncFailure(client: client, bundle: bundle, error: error.localizedDescription)
            }
        }

        return results
    }

    /// Injects secrets from Keychain into server env maps.
    private func injectSecrets(
        _ servers: [MCPServerDefinition],
        for bundleId: UUID
    ) throws -> [MCPServerDefinition] {
        try servers.map { server in
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
