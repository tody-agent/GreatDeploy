import Foundation

/// Sync manifest for Merkle-tree based sync.
public struct SyncManifest: Codable, Equatable, Sendable {
    let machineId: String
    let timestamp: Date
    let entries: [Entry]
    let signature: String

    struct Entry: Codable, Equatable, Sendable {
        let id: String
        let hash: String
        let timestamp: Date
    }

    init(machineId: String, timestamp: Date = Date(), entries: [Entry] = [], signature: String = "") {
        self.machineId = machineId
        self.timestamp = timestamp
        self.entries = entries
        self.signature = signature
    }
}
