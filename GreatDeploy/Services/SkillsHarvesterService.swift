import Foundation
import os.log

final class SkillsHarvesterService: SkillsHarvesting {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "Harvester")
    static let shared = SkillsHarvesterService()
    
    private let discovery: ToolDiscoveryServicing
    private let skillsService: SkillsServicing
    
    init(
        discovery: ToolDiscoveryServicing = ToolDiscoveryService.shared,
        skillsService: SkillsServicing = SkillsService.shared
    ) {
        self.discovery = discovery
        self.skillsService = skillsService
    }
    
    func harvestAllSkills() async throws -> [DiscoveredSkill] {
        Self.logger.info("Starting skill harvest...")
        
        let tools = discovery.installedSkillsCapableTools()
        Self.logger.info("Found \(tools.count) skills-capable tools")
        
        var allSkills: [DiscoveredSkill] = []
        
        for tool in tools {
            Self.logger.info("Scanning \(tool.displayName)...")
            do {
                let skills = try await harvestSkills(from: tool)
                allSkills.append(contentsOf: skills)
                Self.logger.info("Found \(skills.count) skills in \(tool.displayName)")
            } catch {
                Self.logger.error("Failed to scan \(tool.displayName): \(error.localizedDescription)")
            }
        }
        
        var seen = Set<String>()
        allSkills = allSkills.filter { skill in
            if seen.contains(skill.id) { return false }
            seen.insert(skill.id)
            return true
        }
        
        let cache = DiscoveryCache(skills: allSkills, toolsScanned: tools)
        try? cache.save()
        
        Self.logger.info("Harvest complete. Total unique skills: \(allSkills.count)")
        return allSkills
    }
    
    private func harvestSkills(from tool: AITool) async throws -> [DiscoveredSkill] {
        let skillItems = try skillsService.scanGlobalSkillItems(for: tool)
        return skillItems.map { item in
            DiscoveredSkill(
                name: item.name,
                description: item.description,
                content: item.content,
                sourceTool: tool,
                sourcePath: item.path,
                lastModified: modifiedDate(for: item.path)
            )
        }
    }
    
    private func modifiedDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }
    
    func cachedDiscovery() -> DiscoveryCache? {
        try? DiscoveryCache.load()
    }
    
    func clearCache() throws {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".greatdeploy")
            .appendingPathComponent(DiscoveryCache.cacheFileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    func discoveryStatus() -> HarvestStatus {
        if let cache = cachedDiscovery() {
            return .completed(skillCount: cache.skills.count, toolCount: cache.toolsScannedEnums.count, discoveredAt: cache.discoveredAt)
        }
        return .neverRun
    }
}