import XCTest
@testable import GreatDeploy

// MARK: - Mock MCP Client Adapter

final class MockMCPClientAdapter: MCPClientAdapter, @unchecked Sendable {
    let kind: MCPClientKind
    var displayName: String { kind.displayName }

    var detectResult: Bool = true
    var configPathResult: URL?
    var readServersResult: [MCPServerDefinition] = []
    var readServersError: Error?
    var writeServersError: Error?

    var writeServersCallCount = 0
    var lastWrittenServers: [MCPServerDefinition] = []
    var lastWrittenExistingContent: String?
    var lastWrittenPreviouslySyncedNames: Set<String> = []

    init(kind: MCPClientKind) {
        self.kind = kind
    }

    func detect() -> Bool { detectResult }
    func configPath() -> URL? { configPathResult }

    func readServers() throws -> [MCPServerDefinition] {
        if let error = readServersError { throw error }
        return readServersResult
    }

    func writeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws {
        writeServersCallCount += 1
        lastWrittenServers = servers
        lastWrittenExistingContent = existingContent
        lastWrittenPreviouslySyncedNames = previouslySyncedNames
        if let error = writeServersError { throw error }
    }
}

// MARK: - Tests

@MainActor
final class MCPSyncEngineTests: XCTestCase {

    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
        try await super.tearDown()
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GreatDeployTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func makeTestServer(name: String, secretKeys: [String] = []) -> MCPServerDefinition {
        MCPServerDefinition(
            name: name,
            serverDescription: "Test server \(name)",
            enabled: true,
            transport: .stdio,
            command: "test-command",
            secretEnvKeys: secretKeys
        )
    }

    private func makeTestBundle(id: UUID = UUID(), servers: [MCPServerDefinition]) -> MCPBundle {
        MCPBundle(
            id: id,
            name: "Test Bundle",
            bundleDescription: "Test",
            servers: servers,
            enabledClients: [],
            isActive: false
        )
    }

    // MARK: - Test 1: Client not installed → skip with success=true

    func testSyncClientNotInstalled() async {
        let mock = MockMCPClientAdapter(kind: .cursor)
        mock.detectResult = false

        let bundleStore = MCPBundleStore(startLoading: false)
        let auditLogger = AuditLogger()
        let engine = MCPSyncEngine(
            bundleStore: bundleStore,
            auditLogger: auditLogger,
            makeAdapter: { _ in mock }
        )

        let bundle = makeTestBundle(servers: [makeTestServer(name: "test-server")])
        let results = await engine.sync(bundle: bundle, toClients: [.cursor])

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertEqual(results[0].serversWritten, 0)
        XCTAssertEqual(results[0].warnings, ["Client not installed"])
    }

    // MARK: - Test 2: Single client, 3 servers → all success

    func testSyncSingleClientThreeServers() async {
        let tempDir = try! makeTempDirectory()
        let configURL = tempDir.appendingPathComponent("mcp.json")

        let server1 = makeTestServer(name: "server-1")
        let server2 = makeTestServer(name: "server-2")
        let server3 = makeTestServer(name: "server-3")

        let mock = MockMCPClientAdapter(kind: .cursor)
        mock.detectResult = true
        mock.configPathResult = configURL
        mock.readServersResult = [server1, server2, server3]

        let bundleStore = MCPBundleStore(startLoading: false)
        let auditLogger = AuditLogger()
        let engine = MCPSyncEngine(
            bundleStore: bundleStore,
            auditLogger: auditLogger,
            makeAdapter: { _ in mock }
        )

        let bundle = makeTestBundle(servers: [server1, server2, server3])
        let results = await engine.sync(bundle: bundle, toClients: [.cursor])

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertEqual(results[0].serversWritten, 3)
        XCTAssertEqual(mock.writeServersCallCount, 1)
    }

    // MARK: - Test 3: Keychain miss for 1 server → warning, still sync

