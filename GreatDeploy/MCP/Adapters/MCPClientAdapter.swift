import Foundation

/// Protocol for MCP client adapters that can detect, read from, and write to
/// different AI coding tool configurations.
protocol MCPClientAdapter: Sendable {
    /// The client kind this adapter handles.
    var kind: MCPClientKind { get }

    /// Human-readable display name.
    var displayName: String { get }

    /// Check if this client is installed (config dir or app bundle exists).
    func detect() -> Bool

    /// Return the path to this client's MCP config file.
    func configPath() -> URL?

    /// Read MCP server configurations from this client's config.
    func readServers() throws -> [MCPServerDefinition]

    /// Write MCP server configurations to this client's config.
    /// - Parameters:
    ///   - servers: The servers to write (from the bundle).
    ///   - existingContent: Current file content (captured before write for rollback).
    ///   - previouslySyncedNames: Cumulative set of ALL server names ever synced to this client.
    ///     Used to distinguish user-added servers from managed orphans.
    ///
    /// Merge formula: final = (existing ∖ previouslySyncedNames) ∪ servers
    /// - User-added servers (not in previouslySyncedNames) are preserved.
    /// - Orphan servers (in previouslySyncedNames but not in servers) are removed.
    /// - Bundle servers overwrite any existing server with the same name.
    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws
}

/// Extension to create adapters from MCPClientKind.
extension MCPClientKind {
    /// Returns the appropriate adapter for this client kind.
    func makeAdapter() -> MCPClientAdapter {
        switch self {
        case .claudeDesktop: return ClaudeDesktopAdapter()
        case .cursor: return CursorAdapter()
        case .vscode: return VSCodeAdapter()
        case .claudeCode: return ClaudeCodeAdapter()
        case .windsurf: return WindsurfAdapter()
        case .zed: return ZedAdapter()
        case .jetbrains: return JetBrainsAdapter()
        case .codex: return CodexAdapter()
        case .antigravity: return AntigravityAdapter()
        }
    }
}
