import Foundation
import os.log

/// Service for managing skills across multiple AI tools.
final class SkillsService: SkillsServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "Skills")
    static let shared = SkillsService()
    private init() {}

    var globalSkillsDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills") }
    static let projectSkillsSubpath = ".claude/skills"

    func skillsDirectory(for tool: AITool) -> URL? { tool.skillsDirectory }
    func projectSkillsSubpath(for tool: AITool) -> String? { tool.projectSkillsSubpath }

    func scanGlobalSkills() throws -> [URL] { try scanSkillURLs(at: globalSkillsDirectory) }
    func scanProjectSkills(at projectDir: URL) throws -> [URL] { try scanSkillURLs(at: projectDir.appendingPathComponent(Self.projectSkillsSubpath)) }

    func scanGlobalSkills(for tool: AITool) throws -> [URL] {
        guard let dir = tool.skillsDirectory else { return [] }
        switch tool.skillFormat {
        case .skillMD: return try scanSkillURLs(at: dir)
        case .mdc: return try scanMDCFiles(at: dir)
        case .markdown: return try scanMarkdownFiles(at: dir)
        case .none: return []
        }
    }

    func scanGlobalSkillItems() throws -> [SkillItem] { try scanSkillItems(at: globalSkillsDirectory) }
    func scanProjectSkillItems(at projectDir: URL) throws -> [SkillItem] { try scanSkillItems(at: projectDir.appendingPathComponent(Self.projectSkillsSubpath)) }

    func scanGlobalSkillItems(for tool: AITool) throws -> [SkillItem] {
        guard let dir = tool.skillsDirectory else { return [] }
        switch tool.skillFormat {
        case .skillMD: return try scanSkillItems(at: dir)
        case .mdc: return try scanMDCItems(at: dir)
        case .markdown: return try scanMarkdownItems(at: dir)
        case .none: return []
        }
    }

    private func scanSkillURLs(at directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return contents.filter { fm.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func scanMDCFiles(at directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).filter { $0.pathExtension == "mdc" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func scanMarkdownFiles(at directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func scanSkillItems(at directory: URL) throws -> [SkillItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return contents.compactMap { item -> SkillItem? in
            let skillFile = item.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { return nil }
            guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }
            return SkillItem(name: item.lastPathComponent, path: item, description: parseSkillDescription(from: content), content: content)
        }.sorted { $0.name < $1.name }
    }

    private func scanMDCItems(at directory: URL) throws -> [SkillItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).filter { $0.pathExtension == "mdc" }.compactMap { item -> SkillItem? in
            let content = try String(contentsOf: item, encoding: .utf8)
            return SkillItem(name: item.deletingPathExtension().lastPathComponent, path: item, description: parseMDCDescription(from: content), content: content)
        }.sorted { $0.name < $1.name }
    }

    private func scanMarkdownItems(at directory: URL) throws -> [SkillItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).filter { $0.pathExtension == "md" }.compactMap { item -> SkillItem? in
            let content = try String(contentsOf: item, encoding: .utf8)
            return SkillItem(name: item.deletingPathExtension().lastPathComponent, path: item, description: parseSkillDescription(from: content), content: content)
        }.sorted { $0.name < $1.name }
    }

    func readSkill(at path: URL) throws -> String {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) else { throw SkillsError.readFailed("Path not found") }
        if isDir.boolValue { return try String(contentsOf: path.appendingPathComponent("SKILL.md"), encoding: .utf8) }
        return try String(contentsOf: path, encoding: .utf8)
    }

    func writeSkill(_ content: String, at path: URL) throws {
        let fm = FileManager.default
        let skillFile = path.appendingPathComponent("SKILL.md")
        if !fm.fileExists(atPath: path.path) { try fm.createDirectory(at: path, withIntermediateDirectories: true) }
        try content.write(to: skillFile, atomically: true, encoding: .utf8)
    }

    func createSkill(name: String, in directory: URL) throws -> SkillItem {
        let template = "# \(name)\n\n## Description\nDescribe this skill.\n\n## Usage\nWhen to trigger.\n\n## Instructions\nDetails."
        try writeSkill(template, at: directory.appendingPathComponent(name))
        return SkillItem(name: name, path: directory.appendingPathComponent(name), description: "New skill", content: template)
    }

    func deleteSkill(at path: URL) throws { try FileManager.default.removeItem(at: path) }

    private func parseSkillDescription(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var foundHeading = false, description = ""
        for line in lines { let trimmed = line.trimmingCharacters(in: .whitespaces); if trimmed.hasPrefix("# ") { foundHeading = true; continue }; if foundHeading { if trimmed.isEmpty { if !description.isEmpty { break }; continue }; if trimmed.hasPrefix("##") { break }; if !description.isEmpty { description += " " }; description += trimmed } }
        return description.isEmpty ? "No description" : description
    }

    private func parseMDCDescription(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var inFrontmatter = false
        for line in lines { let trimmed = line.trimmingCharacters(in: .whitespaces); if trimmed == "---" { if inFrontmatter { break }; inFrontmatter = true; continue }; if inFrontmatter && trimmed.hasPrefix("description:") { return trimmed.replacingOccurrences(of: "description:", with: "").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) } }
        return "No description"
    }

    enum SkillsError: LocalizedError { case scanFailed(String), readFailed(String), writeFailed(String), deleteFailed(String); var errorDescription: String? { switch self { case .scanFailed(let d): return "Failed to scan: \(d)"; case .readFailed(let d): return "Failed to read: \(d)"; case .writeFailed(let d): return "Failed to write: \(d)"; case .deleteFailed(let d): return "Failed to delete: \(d)" } } }
}

struct SkillItem: Identifiable, Equatable { var id: String { name }; let name: String; let path: URL; let description: String; let content: String }
