import Foundation
import AppKit
import os.log

/// Service for detecting which AI tools are installed on the system.
final class ToolDiscoveryService: ToolDiscoveryServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "ToolDiscovery")
    static let shared = ToolDiscoveryService()
    private init() {}

    struct DiscoveryResult: Equatable, Sendable {
        let tool: AITool
        let isInstalled: Bool
        let hasSkillsConfig: Bool
        let hasMCPConfig: Bool
        let configPath: URL?
        let detectedBy: DetectionMethod
    }

    enum DetectionMethod: String, Sendable { case configDirectory = "config-dir", appBundle = "app-bundle", cliBinary = "cli-binary", notDetected = "not-detected" }

    func discoverInstalledTools() -> [DiscoveryResult] { AITool.allCases.map { discoverTool($0) } }

    func discoverTool(_ tool: AITool) -> DiscoveryResult {
        let fm = FileManager.default
        if let skillsDir = tool.skillsDirectory, fm.fileExists(atPath: skillsDir.path) {
            return DiscoveryResult(tool: tool, isInstalled: true, hasSkillsConfig: true, hasMCPConfig: tool.mcpConfigPath.flatMap { fm.fileExists(atPath: $0.path) } ?? false, configPath: skillsDir, detectedBy: .configDirectory)
        }
        if let mcpPath = tool.mcpConfigPath, fm.fileExists(atPath: mcpPath.path) {
            return DiscoveryResult(tool: tool, isInstalled: true, hasSkillsConfig: false, hasMCPConfig: true, configPath: mcpPath, detectedBy: .configDirectory)
        }
        if let bundleId = tool.bundleIdentifier, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
            return DiscoveryResult(tool: tool, isInstalled: true, hasSkillsConfig: false, hasMCPConfig: false, configPath: nil, detectedBy: .appBundle)
        }
        if let cliName = cliBinaryName(for: tool) {
            for dir in ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin"] {
                if fm.fileExists(atPath: "\(dir)/\(cliName)") {
                    return DiscoveryResult(tool: tool, isInstalled: true, hasSkillsConfig: false, hasMCPConfig: false, configPath: nil, detectedBy: .cliBinary)
                }
            }
        }
        return DiscoveryResult(tool: tool, isInstalled: false, hasSkillsConfig: false, hasMCPConfig: false, configPath: nil, detectedBy: .notDetected)
    }

    func installedTools() -> [AITool] { discoverInstalledTools().filter { $0.isInstalled }.sorted { $0.tool.syncPriority < $1.tool.syncPriority }.map { $0.tool } }
    func installedSkillsCapableTools() -> [AITool] { installedTools().filter { $0.supportsSkills } }
    func installedMCPCapableTools() -> [AITool] { installedTools().filter { $0.supportsMCP } }

    private func cliBinaryName(for tool: AITool) -> String? {
        switch tool {
        case .claudeCode: return "claude"
        case .openCode: return "opencode"
        case .geminiCLI: return "gemini"
        case .codex: return "codex"
        default: return nil
        }
    }
}
