import Foundation

/// Per-client sync state. Tracks what has been synced for orphan detection.
struct MCPSyncState: Codable, Equatable, Hashable, Sendable {
    let clientId: MCPClientKind
    var lastSyncedAt: Date?
    var lastSyncedServerNames: [String]
    var previouslySyncedNames: Set<String>

    init(
        clientId: MCPClientKind,
        lastSyncedAt: Date? = nil,
        lastSyncedServerNames: [String] = [],
        previouslySyncedNames: Set<String> = []
    ) {
        self.clientId = clientId
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncedServerNames = lastSyncedServerNames
        self.previouslySyncedNames = previouslySyncedNames
    }
}
