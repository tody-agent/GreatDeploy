import XCTest
@testable import GreatDeploy

@MainActor
final class MCPSyncAdapterTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeBundle(
        enabledClients: Set<MCPClientKind>,
        servers: [MCPServerDefinition] = []
    ) -> MCPBundle {
        MCPBundle(
            name: "Test Bundle",
            bundleDescription: "",
            servers: servers,
            enabledClients: enabledClients
        )
    }

    private func makeServer(
        name: String,
        env: [String: String] = [:],
        secretEnvKeys: [String] = []
    ) -> MCPServerDefinition {
        MCPServerDefinition(
            name: name,
            env: env,
            secretEnvKeys: secretEnvKeys
        )
    }

    // MARK: - 1. snapshot() captures existing content for each enabled client

    func test_snapshot_capturesExistingContent() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let configPath = tempDir.appendingPathComponent("claude_desktop_config.json")
        let existingContent = """
        {
            "mcpServers": {
                "old-server": { "command": "echo" }
            }
        }
        """
        try existingContent.write(to: configPath, atomically: true, encoding: .utf8)

        let fileSystem = TestFileSystem(configURL: configPath)

        let server = makeServer(name: "test-server")
        let bundle = makeBundle(enabledClients: [.claudeDesktop], servers: [server])

        let store = MCPBundleStore(startLoading: false)
        let syncAdapter = MCPSyncAdapter(
            bundleStore: store,
            keychainService: KeychainService.shared,
            fileSystem: fileSystem
        )

        let snapshot = syncAdapter.snapshot(for: bundle)

        let captured = snapshot.clientContents[.claudeDesktop]
        if case let content?? = captured {
            XCTAssertEqual(
                content.trimmingCharacters(in: .whitespacesAndNewlines),
                existingContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            XCTFail("Expected captured content")
        }
    }

    // MARK: - 2. snapshot() captures sync state for each enabled client

    func test_snapshot_capturesSyncState() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let configPath = tempDir.appendingPathComponent("claude_desktop_config.json")
        try "{}".write(to: configPath, atomically: true, encoding: .utf8)

        let fileSystem = TestFileSystem(configURL: configPath)
        let store = MCPBundleStore(startLoading: false)

        let existingState = MCPSyncState(
            clientId: .claudeDesktop,
            lastSyncedAt: Date.distantPast,
            lastSyncedServerNames: ["old-server"],
            previouslySyncedNames: ["old-server", "another-server"]
        )
        store.updateSyncState(existingState)

        let server = makeServer(name: "test-server")
        let bundle = makeBundle(enabledClients: [.claudeDesktop], servers: [server])

        let syncAdapter = MCPSyncAdapter(
            bundleStore: store,
            keychainService: KeychainService.shared,
            fileSystem: fileSystem
        )

        let snapshot = syncAdapter.snapshot(for: bundle)

        let capturedState = snapshot.previousStates[.claudeDesktop]
        XCTAssertNotNil(capturedState)
        XCTAssertTrue(capturedState!.previouslySyncedNames.contains("old-server"))
        XCTAssertTrue(capturedState!.previouslySyncedNames.contains("another-server"))
    }

    // MARK: - 3. sync() → client not installed → skip with success=true

    func test_sync_skipsNotInstalledClient() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let configPath = tempDir.appendingPathComponent("nonexistent_config.json")

        let fileSystem = TestFileSystem(configURL: configPath)

        let server = makeServer(name: "test-server")
        let bundle = makeBundle(enabledClients: [.claudeDesktop], servers: [server])

        let store = MCPBundleStore(startLoading: false)
        let syncAdapter = MCPSyncAdapter(
            bundleStore: store,
            keychainService: KeychainService.shared,
            fileSystem: fileSystem
        )

        let results = await syncAdapter.sync(bundle: bundle)

        XCTAssertEqual(results.count, 1)
        let result = results[0]
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.serversWritten, 0)
        XCTAssertTrue(result.warnings.contains("Client not installed"))
    }

    // MARK: - 4. sync() → injects secrets from Keychain before write

    func test_sync_injectsSecretsFromKeychain() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let configPath = tempDir.appendingPathComponent("claude_desktop_config.json")
        try "{}".write(to: configPath, atomically: true, encoding: .utf8)

        let fileSystem = TestFileSystem(configURL: configPath)
        let store = MCPBundleStore(startLoading: false)

        let server = makeServer(
            name: "secret-server",
            env: ["API_KEY": ""],
            secretEnvKeys: ["API_KEY"]
        )
        let bundle = makeBundle(enabledClients: [.claudeDesktop], servers: [server])

        let keychain = KeychainService.shared
        try keychain.saveMCPSecret(
            bundleId: bundle.id,
            serverId: server.id,
            envKey: "API_KEY",
            value: "super-secret-value"
        )
        defer {
            try? keychain.deleteMCPSecret(bundleId: bundle.id, serverId: server.id, envKey: "API_KEY")
        }

        let syncAdapter = MCPSyncAdapter(
            bundleStore: store,
            keychainService: keychain,
            fileSystem: fileSystem
        )

        let results = await syncAdapter.sync(bundle: bundle)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertEqual(results[0].serversWritten, 1)

        let written = try String(contentsOf: configPath, encoding: .utf8)
        let parsedServers = try JSONAdapterHelpers.parseServers(from: written)
        let writtenServer = parsedServers.first { $0.name == "secret-server" }
        XCTAssertNotNil(writtenServer)
        XCTAssertEqual(writtenServer?.env["API_KEY"], "super-secret-value")
    }

    // MARK: - 5. sync() → updates sync state after successful write

    func test_sync_updatesSyncState() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let configPath = tempDir.appendingPathComponent("claude_desktop_config.json")
        try "{}".write(to: configPath, atomically: true, encoding: .utf8)

        let fileSystem = TestFileSystem(configURL: configPath)
        let store = MCPBundleStore(startLoading: false)

        let server = makeServer(name: "state-server")
        let bundle = makeBundle(enabledClients: [.claudeDesktop], servers: [server])

        let syncAdapter = MCPSyncAdapter(
            bundleStore: store,
            keychainService: KeychainService.shared,
            fileSystem: fileSystem
        )

        _ = await syncAdapter.sync(bundle: bundle)

        let state = store.syncState(for: .claudeDesktop)
        XCTAssertNotNil(state)
        XCTAssertTrue(state!.previouslySyncedNames.contains("state-server"))
        XCTAssertEqual(state!.lastSyncedServerNames, ["state-server"])
        XCTAssertNotNil(state!.lastSyncedAt)
    }

    // MARK: - 6. revert() → restores previous content

    func test_revert_restoresPreviousContent() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let configPath = tempDir.appendingPathComponent("claude_desktop_config.json")
        let originalContent = """
        {
            "mcpServers": {
                "original-server": { "command": "echo" }
            }
        }
        """
        try originalContent.write(to: configPath, atomically: true, encoding: .utf8)

        let fileSystem = TestFileSystem(configURL: configPath)
        let store = MCPBundleStore(startLoading: false)

        let server = makeServer(name: "new-server")
        let bundle = makeBundle(enabledClients: [.claudeDesktop], servers: [server])

        let syncAdapter = MCPSyncAdapter(
            bundleStore: store,
            keychainService: KeychainService.shared,
            fileSystem: fileSystem
        )

        let snapshot = syncAdapter.snapshot(for: bundle)

        try ClaudeDesktopAdapter(fileSystem: fileSystem, overrideConfigPath: configPath)
            .writeServers([server], existingContent: originalContent, previouslySyncedNames: [])

        let writtenBeforeRevert = try String(contentsOf: configPath, encoding: .utf8)
        let parsedBefore = try JSONAdapterHelpers.parseServers(from: writtenBeforeRevert)
        XCTAssertTrue(parsedBefore.contains { $0.name == "new-server" })

        await syncAdapter.revert(to: snapshot)

        let restored = try String(contentsOf: configPath, encoding: .utf8)
        let parsedAfter = try JSONAdapterHelpers.parseServers(from: restored)
        XCTAssertTrue(parsedAfter.contains { $0.name == "original-server" })
        XCTAssertFalse(parsedAfter.contains { $0.name == "new-server" })
    }

    // MARK: - 7. revert() → restores previous sync states

    func test_revert_restoresPreviousSyncStates() async throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let configPath = tempDir.appendingPathComponent("claude_desktop_config.json")
        try "{}".write(to: configPath, atomically: true, encoding: .utf8)

        let fileSystem = TestFileSystem(configURL: configPath)
        let store = MCPBundleStore(startLoading: false)

        let originalState = MCPSyncState(
            clientId: .claudeDesktop,
            lastSyncedAt: Date.distantPast,
            lastSyncedServerNames: ["old-server"],
            previouslySyncedNames: ["old-server"]
        )
        store.updateSyncState(originalState)

        let server = makeServer(name: "new-server")
        let bundle = makeBundle(enabledClients: [.claudeDesktop], servers: [server])

        let syncAdapter = MCPSyncAdapter(
            bundleStore: store,
            keychainService: KeychainService.shared,
            fileSystem: fileSystem
        )

        let snapshot = syncAdapter.snapshot(for: bundle)

        _ = await syncAdapter.sync(bundle: bundle)

        let stateAfterSync = store.syncState(for: .claudeDesktop)
        XCTAssertTrue(stateAfterSync!.previouslySyncedNames.contains("new-server"))

        await syncAdapter.revert(to: snapshot)

        let restoredState = store.syncState(for: .claudeDesktop)
        XCTAssertNotNil(restoredState)
        XCTAssertTrue(restoredState!.previouslySyncedNames.contains("old-server"))
        XCTAssertFalse(restoredState!.previouslySyncedNames.contains("new-server"))
        XCTAssertEqual(restoredState!.lastSyncedServerNames, ["old-server"])
    }

    // MARK: - 8. injectSecrets() → missing secret → server continues without it (no error)

    func test_injectSecrets_missingSecret_continuesWithoutError() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let fileSystem = TestFileSystem(configURL: tempDir)
        let store = MCPBundleStore(startLoading: false)
        let keychain = KeychainService.shared

        let server = makeServer(
            name: "partial-secret-server",
            env: ["MISSING_KEY": "", "ALSO_MISSING": ""],
            secretEnvKeys: ["MISSING_KEY", "ALSO_MISSING"]
        )
        let bundle = makeBundle(enabledClients: [], servers: [server])

        let syncAdapter = MCPSyncAdapter(
            bundleStore: store,
            keychainService: keychain,
            fileSystem: fileSystem
        )

        let enriched = try syncAdapter.injectSecrets([server], for: bundle.id)

        XCTAssertEqual(enriched.count, 1)
        let enrichedServer = enriched[0]
        XCTAssertEqual(enrichedServer.env["MISSING_KEY"], "")
        XCTAssertEqual(enrichedServer.env["ALSO_MISSING"], "")
    }
}
