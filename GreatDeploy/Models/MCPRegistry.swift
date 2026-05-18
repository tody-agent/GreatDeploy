import Foundation
import os.log

/// Master registry for MCP servers across all AI tools.
final class MCPRegistry: MCPRegistryServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "MCPRegistry")
    static let shared = MCPRegistry()
    private init() {}

    var masterMCPDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".greatdeploy/mcp")
    }

    var masterConfigPath: URL { masterMCPDirectory.appendingPathComponent("servers.json") }

    private func ensureMasterDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: masterMCPDirectory.path) { try fm.createDirectory(at: masterMCPDirectory, withIntermediateDirectories: true) }
    }

    func listMasterServers() throws -> [RegisteredMCPServer] {
        try ensureMasterDirectory()
        guard FileManager.default.fileExists(atPath: masterConfigPath.path) else { return [] }
        let data = try Data(contentsOf: masterConfigPath)
        let configs = try JSONDecoder().decode([String: MCPServerConfig].self, from: data)
        return configs.map { name, config in
            RegisteredMCPServer(name: name, config: config, syncRecords: loadSyncRecords(for: name))
        }.sorted { $0.name < $1.name }
    }

    func getMasterServer(name: String) throws -> RegisteredMCPServer? {
        try listMasterServers().first { $0.name == name }
    }

    func installServer(_ config: MCPServerConfig) throws -> RegisteredMCPServer {
        try ensureMasterDirectory()
        var configs = try readMasterConfigs()
        configs[config.name] = config
        try writeMasterConfigs(configs)
        return RegisteredMCPServer(name: config.name, config: config, syncRecords: [:])
    }

    func updateServer(_ config: MCPServerConfig) throws {
        var configs = try readMasterConfigs()
        guard configs[config.name] != nil else { throw MCPRegistryError.serverNotFound(config.name) }
        configs[config.name] = config
        try writeMasterConfigs(configs)
    }

    func deleteServer(name: String) throws {
        var configs = try readMasterConfigs()
        guard configs[name] != nil else { throw MCPRegistryError.serverNotFound(name) }
        configs.removeValue(forKey: name)
        try writeMasterConfigs(configs)
        deleteSyncRecords(for: name)
    }

    func importFromTool(config: MCPServerConfig, from tool: AITool) throws -> RegisteredMCPServer {
        if let existing = try getMasterServer(name: config.name) {
            if existing.config != config { try updateServer(config) }
            return try getMasterServer(name: config.name)!
        }
        return try installServer(config)
    }

    func updateSyncRecord(for serverName: String, tool: AITool, record: ToolSyncRecord) {
        var records = loadSyncRecords(for: serverName)
        records[tool] = record
        saveSyncRecords(records, for: serverName)
    }

    func saveSyncRecords(_ records: [AITool: ToolSyncRecord], for serverName: String) {
        let metaPath = masterMCPDirectory.appendingPathComponent("\(serverName).sync-meta.json")
        var dict: [String: ToolSyncRecord] = [:]
        for (tool, record) in records { dict[tool.rawValue] = record }
        if let data = try? JSONEncoder().encode(dict) { try? data.write(to: metaPath, options: .atomic) }
    }

    func readMasterConfigs() throws -> [String: MCPServerConfig] {
        guard FileManager.default.fileExists(atPath: masterConfigPath.path) else { return [:] }
        let data = try Data(contentsOf: masterConfigPath)
        return try JSONDecoder().decode([String: MCPServerConfig].self, from: data)
    }

    func writeMasterConfigs(_ configs: [String: MCPServerConfig]) throws {
        let data = try JSONEncoder().encode(configs)
        try data.write(to: masterConfigPath, options: .atomic)
    }

    private func loadSyncRecords(for serverName: String) -> [AITool: ToolSyncRecord] {
        let metaPath = masterMCPDirectory.appendingPathComponent("\(serverName).sync-meta.json")
        guard FileManager.default.fileExists(atPath: metaPath.path), let data = try? Data(contentsOf: metaPath), let records = try? JSONDecoder().decode([String: ToolSyncRecord].self, from: data) else { return [:] }
        var result: [AITool: ToolSyncRecord] = [:]
        for (key, record) in records { if let tool = AITool(rawValue: key) { result[tool] = record } }
        return result
    }

    private func deleteSyncRecords(for serverName: String) {
        let metaPath = masterMCPDirectory.appendingPathComponent("\(serverName).sync-meta.json")
        try? FileManager.default.removeItem(at: metaPath)
    }

    enum MCPRegistryError: LocalizedError {
        case serverNotFound(String), writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .serverNotFound(let name): return "MCP server '\(name)' not found"
            case .writeFailed(let detail): return "Failed to write MCP config: \(detail)"
            }
        }
    }
}

public struct RegisteredMCPServer: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    let config: MCPServerConfig
    public var syncRecords: [AITool: ToolSyncRecord]

    public func syncStatus(for tool: AITool) -> SyncStatus { syncRecords[tool]?.status ?? .neverSynced }
    public var isFullySynced: Bool {
        let installed = ToolDiscoveryService.shared.installedMCPCapableTools()
        return installed.allSatisfy { syncStatus(for: $0) == .synced }
    }
}
