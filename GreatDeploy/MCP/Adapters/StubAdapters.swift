import Foundation
import AppKit

/// Adapter for VS Code MCP configuration.
/// Config path: ~/Library/Application Support/Code/User/settings.json
/// MCP servers stored under nested key: mcp → servers
struct VSCodeAdapter: MCPClientAdapter {
    let kind: MCPClientKind = .vscode
    var displayName: String { kind.displayName }

    private let fileSystem: FileSystem
    private let overrideConfigPath: URL?

    init(fileSystem: FileSystem = MacFileSystem.shared, overrideConfigPath: URL? = nil) {
        self.fileSystem = fileSystem
        self.overrideConfigPath = overrideConfigPath
    }

    func detect() -> Bool {
        if overrideConfigPath != nil {
            return configPath().map { fileSystem.exists($0) } ?? false
        }
        if let configPath = configPath() {
            return fileSystem.exists(configPath) || fileSystem.exists(configPath.deletingLastPathComponent())
        }
        let appURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        return FileManager.default.fileExists(atPath: appURL.path)
    }

    func configPath() -> URL? {
        overrideConfigPath ?? MCPClientKind.vscode.configPath
    }

    func readServers() throws -> [MCPServerDefinition] {
        guard let path = configPath(),
              let data = try fileSystem.readData(from: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return try JSONAdapterHelpers.parseServers(from: content, keyPath: ["mcp", "servers"])
    }

    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws {
        guard let path = configPath() else {
            throw MCPAdapterError.configPathUnavailable
        }

        let parentDir = path.deletingLastPathComponent()
        if !fileSystem.exists(parentDir) {
            try fileSystem.createDirectory(at: parentDir)
        }

        let output = try JSONAdapterHelpers.serializeServers(
            servers,
            existingContent: existingContent,
            previouslySyncedNames: previouslySyncedNames,
            keyPath: ["mcp", "servers"]
        )

        guard let data = output.data(using: .utf8) else {
            throw MCPAdapterError.serializationFailed
        }

        try fileSystem.atomicWrite(data, to: path)
    }
}

/// Adapter for Claude Code MCP configuration.
/// Config path: ~/.claude/settings.json
/// MCP servers stored under key: mcpServers
struct ClaudeCodeAdapter: MCPClientAdapter {
    let kind: MCPClientKind = .claudeCode
    var displayName: String { kind.displayName }

    private let fileSystem: FileSystem
    private let overrideConfigPath: URL?

    init(fileSystem: FileSystem = MacFileSystem.shared, overrideConfigPath: URL? = nil) {
        self.fileSystem = fileSystem
        self.overrideConfigPath = overrideConfigPath
    }

