import XCTest
@testable import GreatDeploy

final class ToolDiscoveryTests: XCTestCase {

    var discovery: ToolDiscoveryService!

    override func setUp() {
        super.setUp()
        discovery = ToolDiscoveryService.shared
    }

    // MARK: - Discovery Results

    func testDiscoveryResultHasAllTools() {
        let results = discovery.discoverInstalledTools()
        XCTAssertEqual(results.count, AITool.allCases.count, "Should have a result for every AITool")
    }

    func testDiscoveryResultToolsAreUnique() {
        let results = discovery.discoverInstalledTools()
        let tools = results.map { $0.tool }
        let uniqueTools = Set(tools)
        XCTAssertEqual(tools.count, uniqueTools.count, "All tools in results should be unique")
    }

    func testDiscoveryResultHasDetectionMethod() {
        let results = discovery.discoverInstalledTools()
        for result in results {
            if result.isInstalled {
                XCTAssertNotEqual(result.detectedBy, .notDetected, "\(result.tool.displayName) is installed but has no detection method")
            }
        }
    }

    // MARK: - Installed Tools

    func testInstalledToolsReturnsOnlyInstalled() {
        let installed = discovery.installedTools()
        for tool in installed {
            let result = discovery.discoverTool(tool)
            XCTAssertTrue(result.isInstalled, "\(tool.displayName) should be installed")
        }
    }

    func testInstalledToolsSortedByPriority() {
        let installed = discovery.installedTools()
        for i in 0..<(installed.count - 1) {
            XCTAssertLessThanOrEqual(
                installed[i].syncPriority,
                installed[i + 1].syncPriority,
                "Installed tools should be sorted by priority"
            )
        }
    }

    // MARK: - Skills Capable

    func testInstalledSkillsCapableToolsOnlyReturnSkillsCapable() {
        let tools = discovery.installedSkillsCapableTools()
        for tool in tools {
            XCTAssertTrue(tool.supportsSkills, "\(tool.displayName) should support skills")
        }
    }

    // MARK: - MCP Capable

    func testInstalledMCPCapableToolsOnlyReturnMCPCapable() {
        let tools = discovery.installedMCPCapableTools()
        for tool in tools {
            XCTAssertTrue(tool.supportsMCP, "\(tool.displayName) should support MCP")
        }
    }

    // MARK: - Single Tool Discovery

    func testDiscoverToolReturnsValidResult() {
        for tool in AITool.allCases {
            let result = discovery.discoverTool(tool)
            XCTAssertEqual(result.tool, tool, "Result tool should match requested tool")
        }
    }
}
