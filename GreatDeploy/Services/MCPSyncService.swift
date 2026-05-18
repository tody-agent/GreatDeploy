import Foundation
import os.log

/// Orchestrates syncing MCP server configs from master registry to each AI tool.
final class MCPSyncService: MCPSyncServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "MCPSync")
    private let registry = MCPRegistry.shared
    private let discovery = ToolDiscoveryService.shared
    static let shared = MCPSyncService()
    private init() {}

    struct SyncResult: Sendable { let serverName: String; let tool: AITool; let success: Bool; let error: String?; let syncedAt: Date }
    struct BatchSyncResult: Sendable { let results: [SyncResult]; var successCount: Int { results.filter { $0.success }.count }; var failureCount: Int { results.filter { !$0.success }.count }; var totalCount: Int { results.count } }

    func syncServerToTool(serverName: String, tool: AITool) throws -> SyncResult {
        guard tool.supportsMCP else { return SyncResult(serverName: serverName, tool: tool, success: false, error: "Tool does not support MCP", syncedAt: Date()) }
        guard discovery.installedTools().contains(tool) else {
            registry.updateSyncRecord(for: serverName, tool: tool, record: ToolSyncRecord(tool: tool, status: .toolNotInstalled))
            return SyncResult(serverName: serverName, tool: tool, success: false, error: "Tool not installed", syncedAt: Date())
        }
        guard let masterServer = try registry.getMasterServer(name: serverName) else {
            return SyncResult(serverName: serverName, tool: tool, success: false, error: "Server not found", syncedAt: Date())
        }
        do {
            try writeServerToTool(masterServer.config, tool: tool)
            registry.updateSyncRecord(for: serverName, tool: tool, record: ToolSyncRecord(tool: tool, status: .synced, lastSyncedAt: Date()))
            return SyncResult(serverName: serverName, tool: tool, success: true, error: nil, syncedAt: Date())
        } catch {
            registry.updateSyncRecord(for: serverName, tool: tool, record: ToolSyncRecord(tool: tool, status: .error, lastError: error.localizedDescription))
            return SyncResult(serverName: serverName, tool: tool, success: false, error: error.localizedDescription, syncedAt: Date())
        }
    }

    func syncAllServersToAllTools() -> BatchSyncResult {
        guard let servers = try? registry.listMasterServers() else { return BatchSyncResult(results: []) }
        let tools = discovery.installedMCPCapableTools()
        var allResults: [SyncResult] = []
        for server in servers { for tool in tools { if let result = try? syncServerToTool(serverName: server.name, tool: tool) { allResults.append(result) } } }
        return BatchSyncResult(results: allResults)
    }

    func syncAllServersToTool(tool: AITool) -> BatchSyncResult {
        guard let servers = try? registry.listMasterServers() else { return BatchSyncResult(results: []) }
        let results = servers.compactMap { try? syncServerToTool(serverName: $0.name, tool: tool) }
        return BatchSyncResult(results: results)
    }

    func pullServersFromTool(_ tool: AITool) throws -> [RegisteredMCPServer] {
        let configs = try readToolMCPServers(tool)
        var imported: [RegisteredMCPServer] = []
        for config in configs { imported.append(try registry.importFromTool(config: config, from: tool)) }
        return imported
    }

    private func readToolMCPServers(_ tool: AITool) throws -> [MCPServerConfig] {
        guard let configPath = tool.mcpConfigPath else { return [] }
        guard FileManager.default.fileExists(atPath: configPath.path) else { return [] }
        let data = try Data(contentsOf: configPath)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let serversDict = json["mcpServers"] as? [String: [String: Any]] ?? [:]
        return serversDict.map { name, serverConfig in
            MCPServerConfig(name: name, command: serverConfig["command"] as? String ?? "", args: serverConfig["args"] as? [String] ?? [], env: serverConfig["env"] as? [String: String] ?? [:])
        }
    }

    private func writeServerToTool(_ config: MCPServerConfig, tool: AITool) throws {
        guard let configPath = tool.mcpConfigPath else { throw MCPSyncError.toolNotCapable(tool.displayName) }
        var existingConfig: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: configPath.path), let data = try? Data(contentsOf: configPath), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { existingConfig = json }
        var servers = existingConfig["mcpServers"] as? [String: [String: Any]] ?? [:]
        var serverDict: [String: Any] = ["command": config.command, "args": config.args]
        if !config.env.isEmpty { serverDict["env"] = config.env }
        servers[config.name] = serverDict
        existingConfig["mcpServers"] = servers
        let dir = configPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let data = try JSONSerialization.data(withJSONObject: existingConfig, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configPath, options: .atomic)
    }

    enum MCPSyncError: LocalizedError { case toolNotCapable(String), writeFailed(String); var errorDescription: String? { switch self { case .toolNotCapable(let t): return "\(t) does not support MCP"; case .writeFailed(let d): return "Failed to write: \(d)" } } }
}