    func testSyncKeychainMissingSecret() async {
        let tempDir = try! makeTempDirectory()
        let configURL = tempDir.appendingPathComponent("mcp.json")

        let server = makeTestServer(name: "secret-server", secretKeys: ["API_KEY"])

        let mock = MockMCPClientAdapter(kind: .cursor)
        mock.detectResult = true
        mock.configPathResult = configURL
        mock.readServersResult = [server]

        let bundleStore = MCPBundleStore(startLoading: false)
        let auditLogger = AuditLogger()
        let engine = MCPSyncEngine(
            bundleStore: bundleStore,
            auditLogger: auditLogger,
            makeAdapter: { _ in mock }
        )

        let bundle = makeTestBundle(servers: [server])
        let results = await engine.sync(bundle: bundle, toClients: [.cursor])

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertEqual(results[0].serversWritten, 1)
    }

    // MARK: - Test 4: Verify fail → rollback

    func testSyncVerificationFailRollback() async {
        let tempDir = try! makeTempDirectory()
        let configURL = tempDir.appendingPathComponent("mcp.json")

        let existingContent = "{\"mcpServers\":{}}"
        try! existingContent.write(to: configURL, atomically: true, encoding: .utf8)

        let server = makeTestServer(name: "test-server")

        let mock = MockMCPClientAdapter(kind: .cursor)
        mock.detectResult = true
        mock.configPathResult = configURL
        mock.readServersResult = []

        let bundleStore = MCPBundleStore(startLoading: false)
        let auditLogger = AuditLogger()
        let engine = MCPSyncEngine(
            bundleStore: bundleStore,
            auditLogger: auditLogger,
            makeAdapter: { _ in mock }
        )

        let bundle = makeTestBundle(servers: [server])
        let results = await engine.sync(bundle: bundle, toClients: [.cursor])

        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success)
        XCTAssertNotNil(results[0].error)
        XCTAssertTrue(results[0].error?.contains("Verification failed") ?? false)

