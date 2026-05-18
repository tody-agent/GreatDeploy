import Foundation

/// Represents an AI coding tool that supports MCP server configuration.
enum MCPClientKind: String, Codable, Sendable, CaseIterable {
    case claudeDesktop
    case cursor
    case vscode
    case claudeCode
    case windsurf
    case zed
    case jetbrains
    case codex
    case antigravity

    var displayName: String {
        switch self {
        case .claudeDesktop: return "Claude Desktop"
        case .cursor: return "Cursor"
        case .vscode: return "VS Code"
        case .claudeCode: return "Claude Code"
        case .windsurf: return "Windsurf"
        case .zed: return "Zed"
        case .jetbrains: return "JetBrains IDE"
        case .codex: return "Codex CLI"
        case .antigravity: return "Antigravity"
        }
    }

    var iconName: String {
        switch self {
        case .claudeDesktop: return "desktopcomputer"
        case .cursor: return "cursorarrow"
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        case .claudeCode: return "brain.head.profile"
        case .windsurf: return "wind"
        case .zed: return "text.cursor"
        case .jetbrains: return "app.badge"
        case .codex: return "cpu"
        case .antigravity: return "arrow.down.to.line"
        }
    }

    /// Config path on macOS. Returns nil if not applicable.
    var configPath: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeDesktop:
            return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .cursor:
            return home.appendingPathComponent(".cursor/mcp.json")
        case .vscode:
            return home.appendingPathComponent("Library/Application Support/Code/User/settings.json")
        case .claudeCode:
            return home.appendingPathComponent(".claude/settings.json")
        case .windsurf:
            return home.appendingPathComponent(".codeium/windsurf/mcp_config.json")
        case .zed:
            return home.appendingPathComponent(".config/zed/settings.json")
        case .jetbrains:
            return home.appendingPathComponent("Library/Application Support/JetBrains")
        case .codex:
            return home.appendingPathComponent(".codex/config.toml")
        case .antigravity:
            return nil
        }
    }

    /// Check if this client is installed (config dir or app bundle exists).
    var isInstalled: Bool {
        let fm = FileManager.default
        if let path = configPath {
            if path.pathExtension == "json" || path.pathExtension == "toml" {
                return fm.fileExists(atPath: path.path) || fm.fileExists(atPath: path.deletingLastPathComponent().path)
            }
            return fm.fileExists(atPath: path.path)
        }
        return false
    }

    /// Bundle identifiers for app-based detection.
    var bundleIdentifier: String? {
        switch self {
        case .claudeDesktop: return "com.anthropic.claudefordesktop"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .vscode: return "com.microsoft.VSCode"
        case .windsurf: return "com.windsurf.app"
        case .zed: return "dev.zed.Zed"
        default: return nil
        }
    }
}
