import XCTest
@testable import GreatDeploy

final class CursorAdapterTests: XCTestCase {

    // MARK: - Helpers

    private func makeAdapter(tempDir: URL) -> (adapter: CursorAdapter, configPath: URL) {
        let configPath = tempDir.appendingPathComponent("mcp.json")
        let adapter = CursorAdapter(
            fileSystem: TestFileSystem(configURL: configPath),
            overrideConfigPath: configPath
        )
        return (adapter, configPath)
    }

    private func fixtureContent() throws -> String {
        let bundle = Bundle(for: CursorAdapterTests.self)
        guard let url = bundle.url(forResource: "cursor_mcp", withExtension: "json") else {
            throw XCTSkip("Fixture file not found")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - detect()

    func test_detect_returnsTrue_whenConfigFileExists() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let (adapter, configPath) = makeAdapter(tempDir: tempDir)
        try? FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "{}".write(to: configPath, atomically: true, encoding: .utf8)
        XCTAssertTrue(adapter.detect())
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_detect_returnsFalse_whenConfigFileMissing() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let (adapter, configPath) = makeAdapter(tempDir: tempDir)
        XCTAssertFalse(adapter.detect())
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - readServers()

    func test_readServers_parsesFixture_intoThreeServers() throws {
        let content = try fixtureContent()
        let servers = try JSONAdapterHelpers.parseServers(from: content)
        XCTAssertEqual(servers.count, 3)

        let names = Set(servers.map(\.name))
        XCTAssertTrue(names.contains("filesystem"))
        XCTAssertTrue(names.contains("github"))
        XCTAssertTrue(names.contains("user-added-server"))

        let fs = servers.first { $0.name == "filesystem" }!
        XCTAssertEqual(fs.command, "npx")
        XCTAssertEqual(fs.args, ["-y", "@modelcontextprotocol/server-filesystem", "/Users/test"])
        XCTAssertEqual(fs.transport, .stdio)
        XCTAssertTrue(fs.enabled)

        let gh = servers.first { $0.name == "github" }!
        XCTAssertEqual(gh.command, "npx")
        XCTAssertEqual(gh.env["GITHUB_TOKEN"], "ghp_xxx")
    }

    func test_readServers_emptyFile_returnsEmptyArray() throws {
        let servers = try JSONAdapterHelpers.parseServers(from: "")
        XCTAssertEqual(servers.count, 0)
    }

    // MARK: - writeServers()

    func test_writeServers_preservesUserAddedServers() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let (adapter, configPath) = makeAdapter(tempDir: tempDir)
        try FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fixtureContent = try fixtureContent()
        try fixtureContent.write(to: configPath, atomically: true, encoding: .utf8)

        let bundleServers: [MCPServerDefinition] = [
            MCPServerDefinition(name: "filesystem", command: "npx", args: ["-y", "@mcp/fs"]),
            MCPServerDefinition(name: "github", command: "npx", args: ["-y", "@mcp/github"]),
        ]

        try adapter.writeServers(
            bundleServers,
            existingContent: fixtureContent,
            previouslySyncedNames: ["filesystem", "github"]
        )

        let written = try String(contentsOf: configPath, encoding: .utf8)
        let writtenServers = try JSONAdapterHelpers.parseServers(from: written)
        let writtenNames = Set(writtenServers.map(\.name))

        XCTAssertTrue(writtenNames.contains("user-added-server"), "User-added server should be preserved")
        XCTAssertTrue(writtenNames.contains("filesystem"), "Bundle server should be present")
        XCTAssertTrue(writtenNames.contains("github"), "Bundle server should be present")
        XCTAssertEqual(writtenServers.count, 3)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_writeServers_removesOrphans() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let (adapter, configPath) = makeAdapter(tempDir: tempDir)
        try FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fixtureContent = try fixtureContent()
        try fixtureContent.write(to: configPath, atomically: true, encoding: .utf8)

        let bundleServers: [MCPServerDefinition] = [
            MCPServerDefinition(name: "filesystem", command: "npx", args: ["-y", "@mcp/fs"]),
        ]

        try adapter.writeServers(
            bundleServers,
            existingContent: fixtureContent,
            previouslySyncedNames: ["filesystem", "github"]
        )

        let written = try String(contentsOf: configPath, encoding: .utf8)
        let writtenServers = try JSONAdapterHelpers.parseServers(from: written)
        let writtenNames = Set(writtenServers.map(\.name))

        XCTAssertTrue(writtenNames.contains("filesystem"))
        XCTAssertTrue(writtenNames.contains("user-added-server"))
        XCTAssertFalse(writtenNames.contains("github"), "Orphan should be removed")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_writeServers_atomicWrite_createsFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let (adapter, configPath) = makeAdapter(tempDir: tempDir)
        try FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let servers: [MCPServerDefinition] = [
            MCPServerDefinition(name: "test-server", command: "echo", args: ["hello"]),
        ]

        try adapter.writeServers(servers, existingContent: nil, previouslySyncedNames: [])

        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))

        let content = try String(contentsOf: configPath, encoding: .utf8)
        let parsedServers = try JSONAdapterHelpers.parseServers(from: content)
        XCTAssertEqual(parsedServers.count, 1)
        XCTAssertEqual(parsedServers.first?.name, "test-server")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_writeServers_preservesNonMCPKeys() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let (adapter, configPath) = makeAdapter(tempDir: tempDir)
        try FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fixtureContent = try fixtureContent()
        try fixtureContent.write(to: configPath, atomically: true, encoding: .utf8)

        let bundleServers: [MCPServerDefinition] = [
            MCPServerDefinition(name: "filesystem", command: "npx", args: []),
        ]

        try adapter.writeServers(
            bundleServers,
            existingContent: fixtureContent,
            previouslySyncedNames: ["filesystem"]
        )

        let written = try String(contentsOf: configPath, encoding: .utf8)
        let data = written.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["theme"] as? String, "dark", "Non-MCP keys should be preserved")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_verifyAfterWrite_readServers_matchesWritten() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let (adapter, configPath) = makeAdapter(tempDir: tempDir)
        try FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let servers: [MCPServerDefinition] = [
            MCPServerDefinition(name: "alpha", command: "echo", args: ["a"]),
            MCPServerDefinition(name: "beta", command: "echo", args: ["b"]),
        ]

        try adapter.writeServers(servers, existingContent: nil, previouslySyncedNames: [])

        let readServers = try adapter.readServers()
        let readNames = Set(readServers.map(\.name))
        XCTAssertEqual(readNames, ["alpha", "beta"])
        XCTAssertEqual(readServers.count, 2)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
