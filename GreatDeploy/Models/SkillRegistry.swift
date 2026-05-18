import Foundation
import os.log

/// Master registry for skills across all AI tools.
final class SkillRegistry: SkillRegistryServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "SkillRegistry")
    static let shared = SkillRegistry()
    private init() {}

    var masterSkillsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".greatdeploy/skills")
    }

    private func ensureMasterDirectory() throws {
        let fm = FileManager.default
        let dir = masterSkillsDirectory
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func listMasterSkills() throws -> [RegisteredSkill] {
        try ensureMasterDirectory()
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: masterSkillsDirectory, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])

        var skills: [RegisteredSkill] = []
        for item in contents {
            let skillFile = item.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { continue }
            let content = try String(contentsOf: skillFile, encoding: .utf8)
            let name = item.lastPathComponent
            let description = parseSkillDescription(from: content)
            let modDate = try item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let syncRecords = loadSyncRecords(for: name)
            skills.append(RegisteredSkill(name: name, masterPath: item, description: description, content: content, lastModified: modDate ?? Date(), syncRecords: syncRecords))
        }
        return skills.sorted { $0.name < $1.name }
    }

    func getMasterSkill(name: String) throws -> RegisteredSkill? {
        try listMasterSkills().first { $0.name == name }
    }

    func installSkill(name: String, content: String) throws -> RegisteredSkill {
        try ensureMasterDirectory()
        let skillDir = masterSkillsDirectory.appendingPathComponent(name)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        let fm = FileManager.default
        if !fm.fileExists(atPath: skillDir.path) { try fm.createDirectory(at: skillDir, withIntermediateDirectories: true) }
        try content.write(to: skillFile, atomically: true, encoding: .utf8)
        return RegisteredSkill(name: name, masterPath: skillDir, description: parseSkillDescription(from: content), content: content, lastModified: Date(), syncRecords: [:])
    }

    func updateSkill(name: String, content: String) throws {
        let skillDir = masterSkillsDirectory.appendingPathComponent(name)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillDir.path) else { throw SkillRegistryError.skillNotFound(name) }
        try content.write(to: skillFile, atomically: true, encoding: .utf8)
    }

    func deleteSkill(name: String) throws {
        let skillDir = masterSkillsDirectory.appendingPathComponent(name)
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillDir.path) else { throw SkillRegistryError.skillNotFound(name) }
        try fm.removeItem(at: skillDir)
        deleteSyncRecords(for: name)
    }

    func createSkill(name: String, description: String) throws -> RegisteredSkill {
        let template = "# \(name)\n\n## Description\n\(description.isEmpty ? "Describe this skill." : description)\n\n## Usage\nWhen to trigger this skill.\n\n## Instructions\nDetailed instructions."
        return try installSkill(name: name, content: template)
    }

    func importFromTool(skillName: String, from tool: AITool, content: String) throws -> RegisteredSkill {
        if let existing = try getMasterSkill(name: skillName) {
            if existing.content != content { try updateSkill(name: skillName, content: content) }
            return try getMasterSkill(name: skillName)!
        }
        return try installSkill(name: skillName, content: content)
    }

    func updateSyncRecord(for skillName: String, tool: AITool, record: ToolSyncRecord) {
        var records = loadSyncRecords(for: skillName)
        records[tool] = record
        saveSyncRecords(records, for: skillName)
    }

    func saveSyncRecords(_ records: [AITool: ToolSyncRecord], for skillName: String) {
        let metaPath = masterSkillsDirectory.appendingPathComponent(skillName).appendingPathComponent(".sync-meta.json")
        var dict: [String: ToolSyncRecord] = [:]
        for (tool, record) in records { dict[tool.rawValue] = record }
        if let data = try? JSONEncoder().encode(dict) { try? data.write(to: metaPath, options: .atomic) }
    }

    private func loadSyncRecords(for skillName: String) -> [AITool: ToolSyncRecord] {
        let metaPath = masterSkillsDirectory.appendingPathComponent(skillName).appendingPathComponent(".sync-meta.json")
        guard FileManager.default.fileExists(atPath: metaPath.path), let data = try? Data(contentsOf: metaPath), let records = try? JSONDecoder().decode([String: ToolSyncRecord].self, from: data) else { return [:] }
        var result: [AITool: ToolSyncRecord] = [:]
        for (key, record) in records { if let tool = AITool(rawValue: key) { result[tool] = record } }
        return result
    }

    private func deleteSyncRecords(for skillName: String) {
        let metaPath = masterSkillsDirectory.appendingPathComponent(skillName).appendingPathComponent(".sync-meta.json")
        try? FileManager.default.removeItem(at: metaPath)
    }

    private func parseSkillDescription(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var foundHeading = false, description = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") { foundHeading = true; continue }
            if foundHeading {
                if trimmed.isEmpty { if !description.isEmpty { break }; continue }
                if trimmed.hasPrefix("##") { break }
                if !description.isEmpty { description += " " }
                description += trimmed
            }
        }
        return description.isEmpty ? "No description" : description
    }

    enum SkillRegistryError: LocalizedError {
        case skillNotFound(String)
        var errorDescription: String? {
            switch self { case .skillNotFound(let name): return "Skill '\(name)' not found" }
        }
    }
}

public struct RegisteredSkill: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let masterPath: URL
    public let description: String
    public let content: String
    public let lastModified: Date
    public var syncRecords: [AITool: ToolSyncRecord]

    public func syncStatus(for tool: AITool) -> SyncStatus { syncRecords[tool]?.status ?? .neverSynced }
    public var isFullySynced: Bool {
        let installed = ToolDiscoveryService.shared.installedSkillsCapableTools()
        return installed.allSatisfy { syncStatus(for: $0) == .synced }
    }
    public var pendingTools: [AITool] { AITool.skillsCapable.filter { syncStatus(for: $0) == .pending } }
}
