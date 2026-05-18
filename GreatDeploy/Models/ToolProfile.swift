import Foundation

/// Represents an AI coding assistant tool and its configuration paths/formats.
public enum AITool: String, CaseIterable, Identifiable, Codable, Sendable {
    case openCode = "opencode"
    case cursor = "cursor"
    case claudeCode = "claude-code"
    case claudeDesktop = "claude-desktop"
    case windsurf = "windsurf"
    case vscodeCopilot = "vscode-copilot"
    case geminiCLI = "gemini-cli"
    case codex = "codex"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openCode: return "OpenCode"
        case .cursor: return "Cursor"
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .windsurf: return "Windsurf"
        case .vscodeCopilot: return "VS Code Copilot"
        case .geminiCLI: return "Gemini CLI"
        case .codex: return "Codex"
        }
    }

    public var iconName: String {
        switch self {
        case .openCode: return "terminal"
        case .cursor: return "cursorarrow"
        case .claudeCode: return "brain.head.profile"
        case .claudeDesktop: return "desktopcomputer"
        case .windsurf: return "wind"
        case .vscodeCopilot: return "chevron.left.forwardslash.chevron.right"
        case .geminiCLI: return "sparkles"
        case .codex: return "cpu"
        }
    }

    public var supportsSkills: Bool {
        switch self {
        case .openCode, .cursor, .claudeCode, .windsurf, .vscodeCopilot: return true
        case .claudeDesktop, .geminiCLI, .codex: return false
        }
    }

    public var skillsDirectory: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .openCode: return home.appendingPathComponent(".config/opencode/skills")
        case .cursor: return home.appendingPathComponent(".cursor/rules")
        case .claudeCode: return home.appendingPathComponent(".claude/skills")
        case .windsurf: return home.appendingPathComponent(".windsurf/rules")
        case .vscodeCopilot: return nil
        case .claudeDesktop, .geminiCLI, .codex: return nil
        }
    }

    public var projectSkillsSubpath: String? {
        switch self {
        case .openCode: return ".opencode/skills"
        case .cursor: return ".cursor/rules"
        case .claudeCode: return ".claude/skills"
        case .windsurf: return ".windsurf/rules"
        case .vscodeCopilot: return ".github"
        case .claudeDesktop, .geminiCLI, .codex: return nil
        }
    }

    public var skillFormat: SkillFormat {
        switch self {
        case .openCode, .claudeCode: return .skillMD
        case .cursor: return .mdc
        case .windsurf, .vscodeCopilot: return .markdown
        case .claudeDesktop, .geminiCLI, .codex: return .none
        }
    }

    public var supportsMCP: Bool {
        switch self {
        case .openCode, .cursor, .claudeCode, .claudeDesktop, .windsurf, .vscodeCopilot: return true
        case .geminiCLI, .codex: return false
        }
    }

    public var mcpConfigPath: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeDesktop: return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .cursor: return home.appendingPathComponent(".cursor/mcp.json")
        case .claudeCode: return home.appendingPathComponent(".claude/mcp.json")
        case .openCode: return home.appendingPathComponent(".config/opencode/opencode.json")
        case .windsurf: return home.appendingPathComponent(".windsurf/mcp.json")
        case .vscodeCopilot: return nil
        case .geminiCLI, .codex: return nil
        }
    }

    public var projectMCPSubpath: String? {
        switch self {
        case .claudeCode, .cursor, .windsurf: return ".mcp.json"
        case .openCode: return ".opencode/mcp.json"
        case .vscodeCopilot: return ".vscode/mcp.json"
        case .claudeDesktop, .geminiCLI, .codex: return nil
        }
    }

    public var mcpFormat: MCPFormat {
        switch self {
        case .claudeDesktop: return .claudeDesktop
        case .cursor, .claudeCode, .windsurf, .vscodeCopilot: return .mcpJSON
        case .openCode: return .opencodeJSON
        case .geminiCLI, .codex: return .none
        }
    }

    public var supportsAgents: Bool { self == .claudeCode }

    public var agentsDirectory: URL? {
        if self == .claudeCode {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/agents")
        }
        return nil
    }

    public var bundleIdentifier: String? {
        switch self {
        case .claudeDesktop: return "com.anthropic.claudefordesktop"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .windsurf: return "com.windsurf.app"
        case .vscodeCopilot: return "com.microsoft.VSCode"
        default: return nil
        }
    }

    public var syncPriority: Int {
        switch self {
        case .claudeCode: return 1
        case .openCode: return 2
        case .cursor: return 3
        case .windsurf: return 4
        case .vscodeCopilot: return 5
        case .claudeDesktop: return 6
        case .geminiCLI: return 7
        case .codex: return 8
        }
    }

    static var allByPriority: [AITool] { allCases.sorted { $0.syncPriority < $1.syncPriority } }
    static var skillsCapable: [AITool] { allByPriority.filter { $0.supportsSkills } }
    static var mcpCapable: [AITool] { allByPriority.filter { $0.supportsMCP } }
}

public enum SkillFormat: String, Codable, Sendable {
    case skillMD, mdc, markdown, none
}

public enum MCPFormat: String, Codable, Sendable {
    case claudeDesktop, mcpJSON, opencodeJSON, none
}

public enum SyncStatus: String, Codable, Sendable {
    case synced, pending, conflict, error, neverSynced, toolNotInstalled

    public var displayLabel: String {
        switch self {
        case .synced: return "Synced"
        case .pending: return "Pending"
        case .conflict: return "Conflict"
        case .error: return "Error"
        case .neverSynced: return "Never synced"
        case .toolNotInstalled: return "Not installed"
        }
    }

    public var systemImage: String {
        switch self {
        case .synced: return "checkmark.circle.fill"
        case .pending: return "arrow.triangle.2.circlepath"
        case .conflict: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .neverSynced: return "circle.dashed"
        case .toolNotInstalled: return "questionmark.circle"
        }
    }
}

public struct ToolSyncRecord: Codable, Equatable, Sendable {
    public let tool: AITool
    public var status: SyncStatus
    public var lastSyncedAt: Date?
    public var lastError: String?
    public var targetPath: URL?

    init(tool: AITool, status: SyncStatus = .neverSynced, lastSyncedAt: Date? = nil, lastError: String? = nil, targetPath: URL? = nil) {
        self.tool = tool
        self.status = status
        self.lastSyncedAt = lastSyncedAt
        self.lastError = lastError
        self.targetPath = targetPath
    }
}
