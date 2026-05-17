import XCTest
@testable import GreatDeploy

final class ToolProfileTests: XCTestCase {

    // MARK: - AITool Properties

    func testAllAIToolsHaveDisplayName() {
        for tool in AITool.allCases {
            XCTAssertFalse(tool.displayName.isEmpty, "\(tool.rawValue) should have a display name")
        }
    }

    func testAllAIToolsHaveIconName() {
        for tool in AITool.allCases {
            XCTAssertFalse(tool.iconName.isEmpty, "\(tool.rawValue) should have an icon name")
        }
    }

    func testAllAIToolsHaveUniqueID() {
        let ids = AITool.allCases.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All AITool IDs should be unique")
    }

    // MARK: - Skills Support

    func testSkillsCapableTools() {
        let skillsCapable = AITool.skillsCapable
        XCTAssertTrue(skillsCapable.contains(.openCode))
        XCTAssertTrue(skillsCapable.contains(.cursor))
        XCTAssertTrue(skillsCapable.contains(.claudeCode))
        XCTAssertTrue(skillsCapable.contains(.windsurf))
        XCTAssertTrue(skillsCapable.contains(.vscodeCopilot))
        XCTAssertFalse(skillsCapable.contains(.claudeDesktop))
    }

    func testOpenCodeSkillFormat() {
        XCTAssertEqual(AITool.openCode.skillFormat, .skillMD)
    }

    func testCursorSkillFormat() {
        XCTAssertEqual(AITool.cursor.skillFormat, .mdc)
    }

    func testClaudeCodeSkillFormat() {
        XCTAssertEqual(AITool.claudeCode.skillFormat, .skillMD)
    }

    func testWindsurfSkillFormat() {
        XCTAssertEqual(AITool.windsurf.skillFormat, .markdown)
    }

    // MARK: - MCP Support

    func testMCPCapableTools() {
        let mcpCapable = AITool.mcpCapable
        XCTAssertTrue(mcpCapable.contains(.openCode))
        XCTAssertTrue(mcpCapable.contains(.cursor))
        XCTAssertTrue(mcpCapable.contains(.claudeCode))
        XCTAssertTrue(mcpCapable.contains(.claudeDesktop))
        XCTAssertTrue(mcpCapable.contains(.windsurf))
        XCTAssertTrue(mcpCapable.contains(.vscodeCopilot))
    }

    // MARK: - Sync Priority

    func testSyncPriorityOrder() {
        let allByPriority = AITool.allByPriority
        XCTAssertEqual(allByPriority.first, .claudeCode, "Claude Code should have highest priority")
    }

    // MARK: - Skill Format

    func testSkillFormatRawValues() {
        XCTAssertEqual(SkillFormat.skillMD.rawValue, "skillMD")
        XCTAssertEqual(SkillFormat.mdc.rawValue, "mdc")
        XCTAssertEqual(SkillFormat.markdown.rawValue, "markdown")
        XCTAssertEqual(SkillFormat.none.rawValue, "none")
    }

    // MARK: - Sync Status

    func testSyncStatusDisplayLabels() {
        XCTAssertEqual(SyncStatus.synced.displayLabel, "Synced")
        XCTAssertEqual(SyncStatus.pending.displayLabel, "Pending")
        XCTAssertEqual(SyncStatus.conflict.displayLabel, "Conflict")
        XCTAssertEqual(SyncStatus.error.displayLabel, "Error")
        XCTAssertEqual(SyncStatus.neverSynced.displayLabel, "Never synced")
        XCTAssertEqual(SyncStatus.toolNotInstalled.displayLabel, "Not installed")
    }

    func testSyncStatusSystemImages() {
        XCTAssertFalse(SyncStatus.synced.systemImage.isEmpty)
        XCTAssertFalse(SyncStatus.pending.systemImage.isEmpty)
        XCTAssertFalse(SyncStatus.conflict.systemImage.isEmpty)
        XCTAssertFalse(SyncStatus.error.systemImage.isEmpty)
        XCTAssertFalse(SyncStatus.neverSynced.systemImage.isEmpty)
        XCTAssertFalse(SyncStatus.toolNotInstalled.systemImage.isEmpty)
    }

    // MARK: - Tool Sync Record

    func testToolSyncRecordInit() {
        let record = ToolSyncRecord(tool: .openCode, status: .synced)
        XCTAssertEqual(record.tool, .openCode)
        XCTAssertEqual(record.status, .synced)
        XCTAssertNil(record.lastSyncedAt)
        XCTAssertNil(record.lastError)
        XCTAssertNil(record.targetPath)
    }

    func testToolSyncRecordEquality() {
        let date = Date()
        let record1 = ToolSyncRecord(tool: .cursor, status: .synced, lastSyncedAt: date)
        let record2 = ToolSyncRecord(tool: .cursor, status: .synced, lastSyncedAt: date)
        XCTAssertEqual(record1, record2)
    }

    // MARK: - Skills Directory Paths

    func testOpenCodeSkillsDirectory() {
        let dir = AITool.openCode.skillsDirectory
        XCTAssertNotNil(dir)
        XCTAssertTrue(dir!.path.contains(".config/opencode/skills"))
    }

    func testCursorSkillsDirectory() {
        let dir = AITool.cursor.skillsDirectory
        XCTAssertNotNil(dir)
        XCTAssertTrue(dir!.path.contains(".cursor/rules"))
    }

    func testClaudeCodeSkillsDirectory() {
        let dir = AITool.claudeCode.skillsDirectory
        XCTAssertNotNil(dir)
        XCTAssertTrue(dir!.path.contains(".claude/skills"))
    }

    func testClaudeDesktopSkillsDirectory() {
        let dir = AITool.claudeDesktop.skillsDirectory
        XCTAssertNil(dir, "Claude Desktop should not have a skills directory")
    }

    // MARK: - MCP Config Paths

    func testClaudeDesktopMCPConfigPath() {
        let path = AITool.claudeDesktop.mcpConfigPath
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.path.contains("claude_desktop_config.json"))
    }

    func testCursorMCPConfigPath() {
        let path = AITool.cursor.mcpConfigPath
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.path.contains(".cursor/mcp.json"))
    }

    func testOpenCodeMCPConfigPath() {
        let path = AITool.openCode.mcpConfigPath
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.path.contains("opencode"))
    }
}
