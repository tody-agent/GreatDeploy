import XCTest
@testable import GreatDeploy

final class SkillRegistryTests: XCTestCase {

    var registry: SkillRegistry!
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        registry = SkillRegistry.shared
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillRegistryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - RegisteredSkill Model

    func testRegisteredSkillID() {
        let skill = RegisteredSkill(
            name: "test-skill",
            masterPath: tempDirectory.appendingPathComponent("test-skill"),
            description: "A test skill",
            content: "# test-skill\n\nDescription here",
            lastModified: Date(),
            syncRecords: [:]
        )
        XCTAssertEqual(skill.id, "test-skill")
    }

    func testRegisteredSkillSyncStatus() {
        let skill = RegisteredSkill(
            name: "test-skill",
            masterPath: tempDirectory.appendingPathComponent("test-skill"),
            description: "Test",
            content: "",
            lastModified: Date(),
            syncRecords: [
                .openCode: ToolSyncRecord(tool: .openCode, status: .synced),
                .cursor: ToolSyncRecord(tool: .cursor, status: .pending)
            ]
        )
        XCTAssertEqual(skill.syncStatus(for: .openCode), .synced)
        XCTAssertEqual(skill.syncStatus(for: .cursor), .pending)
        XCTAssertEqual(skill.syncStatus(for: .claudeCode), .neverSynced)
    }

    func testRegisteredSkillEquality() {
        let path = tempDirectory.appendingPathComponent("test-skill")
        let date = Date()

        let skill1 = RegisteredSkill(
            name: "test-skill",
            masterPath: path,
            description: "Test",
            content: "content",
            lastModified: date,
            syncRecords: [:]
        )
        let skill2 = RegisteredSkill(
            name: "test-skill",
            masterPath: path,
            description: "Test",
            content: "content",
            lastModified: date,
            syncRecords: [:]
        )
        XCTAssertEqual(skill1, skill2)
    }

    // MARK: - MCPRegistry

    func testRegisteredMCPServerID() {
        let config = MCPServerConfig(
            name: "test-server",
            command: "node",
            args: ["server.js"],
            env: ["KEY": "value"]
        )
        let server = RegisteredMCPServer(
            name: "test-server",
            config: config,
            syncRecords: [:]
        )
        XCTAssertEqual(server.id, "test-server")
    }

    func testRegisteredMCPServerSyncStatus() {
        let config = MCPServerConfig(
            name: "test-server",
            command: "node",
            args: [],
            env: [:]
        )
        let server = RegisteredMCPServer(
            name: "test-server",
            config: config,
            syncRecords: [
                .cursor: ToolSyncRecord(tool: .cursor, status: .synced)
            ]
        )
        XCTAssertEqual(server.syncStatus(for: .cursor), .synced)
        XCTAssertEqual(server.syncStatus(for: .openCode), .neverSynced)
    }

    // MARK: - MCPServerConfig

    func testMCPServerConfigCodable() {
        let config = MCPServerConfig(
            name: "test",
            command: "node",
            args: ["--port", "3000"],
            env: ["API_KEY": "secret"]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let data = try encoder.encode(config)
            let decoded = try decoder.decode(MCPServerConfig.self, from: data)
            XCTAssertEqual(decoded.name, config.name)
            XCTAssertEqual(decoded.command, config.command)
            XCTAssertEqual(decoded.args, config.args)
            XCTAssertEqual(decoded.env, config.env)
        } catch {
            XCTFail("MCPServerConfig should be Codable: \(error)")
        }
    }

    func testMCPServerConfigEquality() {
        let config1 = MCPServerConfig(name: "test", command: "node", args: [], env: [:])
        let config2 = MCPServerConfig(name: "test", command: "node", args: [], env: [:])
        XCTAssertEqual(config1, config2)
    }

    func testMCPServerConfigIdentifiable() {
        let config = MCPServerConfig(name: "my-server", command: "python", args: [], env: [:])
        XCTAssertEqual(config.id, "my-server")
    }

    // MARK: - ToolSyncRecord

    func testToolSyncRecordCodable() {
        let record = ToolSyncRecord(
            tool: .cursor,
            status: .synced,
            lastSyncedAt: Date(),
            lastError: nil,
            targetPath: URL(fileURLWithPath: "/tmp/test")
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let data = try encoder.encode(record)
            let decoded = try decoder.decode(ToolSyncRecord.self, from: data)
            XCTAssertEqual(decoded.tool, .cursor)
            XCTAssertEqual(decoded.status, .synced)
        } catch {
            XCTFail("ToolSyncRecord should be Codable: \(error)")
        }
    }
}
