import XCTest
@testable import GreatDeploy

final class ZedAdapterTests: XCTestCase {

    // MARK: - Helpers

    private func makeAdapter(tempDir: URL) -> (adapter: ZedAdapter, configPath: URL) {
        let configPath = tempDir.appendingPathComponent("settings.json")
        let adapter = ZedAdapter(
            fileSystem: TestFileSystem(configURL: configPath),
            overrideConfigPath: configPath
        )
        return (adapter, configPath)
    }

    private func fixtureContent() throws -> String {
        let bundle = Bundle(for: ZedAdapterTests.self)
        guard let url = bundle.url(forResource: "zed_settings", withExtension: "json") else {
            throw XCTSkip("Fixture file not found")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - detect()

    func test_detect_returnsTrue_whenConfigDirExists() {
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
        let (adapter, _) = makeAdapter(tempDir: tempDir)
        XCTAssertFalse(adapter.detect())
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - readServers()

    func test_readServers_parsesContextServers_intoTwoServers() throws {
        let content = try fixtureContent()
        let servers = try JSONAdapterHelpers.parseServers(from: content, keyPath: ["context_servers"])
        XCTAssertEqual(servers.count, 2)

        let names = Set(servers.map(\.name))
        XCTAssertTrue(names.contains("filesystem"))
        XCTAssertTrue(names.contains("user-zed-server"))

        let fs = servers.first { $0.name == "filesystem" }!
        XCTAssertEqual(fs.command, "npx")
        XCTAssertEqual(fs.args, ["-y", "@modelcontextprotocol/server-filesystem", "/Users/test"])
        XCTAssertEqual(fs.transport, .stdio)
        XCTAssertTrue(fs.enabled)
    }

    func test_readServers_emptyFile_returnsEmptyArray() throws {
        let servers = try JSONAdapterHelpers.parseServers(from: "", keyPath: ["context_servers"])
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
        let writtenServers = try JSONAdapterHelpers.parseServers(from: written, keyPath: ["context_servers"])
        let writtenNames = Set(writtenServers.map(\.name))

        XCTAssertTrue(writtenNames.contains("user-zed-server"), "User-added server should be preserved")
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
            previouslySyncedNames: ["filesystem", "user-zed-server"]
        )

        let written = try String(contentsOf: configPath, encoding: .utf8)
        let writtenServers = try JSONAdapterHelpers.parseServers(from: written, keyPath: ["context_servers"])
        let writtenNames = Set(writtenServers.map(\.name))

        XCTAssertTrue(writtenNames.contains("filesystem"))
        XCTAssertFalse(writtenNames.contains("user-zed-server"), "Orphan should be removed")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_writeServers_preservesNonMCPSettings() throws {
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
        XCTAssertEqual(json?["theme"] as? String, "onedark", "theme should be preserved")

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
