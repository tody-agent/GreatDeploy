import Foundation
import AppKit
import os.log

/// Service for managing MCP server configurations across multiple tools.
final class MCPConfigService: MCPConfigServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "MCPConfig")
    static let shared = MCPConfigService()
    private let fileSystem: FileSystem

    init(fileSystem: FileSystem = MacFileSystem.shared) {
        self.fileSystem = fileSystem
    }

    var claudeDesktopConfigPath: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json") }

    func isClaudeDesktopRunning() -> Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.anthropic.claudefordesktop" } }

    func readClaudeDesktopConfig() throws -> [String: Any] {
        let path = claudeDesktopConfigPath
        guard fileSystem.exists(path) else { return [:] }
        guard let data = try fileSystem.readData(from: path) else { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func writeClaudeDesktopConfig(_ config: [String: Any]) throws {
        let path = claudeDesktopConfigPath
        if isClaudeDesktopRunning() { Self.logger.warning("Claude Desktop is running — config changes may require restart") }
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let dir = path.deletingLastPathComponent()
        if !fileSystem.exists(dir) { try fileSystem.createDirectory(at: dir) }
        try fileSystem.atomicWrite(data, to: path)
    }

    func getMCPServers() throws -> [MCPServerConfig] {
        let config = try readClaudeDesktopConfig()
        guard let servers = config["mcpServers"] as? [String: [String: Any]] else { return [] }
        return servers.map { name, serverConfig in MCPServerConfig(name: name, command: serverConfig["command"] as? String ?? "", args: serverConfig["args"] as? [String] ?? [], env: serverConfig["env"] as? [String: String] ?? [:]) }
    }

    func setMCPServer(_ server: MCPServerConfig) throws {
        var config = try readClaudeDesktopConfig()
        var servers = config["mcpServers"] as? [String: [String: Any]] ?? [:]
        var serverDict: [String: Any] = ["command": server.command, "args": server.args]
        if !server.env.isEmpty { serverDict["env"] = server.env }
        servers[server.name] = serverDict
        config["mcpServers"] = servers
        try writeClaudeDesktopConfig(config)
    }

    func removeMCPServer(named name: String) throws {
        var config = try readClaudeDesktopConfig()
        var servers = config["mcpServers"] as? [String: [String: Any]] ?? [:]
        servers.removeValue(forKey: name)
        config["mcpServers"] = servers
        try writeClaudeDesktopConfig(config)
    }

    func readProjectMCPConfig(at projectDir: URL) throws -> [String: Any] {
        let path = projectDir.appendingPathComponent(".mcp.json")
        guard fileSystem.exists(path) else { return [:] }
        guard let data = try fileSystem.readData(from: path) else { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func writeProjectMCPConfig(_ config: [String: Any], at projectDir: URL) throws {
        let path = projectDir.appendingPathComponent(".mcp.json")
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try fileSystem.atomicWrite(data, to: path)
    }
}

struct MCPServerConfig: Identifiable, Codable, Equatable {
    var id: String { name }
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]
}