        let contentAfter = try! String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(contentAfter, existingContent)
    }

    // MARK: - Test 5: Adapter throws on write → error result

    func testSyncWriteThrows() async {
        let tempDir = try! makeTempDirectory()
        let configURL = tempDir.appendingPathComponent("mcp.json")

        let existingContent = "{\"mcpServers\":{}}"
        try! existingContent.write(to: configURL, atomically: true, encoding: .utf8)

        let server = makeTestServer(name: "test-server")

        struct TestWriteError: LocalizedError {
            var errorDescription: String? { "Write failed" }
        }

        let mock = MockMCPClientAdapter(kind: .cursor)
        mock.detectResult = true
        mock.configPathResult = configURL
        mock.writeServersError = TestWriteError()

        let bundleStore = MCPBundleStore(startLoading: false)
        let auditLogger = AuditLogger()
        let engine = MCPSyncEngine(
            bundleStore: bundleStore,
            auditLogger: auditLogger,
            makeAdapter: { _ in mock }
        )

        let bundle = makeTestBundle(servers: [server])
        let results = await engine.sync(bundle: bundle, toClients: [.cursor])

        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success)
        XCTAssertEqual(results[0].error, "Write failed")

        let contentAfter = try! String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(contentAfter, existingContent)
    }

    // MARK: - Test 6: previouslySyncedNames cumulative after sync

    func testSyncStateCumulative() async {
        let tempDir = try! makeTempDirectory()
        let configURL = tempDir.appendingPathComponent("mcp.json")

        let server1 = makeTestServer(name: "server-1")
        let server2 = makeTestServer(name: "server-2")

        let mock = MockMCPClientAdapter(kind: .cursor)
        mock.detectResult = true
        mock.configPathResult = configURL
        mock.readServersResult = [server1, server2]

        let bundleStore = MCPBundleStore(startLoading: false)
        let auditLogger = AuditLogger()
        let engine = MCPSyncEngine(
            bundleStore: bundleStore,
            auditLogger: auditLogger,
            makeAdapter: { _ in mock }
        )

        let bundle = makeTestBundle(servers: [server1, server2])
        _ = await engine.sync(bundle: bundle, toClients: [.cursor])

        let syncState = bundleStore.syncState(for: .cursor)
        XCTAssertNotNil(syncState)
        XCTAssertEqual(syncState?.previouslySyncedNames, Set(["server-1", "server-2"]))
        XCTAssertEqual(syncState?.lastSyncedServerNames, ["server-1", "server-2"])
    }

    // MARK: - Test 7: Audit log → grep for token-like strings → 0 matches

    func testAuditLogNoSecrets() async throws {
        let tempDir = try! makeTempDirectory()
        let configURL = tempDir.appendingPathComponent("mcp.json")

        let bundleId = UUID()
        let serverId = UUID()
        let secretValue = "super-secret-token-abc123xyz"

        try? KeychainService.shared.saveMCPSecret(
            bundleId: bundleId,
            serverId: serverId,
            envKey: "API_KEY",
            value: secretValue
        )

        let server = MCPServerDefinition(
            id: serverId,
            name: "secret-server",
            enabled: true,
            transport: .stdio,
            command: "test",
            secretEnvKeys: ["API_KEY"]
        )

        let mock = MockMCPClientAdapter(kind: .cursor)
        mock.detectResult = true
        mock.configPathResult = configURL
        mock.readServersResult = [server]

        let bundleStore = MCPBundleStore(startLoading: false)
        let auditLogger = AuditLogger()
        let engine = MCPSyncEngine(
            bundleStore: bundleStore,
            keychainService: KeychainService.shared,
            auditLogger: auditLogger,
            makeAdapter: { _ in mock }
        )

        let bundle = MCPBundle(
            id: bundleId,
            name: "Secret Bundle",
            servers: [server]
        )
        _ = await engine.sync(bundle: bundle, toClients: [.cursor])

        try? await Task.sleep(nanoseconds: 200_000_000)

        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GreatDeploy/mcp-audit.log")

        if let content = try? String(contentsOf: logFile, encoding: .utf8) {
            XCTAssertFalse(
                content.contains(secretValue),
                "Audit log must NOT contain secret values"
            )
        }

        try? KeychainService.shared.deleteMCPSecret(
            bundleId: bundleId,
            serverId: serverId,
            envKey: "API_KEY"
        )
    }

    // MARK: - Test 8: Multiple clients, some installed some not → mixed results

    func testSyncMultipleClientsMixed() async {
        let tempDir = try! makeTempDirectory()
        let cursorConfigURL = tempDir.appendingPathComponent("cursor-mcp.json")

        let server = makeTestServer(name: "test-server")

        let cursorMock = MockMCPClientAdapter(kind: .cursor)
        cursorMock.detectResult = true
        cursorMock.configPathResult = cursorConfigURL
        cursorMock.readServersResult = [server]

        let claudeMock = MockMCPClientAdapter(kind: .claudeCode)
        claudeMock.detectResult = false

        let bundleStore = MCPBundleStore(startLoading: false)
        let auditLogger = AuditLogger()
        let engine = MCPSyncEngine(
            bundleStore: bundleStore,
            auditLogger: auditLogger,
            makeAdapter: { kind in
                switch kind {
                case .cursor: return cursorMock
                case .claudeCode: return claudeMock
                default: return kind.makeAdapter()
                }
            }
        )

        let bundle = makeTestBundle(servers: [server])
        let results = await engine.sync(bundle: bundle, toClients: [.cursor, .claudeCode])

        XCTAssertEqual(results.count, 2)

        let cursorResult = results.first { $0.client == .cursor }
        let claudeResult = results.first { $0.client == .claudeCode }

        XCTAssertNotNil(cursorResult)
        XCTAssertTrue(cursorResult?.success ?? false)
        XCTAssertEqual(cursorResult?.serversWritten, 1)

        XCTAssertNotNil(claudeResult)
        XCTAssertTrue(claudeResult?.success ?? false)
        XCTAssertEqual(claudeResult?.serversWritten, 0)
        XCTAssertEqual(claudeResult?.warnings, ["Client not installed"])
    }
}
