import Foundation

/// Resolves conflicts between local and remote bundles.
/// Per-server level conflict resolution with last-write-wins default.
enum ConflictResolver {

    /// Result of merging local and remote bundles.
    struct MergeResult {
        let mergedBundles: [MCPBundle]
        let conflicts: [Conflict]
    }

    /// A detected conflict.
    struct Conflict: Identifiable {
        let id = UUID()
        let bundleId: UUID
        let serverName: String
        let localVersion: MCPServerDefinition
        let remoteVersion: MCPServerDefinition
        let resolution: Resolution

        enum Resolution {
            case keepLocal
            case keepRemote
            case unresolved
        }
    }

    /// Merge local and remote bundles.
    /// - Per-server: last-write-wins based on updatedAt timestamp.
    /// - Same timestamp, different content → flag conflict, keep local by default.
    /// - Identical content → no-op.
    /// - New servers on either side → add.
    /// - Deleted servers → detect via missing IDs.
    static func merge(
        local: [MCPBundle],
        remote: [MCPBundle]
    ) -> MergeResult {
        var merged: [MCPBundle] = []
        var conflicts: [Conflict] = []

        let localMap = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteMap = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })

        let allIds = Set(localMap.keys).union(remoteMap.keys)

        for bundleId in allIds.sorted() {
            let localBundle = localMap[bundleId]
            let remoteBundle = remoteMap[bundleId]

            if let local = localBundle, let remote = remoteBundle {
                let (mergedServers, bundleConflicts) = mergeServers(
                    local: local.servers,
                    remote: remote.servers
                )
                conflicts.append(contentsOf: bundleConflicts)

                let base = local.updatedAt >= remote.updatedAt ? local : remote
                var mergedBundle = base
                mergedBundle.servers = mergedServers
                mergedBundle.updatedAt = max(local.updatedAt, remote.updatedAt)
                merged.append(mergedBundle)

            } else if let local = localBundle {
                merged.append(local)
            } else if let remote = remoteBundle {
                merged.append(remote)
            }
        }

        return MergeResult(mergedBundles: merged, conflicts: conflicts)
    }

    /// Merge servers from local and remote.
    private static func mergeServers(
        local: [MCPServerDefinition],
        remote: [MCPServerDefinition]
    ) -> (servers: [MCPServerDefinition], conflicts: [Conflict]) {
        var result: [MCPServerDefinition] = []
        var conflicts: [Conflict] = []

        let localMap = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteMap = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })

        let allIds = Set(localMap.keys).union(remoteMap.keys)

        for serverId in allIds.sorted() {
            let localServer = localMap[serverId]
            let remoteServer = remoteMap[serverId]

            if let local = localServer, let remote = remoteServer {
                if local == remote {
                    result.append(local)
                } else if local.updatedAt > remote.updatedAt {
                    result.append(local)
                } else if remote.updatedAt > local.updatedAt {
                    result.append(remote)
                } else {
                    result.append(local)
                    conflicts.append(Conflict(
                        bundleId: serverId,
                        serverName: local.name,
                        localVersion: local,
                        remoteVersion: remote,
                        resolution: .unresolved
                    ))
                }
            } else if let local = localServer {
                result.append(local)
            } else if let remote = remoteServer {
                result.append(remote)
            }
        }

        return (result, conflicts)
    }

    /// Check if a server has missing secrets on this device.
    static func hasMissingSecrets(
        server: MCPServerDefinition,
        bundleId: UUID,
        keychainService: KeychainService
    ) -> Bool {
        guard !server.secretEnvKeys.isEmpty else { return false }

        for key in server.secretEnvKeys {
            if keychainService.readMCPSecret(
                bundleId: bundleId,
                serverId: server.id,
                envKey: key
            ) == nil {
                return true
            }
        }
        return false
    }
}