    func detect() -> Bool {
        if overrideConfigPath != nil {
            return configPath().map { fileSystem.exists($0) } ?? false
        }
        if let configPath = configPath() {
            return fileSystem.exists(configPath) || fileSystem.exists(configPath.deletingLastPathComponent())
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude")
        return FileManager.default.fileExists(atPath: claudeDir.path)
    }

    func configPath() -> URL? {
        overrideConfigPath ?? MCPClientKind.claudeCode.configPath
    }

    func readServers() throws -> [MCPServerDefinition] {
        guard let path = configPath(),
              let data = try fileSystem.readData(from: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return try JSONAdapterHelpers.parseServers(from: content)
    }

    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws {
        guard let path = configPath() else {
            throw MCPAdapterError.configPathUnavailable
        }

        let parentDir = path.deletingLastPathComponent()
        if !fileSystem.exists(parentDir) {
            try fileSystem.createDirectory(at: parentDir)
        }

        let output = try JSONAdapterHelpers.serializeServers(
            servers,
            existingContent: existingContent,
            previouslySyncedNames: previouslySyncedNames
        )

        guard let data = output.data(using: .utf8) else {
            throw MCPAdapterError.serializationFailed
        }

        try fileSystem.atomicWrite(data, to: path)
    }
}

/// Adapter for Windsurf MCP configuration.
/// Config path: ~/.codeium/windsurf/mcp_config.json
/// MCP servers stored under key: mcpServers (standard JSON format).
struct WindsurfAdapter: MCPClientAdapter {
    let kind: MCPClientKind = .windsurf
    var displayName: String { kind.displayName }

    private let fileSystem: FileSystem
    private let overrideConfigPath: URL?

    init(fileSystem: FileSystem = MacFileSystem.shared, overrideConfigPath: URL? = nil) {
        self.fileSystem = fileSystem
        self.overrideConfigPath = overrideConfigPath
    }

    func detect() -> Bool {
        if overrideConfigPath != nil {
            return configPath().map { fileSystem.exists($0) } ?? false
        }
        if let configPath = configPath() {
            return fileSystem.exists(configPath) || fileSystem.exists(configPath.deletingLastPathComponent())
        }
        let appURL = URL(fileURLWithPath: "/Applications/Windsurf.app")
        return FileManager.default.fileExists(atPath: appURL.path)
            || MCPClientKind.windsurf.bundleIdentifier.map {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            } ?? false
    }

    func configPath() -> URL? {
        overrideConfigPath ?? MCPClientKind.windsurf.configPath
    }

    func readServers() throws -> [MCPServerDefinition] {
        guard let path = configPath(),
              let data = try fileSystem.readData(from: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return try JSONAdapterHelpers.parseServers(from: content)
    }

    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws {
        guard let path = configPath() else {
            throw MCPAdapterError.configPathUnavailable
        }

        let parentDir = path.deletingLastPathComponent()
        if !fileSystem.exists(parentDir) {
            try fileSystem.createDirectory(at: parentDir)
        }

        let output = try JSONAdapterHelpers.serializeServers(
            servers,
            existingContent: existingContent,
            previouslySyncedNames: previouslySyncedNames
        )

        guard let data = output.data(using: .utf8) else {
            throw MCPAdapterError.serializationFailed
        }

        try fileSystem.atomicWrite(data, to: path)
    }
}

/// Adapter for Zed MCP configuration.
/// Config path: ~/.config/zed/settings.json
/// MCP servers stored under key: context_servers (flat command structure).
struct ZedAdapter: MCPClientAdapter {
    let kind: MCPClientKind = .zed
    var displayName: String { kind.displayName }

    private let fileSystem: FileSystem
    private let overrideConfigPath: URL?

    init(fileSystem: FileSystem = MacFileSystem.shared, overrideConfigPath: URL? = nil) {
        self.fileSystem = fileSystem
        self.overrideConfigPath = overrideConfigPath
    }

    func detect() -> Bool {
        if overrideConfigPath != nil {
            return configPath().map { fileSystem.exists($0) } ?? false
        }
        if let configPath = configPath() {
            return fileSystem.exists(configPath) || fileSystem.exists(configPath.deletingLastPathComponent())
        }
        let appURL = URL(fileURLWithPath: "/Applications/Zed.app")
        return FileManager.default.fileExists(atPath: appURL.path)
            || MCPClientKind.zed.bundleIdentifier.map {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            } ?? false
    }

    func configPath() -> URL? {
        overrideConfigPath ?? MCPClientKind.zed.configPath
    }

    func readServers() throws -> [MCPServerDefinition] {
        guard let path = configPath(),
              let data = try fileSystem.readData(from: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return try JSONAdapterHelpers.parseServers(from: content, keyPath: ["context_servers"])
    }

    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws {
        guard let path = configPath() else {
            throw MCPAdapterError.configPathUnavailable
        }

        let parentDir = path.deletingLastPathComponent()
        if !fileSystem.exists(parentDir) {
            try fileSystem.createDirectory(at: parentDir)
        }

        let output = try JSONAdapterHelpers.serializeServers(
            servers,
            existingContent: existingContent,
            previouslySyncedNames: previouslySyncedNames,
            keyPath: ["context_servers"]
        )

        guard let data = output.data(using: .utf8) else {
            throw MCPAdapterError.serializationFailed
        }

        try fileSystem.atomicWrite(data, to: path)
    }
}

/// Adapter for JetBrains IDE MCP configuration.
/// Config path: ~/Library/Application Support/JetBrains/<IDE><version>/options/mcp.xml
/// Uses XML format (not JSON) for server configuration.
struct JetBrainsAdapter: MCPClientAdapter {
    let kind: MCPClientKind = .jetbrains
    var displayName: String { kind.displayName }

    private let fileSystem: FileSystem
    private let overrideConfigPath: URL?

    init(fileSystem: FileSystem = MacFileSystem.shared, overrideConfigPath: URL? = nil) {
        self.fileSystem = fileSystem
        self.overrideConfigPath = overrideConfigPath
    }

    private let idePrefixes = [
        "IntelliJIdea", "WebStorm", "PyCharm", "GoLand",
        "RustRover", "CLion", "Rider", "PhpStorm", "DataGrip",
    ]

    func detect() -> Bool {
        if overrideConfigPath != nil {
            return configPath().map { fileSystem.exists($0) } ?? false
        }
        let jetbrainsDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/JetBrains")
        guard fileSystem.exists(jetbrainsDir) else { return false }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: jetbrainsDir,
            includingPropertiesForKeys: nil
        )) ?? []

        for ideDir in contents {
            let mcpXml = ideDir.appendingPathComponent("options/mcp.xml")
            if FileManager.default.fileExists(atPath: mcpXml.path) {
                return true
            }
        }
        return false
    }

    func configPath() -> URL? {
        if let override = overrideConfigPath {
            return override
        }

        let jetbrainsDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/JetBrains")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: jetbrainsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return nil
        }

        var candidates: [(URL, String, Int)] = []

        for ideDir in contents {
            let name = ideDir.lastPathComponent
            for prefix in idePrefixes {
                if name.hasPrefix(prefix) {
                    let versionPart = String(name.dropFirst(prefix.count))
                    let version = extractVersion(versionPart)
                    let mcpXml = ideDir.appendingPathComponent("options/mcp.xml")
                    if FileManager.default.fileExists(atPath: mcpXml.path) {
                        candidates.append((mcpXml, prefix, version))
                    }
                }
            }
        }

        candidates.sort { a, b in
            if a.1 == b.1 {
                return a.2 > b.2
            }
            return idePrefixes.firstIndex(of: a.1)! < idePrefixes.firstIndex(of: b.1)!
        }

        return candidates.first?.0
    }

    private func extractVersion(_ s: String) -> Int {
        let digits = s.prefix { $0.isNumber || $0 == "." }
        let parts = String(digits).split(separator: ".").compactMap { Int($0) }
        if parts.count >= 2 {
            return parts[0] * 100 + parts[1]
        }
        return parts.first ?? 0
    }

    func readServers() throws -> [MCPServerDefinition] {
        guard let path = configPath(),
              let data = try fileSystem.readData(from: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return try XMLSerializer.parse(content)
    }

    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws {
        guard let path = configPath() else {
            throw MCPAdapterError.configPathUnavailable
        }

        let parentDir = path.deletingLastPathComponent()
        if !fileSystem.exists(parentDir) {
            try fileSystem.createDirectory(at: parentDir)
        }

        let existingNames: Set<String>
        if let existing = existingContent {
            let existingServers = (try? XMLSerializer.parse(existing)) ?? []
            existingNames = Set(existingServers.map(\.name))
        } else {
            existingNames = []
        }

        let userAddedNames = existingNames.subtracting(previouslySyncedNames)
        let orphanNames = previouslySyncedNames.subtracting(servers.map(\.name))
        let preservedNames = userAddedNames.subtracting(orphanNames)

        var existingServers = (try? XMLSerializer.parse(existingContent ?? "")) ?? []
        var preservedServers = existingServers.filter { preservedNames.contains($0.name) }

        var finalServers: [MCPServerDefinition] = []
        var addedNames = Set<String>()

        for server in servers {
            if let idx = preservedServers.firstIndex(where: { $0.name == server.name }) {
                preservedServers.remove(at: idx)
            }
            finalServers.append(server)
            addedNames.insert(server.name)
        }

        for preserved in preservedServers where !addedNames.contains(preserved.name) {
            finalServers.append(preserved)
        }

        let output = XMLSerializer.serialize(finalServers)

        guard let data = output.data(using: .utf8) else {
            throw MCPAdapterError.serializationFailed
        }

        try fileSystem.atomicWrite(data, to: path)
    }
}

/// Adapter for Codex CLI MCP configuration.
/// Config path: ~/.codex/config.toml
/// Uses TOML format: [mcp_servers.name] with command, args, env.
struct CodexAdapter: MCPClientAdapter {
    let kind: MCPClientKind = .codex
    var displayName: String { kind.displayName }

    private let fileSystem: FileSystem
    private let overrideConfigPath: URL?

    init(fileSystem: FileSystem = MacFileSystem.shared, overrideConfigPath: URL? = nil) {
        self.fileSystem = fileSystem
        self.overrideConfigPath = overrideConfigPath
    }

    func detect() -> Bool {
        if overrideConfigPath != nil {
            return configPath().map { fileSystem.exists($0) } ?? false
        }
        if let configPath = configPath() {
            return fileSystem.exists(configPath) || fileSystem.exists(configPath.deletingLastPathComponent())
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexDir = home.appendingPathComponent(".codex")
        return FileManager.default.fileExists(atPath: codexDir.path)
    }

    func configPath() -> URL? {
        overrideConfigPath ?? MCPClientKind.codex.configPath
    }

    func readServers() throws -> [MCPServerDefinition] {
        guard let path = configPath(),
              let data = try fileSystem.readData(from: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return try TOMLSerializer.parse(content)
    }

    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws {
        guard let path = configPath() else {
            throw MCPAdapterError.configPathUnavailable
        }

        let parentDir = path.deletingLastPathComponent()
        if !fileSystem.exists(parentDir) {
            try fileSystem.createDirectory(at: parentDir)
        }

        // Parse existing servers to preserve user-added ones
        var existingServers: [MCPServerDefinition] = []
        if let existingContent, !existingContent.isEmpty {
            existingServers = (try? TOMLSerializer.parse(existingContent)) ?? []
        }

        // Compute preserved (user-added) servers
        var preservedServers: [MCPServerDefinition] = []
        for existing in existingServers {
            let matchedPreviously = previouslySyncedNames.contains { $0.caseInsensitiveCompare(existing.name) == .orderedSame }
            if !matchedPreviously {
                preservedServers.append(existing)
            }
        }

        // Merge: preserved + bundle (bundle overwrites on conflict)
        var mergedDict: [String: MCPServerDefinition] = Dictionary(uniqueKeysWithValues: preservedServers.map { ($0.name, $0) })
        for server in servers {
            mergedDict[server.name] = server
        }

        let mergedServers = Array(mergedDict.values)
        let output = TOMLSerializer.serialize(mergedServers)

        guard let data = output.data(using: .utf8) else {
            throw MCPAdapterError.serializationFailed
        }

        try fileSystem.atomicWrite(data, to: path)
    }
}

/// Adapter for Antigravity MCP configuration.
/// Config path: .antigravity/config.json (project-level, relative to home).
/// MCP servers stored under key: mcpServers (standard JSON format).
struct AntigravityAdapter: MCPClientAdapter {
    let kind: MCPClientKind = .antigravity
    var displayName: String { kind.displayName }

    private let fileSystem: FileSystem
    private let overrideConfigPath: URL?

    init(fileSystem: FileSystem = MacFileSystem.shared, overrideConfigPath: URL? = nil) {
        self.fileSystem = fileSystem
        self.overrideConfigPath = overrideConfigPath
    }

    func detect() -> Bool {
        if overrideConfigPath != nil {
            return configPath().map { fileSystem.exists($0) } ?? false
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let homeAntigravity = home.appendingPathComponent(".antigravity")
        if fileSystem.exists(homeAntigravity) {
            return true
        }
        let cwdAntigravity = FileManager.default.currentDirectoryPath.appending("/.antigravity")
        if FileManager.default.fileExists(atPath: cwdAntigravity) {
            return true
        }
        return false
    }

    func configPath() -> URL? {
        overrideConfigPath ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity/config.json")
    }

    func readServers() throws -> [MCPServerDefinition] {
        guard let path = configPath(),
              let data = try fileSystem.readData(from: path),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return try JSONAdapterHelpers.parseServers(from: content)
    }

    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws {
        guard let path = configPath() else {
            throw MCPAdapterError.configPathUnavailable
        }

        let parentDir = path.deletingLastPathComponent()
        if !fileSystem.exists(parentDir) {
            try fileSystem.createDirectory(at: parentDir)
        }

        let output = try JSONAdapterHelpers.serializeServers(
            servers,
            existingContent: existingContent,
            previouslySyncedNames: previouslySyncedNames
        )

        guard let data = output.data(using: .utf8) else {
            throw MCPAdapterError.serializationFailed
        }

        try fileSystem.atomicWrite(data, to: path)
    }
}
