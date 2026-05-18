import Foundation

/// Adapter for Claude Desktop MCP configuration.
/// Config path: ~/Library/Application Support/Claude/claude_desktop_config.json
struct ClaudeDesktopAdapter: MCPClientAdapter {
    let kind: MCPClientKind = .claudeDesktop
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
        let appURL = URL(fileURLWithPath: "/Applications/Claude.app")
        return FileManager.default.fileExists(atPath: appURL.path)
    }

    func configPath() -> URL? {
        overrideConfigPath ?? MCPClientKind.claudeDesktop.configPath
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
