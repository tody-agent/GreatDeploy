import Foundation
import os.log

/// Orchestrates syncing skills from master registry to each AI tool.
final class ToolSyncService: ToolSyncServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "ToolSync")
    private let registry = SkillRegistry.shared
    private let discovery = ToolDiscoveryService.shared
    static let shared = ToolSyncService()
    private init() {}

    struct SyncResult: Sendable { let skillName: String; let tool: AITool; let success: Bool; let error: String?; let syncedAt: Date }
    struct BatchSyncResult: Sendable { let results: [SyncResult]; var successCount: Int { results.filter { $0.success }.count }; var failureCount: Int { results.filter { !$0.success }.count }; var totalCount: Int { results.count } }

    func syncSkillToTool(skillName: String, tool: AITool) throws -> SyncResult {
        guard tool.supportsSkills else { return SyncResult(skillName: skillName, tool: tool, success: false, error: "Tool does not support skills", syncedAt: Date()) }
        guard discovery.installedTools().contains(tool) else {
            registry.updateSyncRecord(for: skillName, tool: tool, record: ToolSyncRecord(tool: tool, status: .toolNotInstalled))
            return SyncResult(skillName: skillName, tool: tool, success: false, error: "Tool not installed", syncedAt: Date())
        }
        guard let masterSkill = try registry.getMasterSkill(name: skillName) else {
            return SyncResult(skillName: skillName, tool: tool, success: false, error: "Skill not found", syncedAt: Date())
        }
        do {
            let targetPath = try writeSkillToTool(masterSkill, tool: tool)
            registry.updateSyncRecord(for: skillName, tool: tool, record: ToolSyncRecord(tool: tool, status: .synced, lastSyncedAt: Date(), targetPath: targetPath))
            return SyncResult(skillName: skillName, tool: tool, success: true, error: nil, syncedAt: Date())
        } catch {
            registry.updateSyncRecord(for: skillName, tool: tool, record: ToolSyncRecord(tool: tool, status: .error, lastError: error.localizedDescription))
            return SyncResult(skillName: skillName, tool: tool, success: false, error: error.localizedDescription, syncedAt: Date())
        }
    }

    func syncSkillToAllTools(skillName: String) -> BatchSyncResult {
        let tools = discovery.installedSkillsCapableTools()
        let results = tools.compactMap { try? syncSkillToTool(skillName: skillName, tool: $0) }
        return BatchSyncResult(results: results)
    }

    func syncAllSkillsToAllTools() -> BatchSyncResult {
        guard let skills = try? registry.listMasterSkills() else { return BatchSyncResult(results: []) }
        let tools = discovery.installedSkillsCapableTools()
        var allResults: [SyncResult] = []
        for skill in skills { for tool in tools { if let result = try? syncSkillToTool(skillName: skill.name, tool: tool) { allResults.append(result) } } }
        return BatchSyncResult(results: allResults)
    }

    func syncAllSkillsToTool(tool: AITool) -> BatchSyncResult {
        guard let skills = try? registry.listMasterSkills() else { return BatchSyncResult(results: []) }
        let results = skills.compactMap { try? syncSkillToTool(skillName: $0.name, tool: tool) }
        return BatchSyncResult(results: results)
    }

    func pullSkillFromTool(skillName: String, from tool: AITool) throws -> RegisteredSkill {
        guard let skillsDir = tool.skillsDirectory else { throw SyncError.toolNotCapable(tool.displayName) }
        let content: String
        switch tool.skillFormat {
        case .skillMD: content = try String(contentsOf: skillsDir.appendingPathComponent(skillName).appendingPathComponent("SKILL.md"), encoding: .utf8)
        case .mdc: content = try String(contentsOf: skillsDir.appendingPathComponent("\(skillName).mdc"), encoding: .utf8)
        case .markdown: content = try String(contentsOf: skillsDir.appendingPathComponent("\(skillName).md"), encoding: .utf8)
        case .none: throw SyncError.toolNotCapable(tool.displayName)
        }
        return try registry.importFromTool(skillName: skillName, from: tool, content: content)
    }

    private func writeSkillToTool(_ skill: RegisteredSkill, tool: AITool) throws -> URL {
        guard let skillsDir = tool.skillsDirectory else { throw SyncError.toolNotCapable(tool.displayName) }
        let fm = FileManager.default
        if !fm.fileExists(atPath: skillsDir.path) { try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true) }
        switch tool.skillFormat {
        case .skillMD:
            let skillDir = skillsDir.appendingPathComponent(skill.name)
            let skillFile = skillDir.appendingPathComponent("SKILL.md")
            if !fm.fileExists(atPath: skillDir.path) { try fm.createDirectory(at: skillDir, withIntermediateDirectories: true) }
            try skill.content.write(to: skillFile, atomically: true, encoding: .utf8)
            return skillDir
        case .mdc:
            let skillFile = skillsDir.appendingPathComponent("\(skill.name).mdc")
            let mdcContent = "---\ndescription: \"\(parseSkillDescription(from: skill.content))\"\nalwaysApply: false\n---\n\n\(skill.content)"
            try mdcContent.write(to: skillFile, atomically: true, encoding: .utf8)
            return skillFile
        case .markdown:
            let skillFile = skillsDir.appendingPathComponent("\(skill.name).md")
            try skill.content.write(to: skillFile, atomically: true, encoding: .utf8)
            return skillFile
        case .none: throw SyncError.toolNotCapable(tool.displayName)
        }
    }

    private func parseSkillDescription(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var foundHeading = false, description = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") { foundHeading = true; continue }
            if foundHeading { if trimmed.isEmpty { if !description.isEmpty { break }; continue }; if trimmed.hasPrefix("##") { break }; if !description.isEmpty { description += " " }; description += trimmed }
        }
        return description.isEmpty ? "Unknown skill" : description
    }

    enum SyncError: LocalizedError { case toolNotCapable(String), writeFailed(String), readFailed(String); var errorDescription: String? { switch self { case .toolNotCapable(let t): return "\(t) does not support skills"; case .writeFailed(let d): return "Failed to write: \(d)"; case .readFailed(let d): return "Failed to read: \(d)" } } }
}
