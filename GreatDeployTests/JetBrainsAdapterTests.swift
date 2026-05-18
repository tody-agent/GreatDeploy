import XCTest
@testable import GreatDeploy

final class JetBrainsAdapterTests: XCTestCase {

    // MARK: - Helpers

    private func makeAdapter(tempDir: URL) -> (adapter: JetBrainsAdapter, configPath: URL) {
        let configPath = tempDir.appendingPathComponent("options/mcp.xml")
        let adapter = JetBrainsAdapter(
            fileSystem: TestFileSystem(configURL: configPath),
            overrideConfigPath: configPath
        )
        return (adapter, configPath)
    }

    private func fixtureContent() throws -> String {
        let bundle = Bundle(for: JetBrainsAdapterTests.self)
        guard let url = bundle.url(forResource: "jetbrains_mcp", withExtension: "xml") else {
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
        try? "<mcpSettings version=\"1\"><servers></servers></mcpSettings>".write(to: configPath, atomically: true, encoding: .utf8)
        XCTAssertTrue(adapter.detect())
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_detect_returnsFalse_whenConfigFileMissing() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let (adapter, _) = makeAdapter(tempDir: tempDir)
        XCTAssertFalse(adapter.detect())
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - readServers()

    func test_readServers_parsesFixture_intoTwoServers() throws {
        let content = try fixtureContent()
        let servers = try XMLSerializer.parse(content)
        XCTAssertEqual(servers.count, 2)

        let names = Set(servers.map(\.name))
        XCTAssertTrue(names.contains("filesystem"))
        XCTAssertTrue(names.contains("user-jb-server"))

        let fs = servers.first { $0.name == "filesystem" }!
        XCTAssertEqual(fs.command, "npx")
        XCTAssertEqual(fs.args, ["-y", "@mcp/filesystem"])
        XCTAssertEqual(fs.transport, .stdio)
        XCTAssertTrue(fs.enabled)
        XCTAssertEqual(fs.env["API_KEY"], "test-key")
    }

    func test_readServers_emptyFile_returnsEmptyArray() throws {
        let xml = "<?xml version=\"1.0\"?><mcpSettings version=\"1\"><servers></servers></mcpSettings>"
        let servers = try XMLSerializer.parse(xml)
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
        ]

        try adapter.writeServers(
            bundleServers,
            existingContent: fixtureContent,
            previouslySyncedNames: ["filesystem"]
        )

        let written = try String(contentsOf: configPath, encoding: .utf8)
        let writtenServers = try XMLSerializer.parse(written)
        let writtenNames = Set(writtenServers.map(\.name))

        XCTAssertTrue(writtenNames.contains("user-jb-server"), "User-added server should be preserved")
        XCTAssertTrue(writtenNames.contains("filesystem"), "Bundle server should be present")
        XCTAssertEqual(writtenServers.count, 2)

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
            previouslySyncedNames: ["filesystem", "user-jb-server"]
        )

        let written = try String(contentsOf: configPath, encoding: .utf8)
        let writtenServers = try XMLSerializer.parse(written)
        let writtenNames = Set(writtenServers.map(\.name))

        XCTAssertTrue(writtenNames.contains("filesystem"))
        XCTAssertFalse(writtenNames.contains("user-jb-server"), "Orphan should be removed")

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
        let parsedServers = try XMLSerializer.parse(content)
        XCTAssertEqual(parsedServers.count, 1)
        XCTAssertEqual(parsedServers.first?.name, "test-server")

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - verifyAfterWrite

    func test_verifyAfterWrite_readServers_matchesWritten() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let (adapter, configPath) = makeAdapter(tempDir: tempDir)
        try FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let servers: [MCPServerDefinition] = [
            MCPServerDefinition(name: "alpha", command: "echo", args: ["a"]),
            MCPServerDefinition(name: "beta", command: "echo", args: ["b"], env: ["KEY": "val"]),
        ]

        try adapter.writeServers(servers, existingContent: nil, previouslySyncedNames: [])

        let readServers = try adapter.readServers()
        let readNames = Set(readServers.map(\.name))
        XCTAssertEqual(readNames, ["alpha", "beta"])
        XCTAssertEqual(readServers.count, 2)

        let beta = readServers.first { $0.name == "beta" }
        XCTAssertEqual(beta?.env["KEY"], "val")

        try? FileManager.default.removeItem(at: tempDir)
    }
}
