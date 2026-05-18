import Foundation

/// Result of syncing to a single client.
struct MCPSyncResult: Sendable {
    let client: MCPClientKind
    let success: Bool
    let serversWritten: Int
    let error: String?
    let warnings: [String]
    let durationMs: Int

    init(
        client: MCPClientKind,
        success: Bool,
        serversWritten: Int = 0,
        error: String? = nil,
        warnings: [String] = [],
        durationMs: Int = 0
    ) {
        self.client = client
        self.success = success
        self.serversWritten = serversWritten
        self.error = error
        self.warnings = warnings
        self.durationMs = durationMs
    }
}
