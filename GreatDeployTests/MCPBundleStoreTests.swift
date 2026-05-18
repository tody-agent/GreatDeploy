import XCTest
@testable import GreatDeploy

@MainActor
final class MCPBundleStoreTests: XCTestCase {

    // MARK: - Create Bundle

    func testCreateBundle() throws {
        let store = makeStore()

        let bundle = try store.createBundle(name: "Production")

        XCTAssertEqual(store.bundles.count, 1)
        XCTAssertEqual(store.bundles.first?.name, "Production")
        XCTAssertEqual(store.bundles.first?.id, bundle.id)
        XCTAssertTrue(store.hasBundles)
    }

    func testCreateBundleWithDescription() throws {
        let store = makeStore()

        let bundle = try store.createBundle(name: "Staging", description: "Staging environment servers")

        XCTAssertEqual(store.bundles.first?.bundleDescription, "Staging environment servers")
    }

    // MARK: - Update Bundle

    func testUpdateBundle() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "Old Name")

        var updated = bundle
        updated.name = "New Name"
        updated.bundleDescription = "Updated description"

        try store.updateBundle(updated)

        let result = try XCTUnwrap(store.bundles.first { $0.id == bundle.id })
        XCTAssertEqual(result.name, "New Name")
        XCTAssertEqual(result.bundleDescription, "Updated description")
        XCTAssertGreaterThan(result.updatedAt, bundle.updatedAt)
    }

    func testUpdateNonExistentBundleThrows() throws {
        let store = makeStore()
        let fakeBundle = MCPBundle(name: "Fake")

        XCTAssertThrowsError(try store.updateBundle(fakeBundle)) { error in
            guard case MCPBundleStore.MCPBundleStoreError.bundleNotFound = error else {
                return XCTFail("Expected bundleNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Delete Bundle

    func testDeleteBundle() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "To Delete")

        try store.deleteBundle(bundle)

        XCTAssertEqual(store.bundles.count, 0)
        XCTAssertFalse(store.hasBundles)
    }

    func testDeleteMultipleBundles() throws {
        let store = makeStore()
        let bundle1 = try store.createBundle(name: "First")
        _ = try store.createBundle(name: "Second")
        _ = try store.createBundle(name: "Third")

        try store.deleteBundle(bundle1)

        XCTAssertEqual(store.bundles.count, 2)
        XCTAssertNil(store.bundles.first { $0.name == "First" })
    }

    // MARK: - Add Server

    func testAddServerToBundle() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "API Bundle")

        let server = MCPServerDefinition(name: "GitHub", command: "npx", args: ["-y", "@modelcontextprotocol/server-github"])

        try store.addServer(server, to: bundle.id)

        let result = try XCTUnwrap(store.bundles.first { $0.id == bundle.id })
        XCTAssertEqual(result.servers.count, 1)
        XCTAssertEqual(result.servers.first?.name, "GitHub")
    }

    func testAddDuplicateServerThrows() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "API Bundle")

        let server1 = MCPServerDefinition(name: "GitHub", command: "npx")
        let server2 = MCPServerDefinition(name: "github", command: "npx")

        try store.addServer(server1, to: bundle.id)

        XCTAssertThrowsError(try store.addServer(server2, to: bundle.id)) { error in
            guard case MCPBundleStore.MCPBundleStoreError.duplicateServer = error else {
                return XCTFail("Expected duplicateServer error, got \(error)")
            }
        }
    }

    func testAddServerToNonExistentBundleThrows() throws {
        let store = makeStore()
        let server = MCPServerDefinition(name: "GitHub", command: "npx")

        XCTAssertThrowsError(try store.addServer(server, to: UUID())) { error in
            guard case MCPBundleStore.MCPBundleStoreError.bundleNotFound = error else {
                return XCTFail("Expected bundleNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Remove Server

    func testRemoveServerFromBundle() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "API Bundle")
        let server = MCPServerDefinition(name: "GitHub", command: "npx")
        try store.addServer(server, to: bundle.id)

        try store.removeServer(id: server.id, from: bundle.id)

        let result = try XCTUnwrap(store.bundles.first { $0.id == bundle.id })
        XCTAssertTrue(result.servers.isEmpty)
    }

    func testRemoveNonExistentServer() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "API Bundle")

        try store.removeServer(id: UUID(), from: bundle.id)

        let result = try XCTUnwrap(store.bundles.first { $0.id == bundle.id })
        XCTAssertTrue(result.servers.isEmpty)
    }

    func testRemoveServerFromNonExistentBundleThrows() throws {
        let store = makeStore()

        XCTAssertThrowsError(try store.removeServer(id: UUID(), from: UUID())) { error in
            guard case MCPBundleStore.MCPBundleStoreError.bundleNotFound = error else {
                return XCTFail("Expected bundleNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Update Server

    func testUpdateServerInBundle() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "API Bundle")
        let server = MCPServerDefinition(name: "GitHub", command: "npx", args: ["old-arg"])
        try store.addServer(server, to: bundle.id)

        var updated = server
        updated.name = "GitHub Updated"
        updated.command = "node"
        updated.args = ["new-arg"]

        try store.updateServer(updated, in: bundle.id)

        let result = try XCTUnwrap(store.bundles.first { $0.id == bundle.id })
        let updatedServer = try XCTUnwrap(result.servers.first { $0.id == server.id })
        XCTAssertEqual(updatedServer.name, "GitHub Updated")
        XCTAssertEqual(updatedServer.command, "node")
        XCTAssertEqual(updatedServer.args, ["new-arg"])
    }

    func testUpdateNonExistentServerThrows() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "API Bundle")
        let fakeServer = MCPServerDefinition(name: "Fake", command: "npx")

        XCTAssertThrowsError(try store.updateServer(fakeServer, in: bundle.id)) { error in
            guard case MCPBundleStore.MCPBundleStoreError.serverNotFound = error else {
                return XCTFail("Expected serverNotFound error, got \(error)")
            }
        }
    }

    func testUpdateServerInNonExistentBundleThrows() throws {
        let store = makeStore()
        let server = MCPServerDefinition(name: "GitHub", command: "npx")

        XCTAssertThrowsError(try store.updateServer(server, in: UUID())) { error in
            guard case MCPBundleStore.MCPBundleStoreError.bundleNotFound = error else {
                return XCTFail("Expected bundleNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Persistence Roundtrip

    func testPersistenceRoundtrip() throws {
        let suiteName = "GreatDeployTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let store = MCPBundleStore(userDefaults: userDefaults, fileSystem: MacFileSystem(), startLoading: true)

        let bundle = try store.createBundle(name: "Persisted Bundle")
        let server = MCPServerDefinition(name: "FileSystem", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
        try store.addServer(server, to: bundle.id)

        let newUserDefaults = UserDefaults(suiteName: suiteName)!
        let newStore = MCPBundleStore(userDefaults: newUserDefaults, fileSystem: MacFileSystem(), startLoading: true)

        XCTAssertEqual(newStore.bundles.count, 1)
        let loadedBundle = try XCTUnwrap(newStore.bundles.first)
        XCTAssertEqual(loadedBundle.name, "Persisted Bundle")
        XCTAssertEqual(loadedBundle.servers.count, 1)
        XCTAssertEqual(loadedBundle.servers.first?.name, "FileSystem")
        XCTAssertEqual(loadedBundle.servers.first?.command, "npx")
    }

    func testEmptyStoreLoadsEmpty() throws {
        let suiteName = "GreatDeployTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let store = MCPBundleStore(userDefaults: userDefaults, fileSystem: MacFileSystem(), startLoading: true)

        XCTAssertTrue(store.bundles.isEmpty)
        XCTAssertFalse(store.hasBundles)
        XCTAssertNil(store.activeBundle)
    }

    // MARK: - Sync State

    func testUpdateAndRetrieveSyncState() throws {
        let store = makeStore()

        let state = MCPSyncState(
            clientId: .claudeDesktop,
            lastSyncedAt: Date(),
            lastSyncedServerNames: ["server-a"],
            previouslySyncedNames: ["server-a", "server-b"]
        )

        store.updateSyncState(state)

        let retrieved = try XCTUnwrap(store.syncState(for: .claudeDesktop))
        XCTAssertEqual(retrieved.clientId, .claudeDesktop)
        XCTAssertEqual(retrieved.lastSyncedServerNames, ["server-a"])
        XCTAssertTrue(retrieved.previouslySyncedNames.contains("server-a"))
    }

    func testSyncStateForUnknownClientReturnsNil() throws {
        let store = makeStore()

        XCTAssertNil(store.syncState(for: .cursor))
    }

    func testSyncStatePersistence() throws {
        let suiteName = "GreatDeployTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let store = MCPBundleStore(userDefaults: userDefaults, fileSystem: MacFileSystem(), startLoading: true)

        let state = MCPSyncState(clientId: .cursor, lastSyncedServerNames: ["server-x"], previouslySyncedNames: ["server-x"])
        store.updateSyncState(state)

        let newUserDefaults = UserDefaults(suiteName: suiteName)!
        let newStore = MCPBundleStore(userDefaults: newUserDefaults, fileSystem: MacFileSystem(), startLoading: true)

        let retrieved = try XCTUnwrap(newStore.syncState(for: .cursor))
        XCTAssertEqual(retrieved.lastSyncedServerNames, ["server-x"])
    }

    // MARK: - Active Bundle

    func testActiveBundleReturnsFirstWhenNoneActive() throws {
        let store = makeStore()
        _ = try store.createBundle(name: "First")
        _ = try store.createBundle(name: "Second")

        XCTAssertEqual(store.activeBundle?.name, "First")
    }

    func testActiveBundleReturnsMarkedActive() throws {
        let store = makeStore()
        let bundle1 = try store.createBundle(name: "First")
        _ = try store.createBundle(name: "Second")

        var updated = bundle1
        updated.isActive = true
        try store.updateBundle(updated)

        XCTAssertEqual(store.activeBundle?.name, "First")
    }

    // MARK: - Computed Properties

    func testServerCount() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "Bundle")
        try store.addServer(MCPServerDefinition(name: "S1", command: "cmd1"), to: bundle.id)
        try store.addServer(MCPServerDefinition(name: "S2", command: "cmd2"), to: bundle.id)

        let result = try XCTUnwrap(store.bundles.first)
        XCTAssertEqual(result.serverCount, 2)
    }

    func testEnabledServers() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "Bundle")
        let enabled = MCPServerDefinition(name: "Enabled", enabled: true, command: "cmd")
        let disabled = MCPServerDefinition(name: "Disabled", enabled: false, command: "cmd")
        try store.addServer(enabled, to: bundle.id)
        try store.addServer(disabled, to: bundle.id)

        let result = try XCTUnwrap(store.bundles.first)
        XCTAssertEqual(result.enabledServers.count, 1)
        XCTAssertEqual(result.enabledServers.first?.name, "Enabled")
    }

    // MARK: - Helpers

    private func makeStore() -> MCPBundleStore {
        let suiteName = "GreatDeployTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return MCPBundleStore(userDefaults: userDefaults, fileSystem: MacFileSystem(), startLoading: true)
    }
}
