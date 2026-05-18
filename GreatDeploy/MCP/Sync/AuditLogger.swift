import Foundation
import os.log

/// Audit logger for MCP sync operations.
/// Appends to ~/Library/Logs/GreatDeploy/mcp-audit.log
/// SECURITY: NO secret values are logged — only server names and env key names.
@MainActor
final class AuditLogger {
    static let shared = AuditLogger()

    private let logFile: URL
    private let queue = DispatchQueue(label: "com.greatdeploy.mcp-audit")

    init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GreatDeploy")
        if !FileManager.default.fileExists(atPath: logsDir.path) {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        self.logFile = logsDir.appendingPathComponent("mcp-audit.log")
    }

    func logSyncSuccess(client: MCPClientKind, bundle: MCPBundle, serverCount: Int, durationMs: Int) {
        let entry = AuditEntry(
            timestamp: Date(),
            type: "sync_success",
            clientId: client.rawValue,
            bundleId: bundle.id.uuidString,
            bundleName: bundle.name,
            serverCount: serverCount,
            durationMs: durationMs,
            details: nil
        )
        append(entry)
    }

    func logSyncFailure(client: MCPClientKind, bundle: MCPBundle, error: String) {
        let entry = AuditEntry(
            timestamp: Date(),
            type: "sync_failure",
            clientId: client.rawValue,
            bundleId: bundle.id.uuidString,
            bundleName: bundle.name,
            serverCount: 0,
            durationMs: 0,
            details: error
        )
        append(entry)
    }

    func logServerAdded(bundle: MCPBundle, server: MCPServerDefinition) {
        let entry = AuditEntry(
            timestamp: Date(),
            type: "server_added",
            clientId: nil,
            bundleId: bundle.id.uuidString,
            bundleName: bundle.name,
            serverCount: 0,
            durationMs: 0,
            details: "Server: \(server.name), Transport: \(server.transport.rawValue)"
        )
        append(entry)
    }

    func logServerRemoved(bundle: MCPBundle, serverName: String) {
        let entry = AuditEntry(
            timestamp: Date(),
            type: "server_removed",
            clientId: nil,
            bundleId: bundle.id.uuidString,
            bundleName: bundle.name,
            serverCount: 0,
            durationMs: 0,
            details: "Server: \(serverName)"
        )
        append(entry)
    }

    private func append(_ entry: AuditEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let line = entry.toLogLine() + "\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFile.path) {
                    if let handle = try? FileHandle(forUpdating: self.logFile) {
                        handle.seekToEndOfFile()
                        try? handle.write(contentsOf: data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logFile)
                }
            }
        }
    }
}

struct AuditEntry: Sendable {
    let timestamp: Date
    let type: String
    let clientId: String?
    let bundleId: String
    let bundleName: String
    let serverCount: Int
    let durationMs: Int
    let details: String?

    func toLogLine() -> String {
        let ts = ISO8601DateFormatter().string(from: timestamp)
        var parts = [ts, type, "bundle=\(bundleId)", "name=\(bundleName)"]
        if let clientId = clientId { parts.append("client=\(clientId)") }
        if serverCount > 0 { parts.append("servers=\(serverCount)") }
        if durationMs > 0 { parts.append("duration=\(durationMs)ms") }
        if let details = details { parts.append("details=\(details)") }
        return parts.joined(separator: " | ")
    }
}
