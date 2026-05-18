import Foundation

/// Pure merge function for MCP servers.
/// This is the core logic that determines which servers end up in a client's config.
///
/// Merge formula: final = (existing ∖ previouslySyncedNames) ∪ servers
///
/// - existing: servers currently in the client's config
/// - servers: servers from the bundle (what we want to sync)
/// - previouslySyncedNames: cumulative set of ALL names we've ever synced to this client
///
/// Behavior:
/// 1. User-added servers (name NOT in previouslySyncedNames) → PRESERVED
/// 2. Bundle servers (in `servers`) → ADDED/OVERWRITTEN
/// 3. Orphan servers (name in previouslySyncedNames but NOT in `servers`) → REMOVED
///
/// Case-insensitive name matching for all comparisons.
enum JSONMerger {

    /// Merge servers into existing config.
    /// - Parameters:
    ///   - existingServers: Current servers in the client config (by name)
    ///   - bundleServers: Servers from the bundle to sync
    ///   - previouslySyncedNames: Cumulative set of all names ever synced
    /// - Returns: Merged server dictionary (name → server)
    static func merge(
        existingServers: [String: MCPServerDefinition],
        bundleServers: [MCPServerDefinition],
        previouslySyncedNames: Set<String>
    ) -> [String: MCPServerDefinition] {
        let bundleDict = Dictionary(uniqueKeysWithValues: bundleServers.map { ($0.name.lowercased(), $0) })
        let prevSyncedLower = Set(previouslySyncedNames.map { $0.lowercased() })

        var result: [String: MCPServerDefinition] = [:]

        for (name, server) in existingServers {
            let nameLower = name.lowercased()
            if !prevSyncedLower.contains(nameLower) {
                result[name] = server
            }
        }

        for (nameLower, server) in bundleDict {
            result[nameLower] = server
        }

        return result
    }

    /// Calculate which servers will be removed (orphans).
    /// Useful for audit logging and user notifications.
    static func orphanNames(
        existingServers: [String: MCPServerDefinition],
        bundleServers: [MCPServerDefinition],
        previouslySyncedNames: Set<String>
    ) -> Set<String> {
        let bundleNamesLower = Set(bundleServers.map { $0.name.lowercased() })
        let prevSyncedLower = Set(previouslySyncedNames.map { $0.lowercased() })

        var orphans: Set<String> = []
        for name in existingServers.keys {
            let nameLower = name.lowercased()
            if prevSyncedLower.contains(nameLower) && !bundleNamesLower.contains(nameLower) {
                orphans.insert(name)
            }
        }
        return orphans
    }

    /// Calculate which servers are user-added (not managed by us).
    static func userAddedNames(
        existingServers: [String: MCPServerDefinition],
        previouslySyncedNames: Set<String>
    ) -> Set<String> {
        let prevSyncedLower = Set(previouslySyncedNames.map { $0.lowercased() })
        return Set(existingServers.keys.filter { !prevSyncedLower.contains($0.lowercased()) })
    }
}
