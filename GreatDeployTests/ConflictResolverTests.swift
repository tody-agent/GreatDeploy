import XCTest
@testable import GreatDeploy

final class ConflictResolverTests: XCTestCase {

    // MARK: - Test Data Helpers

    private func makeServer(
        id: UUID = UUID(),
        name: String,
        updatedAt: Date,
        command: String = "npx",
        args: [String] = [],
        secretEnvKeys: [String] = []
    ) -> MCPServerDefinition {
        MCPServerDefinition(
            id: id,
            name: name,
            command: command,
            args: args,
            secretEnvKeys: secretEnvKeys,
            updatedAt: updatedAt
        )
    }

    private func makeBundle(
        id: UUID = UUID(),
        name: String,
        servers: [MCPServerDefinition],
        updatedAt: Date
    ) -> MCPBundle {
        MCPBundle(
            id: id,
            name: name,
            servers: servers,
            updatedAt: updatedAt
        )
    }

    // MARK: - 1. Remote newer → replace local

    func testRemoteNewerReplacesLocal() {
        let older = Date(timeIntervalSinceNow: -100)
        let newer = Date(timeIntervalSinceNow: -50)
        let serverId = UUID()
        let bundleId = UUID()

        let localServer = makeServer(id: serverId, name: "GitHub", updatedAt: older, args: ["old-arg"])
        let remoteServer = makeServer(id: serverId, name: "GitHub", updatedAt: newer, args: ["new-arg"])

        let localBundle = makeBundle(id: bundleId, name: "Test", servers: [localServer], updatedAt: older)
        let remoteBundle = makeBundle(id: bundleId, name: "Test", servers: [remoteServer], updatedAt: newer)

        let result = ConflictResolver.merge(local: [localBundle], remote: [remoteBundle])

        XCTAssertEqual(result.mergedBundles.count, 1)
        let mergedServer = result.mergedBundles.first?.servers.first
        XCTAssertEqual(mergedServer?.args, ["new-arg"])
        XCTAssertEqual(result.conflicts.count, 0)
    }

    // MARK: - 2. Local newer → keep local

    func testLocalNewerKeepsLocal() {
        let older = Date(timeIntervalSinceNow: -100)
        let newer = Date(timeIntervalSinceNow: -50)
        let serverId = UUID()
        let bundleId = UUID()

        let localServer = makeServer(id: serverId, name: "GitHub", updatedAt: newer, args: ["local-arg"])
        let remoteServer = makeServer(id: serverId, name: "GitHub", updatedAt: older, args: ["remote-arg"])

        let localBundle = makeBundle(id: bundleId, name: "Test", servers: [localServer], updatedAt: newer)
        let remoteBundle = makeBundle(id: bundleId, name: "Test", servers: [remoteServer], updatedAt: older)

        let result = ConflictResolver.merge(local: [localBundle], remote: [remoteBundle])

        XCTAssertEqual(result.mergedBundles.count, 1)
        let mergedServer = result.mergedBundles.first?.servers.first
        XCTAssertEqual(mergedServer?.args, ["local-arg"])
        XCTAssertEqual(result.conflicts.count, 0)
    }

    // MARK: - 3. Same timestamp, same content → no-op

    func testSameTimestampSameContentIsNoOp() {
        let timestamp = Date(timeIntervalSinceNow: -100)
        let serverId = UUID()
        let bundleId = UUID()

        let server = makeServer(id: serverId, name: "GitHub", updatedAt: timestamp, args: ["same-arg"])

        let localBundle = makeBundle(id: bundleId, name: "Test", servers: [server], updatedAt: timestamp)
        let remoteBundle = makeBundle(id: bundleId, name: "Test", servers: [server], updatedAt: timestamp)

        let result = ConflictResolver.merge(local: [localBundle], remote: [remoteBundle])

        XCTAssertEqual(result.mergedBundles.count, 1)
        XCTAssertEqual(result.mergedBundles.first?.servers.count, 1)
        XCTAssertEqual(result.conflicts.count, 0)
    }

    // MARK: - 4. Same timestamp, different content → flag conflict, keep local

    func testSameTimestampDifferentContentFlagsConflict() {
        let timestamp = Date(timeIntervalSinceNow: -100)
        let serverId = UUID()
        let bundleId = UUID()

        let localServer = makeServer(id: serverId, name: "GitHub", updatedAt: timestamp, args: ["local-arg"])
        let remoteServer = makeServer(id: serverId, name: "GitHub", updatedAt: timestamp, args: ["remote-arg"])

        let localBundle = makeBundle(id: bundleId, name: "Test", servers: [localServer], updatedAt: timestamp)
        let remoteBundle = makeBundle(id: bundleId, name: "Test", servers: [remoteServer], updatedAt: timestamp)

        let result = ConflictResolver.merge(local: [localBundle], remote: [remoteBundle])

        XCTAssertEqual(result.conflicts.count, 1)
        let conflict = result.conflicts.first
        XCTAssertEqual(conflict?.serverName, "GitHub")
        XCTAssertEqual(conflict?.resolution, .unresolved)

        let mergedServer = result.mergedBundles.first?.servers.first
        XCTAssertEqual(mergedServer?.args, ["local-arg"])
    }

    // MARK: - 5. New server on remote → added to merged

    func testNewServerOnRemoteIsAdded() {
        let timestamp = Date()
        let bundleId = UUID()
        let sharedServerId = UUID()
        let newServerId = UUID()

        let sharedServer = makeServer(id: sharedServerId, name: "GitHub", updatedAt: timestamp)
        let newServer = makeServer(id: newServerId, name: "NewServer", updatedAt: timestamp)

        let localBundle = makeBundle(id: bundleId, name: "Test", servers: [sharedServer], updatedAt: timestamp)
        let remoteBundle = makeBundle(id: bundleId, name: "Test", servers: [sharedServer, newServer], updatedAt: timestamp)

        let result = ConflictResolver.merge(local: [localBundle], remote: [remoteBundle])

        XCTAssertEqual(result.mergedBundles.count, 1)
        XCTAssertEqual(result.mergedBundles.first?.servers.count, 2)
        let serverNames = result.mergedBundles.first?.servers.map { $0.name }
        XCTAssertTrue(serverNames?.contains("NewServer") ?? false)
    }

    // MARK: - 6. Server deleted on remote → kept in local (no delete detection in v1)

    func testServerDeletedOnRemoteKeptInLocal() {
        let timestamp = Date()
        let bundleId = UUID()
        let server1Id = UUID()
        let server2Id = UUID()

        let localServer1 = makeServer(id: server1Id, name: "GitHub", updatedAt: timestamp)
        let localServer2 = makeServer(id: server2Id, name: "ToDelete", updatedAt: timestamp)
        let remoteServer1 = makeServer(id: server1Id, name: "GitHub", updatedAt: timestamp)

        let localBundle = makeBundle(id: bundleId, name: "Test", servers: [localServer1, localServer2], updatedAt: timestamp)
        let remoteBundle = makeBundle(id: bundleId, name: "Test", servers: [remoteServer1], updatedAt: timestamp)

        let result = ConflictResolver.merge(local: [localBundle], remote: [remoteBundle])

        XCTAssertEqual(result.mergedBundles.count, 1)
        XCTAssertEqual(result.mergedBundles.first?.servers.count, 2)
    }

    // MARK: - 7. hasMissingSecrets → true when Keychain miss

    func testHasMissingSecretsReturnsTrueWhenKeychainMiss() {
        let server = MCPServerDefinition(
            name: "SecretServer",
            command: "npx",
            secretEnvKeys: ["API_KEY", "DB_PASSWORD"]
        )
        let bundleId = UUID()

        let hasMissing = ConflictResolver.hasMissingSecrets(
            server: server,
            bundleId: bundleId,
            keychainService: KeychainService.shared
        )

        XCTAssertTrue(hasMissing)
    }

    // MARK: - 8. hasMissingSecrets → false when all secrets present

    func testHasMissingSecretsReturnsFalseWhenAllSecretsPresent() throws {
        let server = MCPServerDefinition(
            name: "SecretServer",
            command: "npx",
            secretEnvKeys: ["TEST_SECRET_KEY"]
        )
        let bundleId = UUID()
        let serverId = server.id

        try KeychainService.shared.saveMCPSecret(
            bundleId: bundleId,
            serverId: serverId,
            envKey: "TEST_SECRET_KEY",
            value: "test-value"
        )

        let hasMissing = ConflictResolver.hasMissingSecrets(
            server: server,
            bundleId: bundleId,
            keychainService: KeychainService.shared
        )

        XCTAssertFalse(hasMissing)

        try KeychainService.shared.deleteMCPSecret(
            bundleId: bundleId,
            serverId: serverId,
            envKey: "TEST_SECRET_KEY"
        )
    }

    // MARK: - 9. Empty local + remote → all remote kept

    func testEmptyLocalKeepsAllRemote() {
        let timestamp = Date()
        let remoteServer = makeServer(name: "RemoteOnly", updatedAt: timestamp)
        let remoteBundle = makeBundle(name: "Remote Bundle", servers: [remoteServer], updatedAt: timestamp)

        let result = ConflictResolver.merge(local: [], remote: [remoteBundle])

        XCTAssertEqual(result.mergedBundles.count, 1)
        XCTAssertEqual(result.mergedBundles.first?.name, "Remote Bundle")
        XCTAssertEqual(result.conflicts.count, 0)
    }

    // MARK: - 10. Empty remote + local → all local kept

    func testEmptyRemoteKeepsAllLocal() {
        let timestamp = Date()
        let localServer = makeServer(name: "LocalOnly", updatedAt: timestamp)
        let localBundle = makeBundle(name: "Local Bundle", servers: [localServer], updatedAt: timestamp)

        let result = ConflictResolver.merge(local: [localBundle], remote: [])

        XCTAssertEqual(result.mergedBundles.count, 1)
        XCTAssertEqual(result.mergedBundles.first?.name, "Local Bundle")
        XCTAssertEqual(result.conflicts.count, 0)
    }

    // MARK: - Additional: hasMissingSecrets with no secret keys

    func testHasMissingSecretsReturnsFalseWhenNoSecretKeys() {
        let server = MCPServerDefinition(
            name: "NoSecrets",
            command: "npx",
            secretEnvKeys: []
        )

        let hasMissing = ConflictResolver.hasMissingSecrets(
            server: server,
            bundleId: UUID(),
            keychainService: KeychainService.shared
        )

        XCTAssertFalse(hasMissing)
    }

    // MARK: - Additional: Multiple bundles merge

    func testMultipleBundlesMergeCorrectly() {
        let older = Date(timeIntervalSinceNow: -100)
        let newer = Date(timeIntervalSinceNow: -50)

        let server1 = makeServer(name: "S1", updatedAt: older)
        let server2 = makeServer(name: "S2", updatedAt: newer)

        let localBundle1 = makeBundle(name: "Bundle A", servers: [server1], updatedAt: older)
        let remoteBundle2 = makeBundle(name: "Bundle B", servers: [server2], updatedAt: newer)

        let result = ConflictResolver.merge(local: [localBundle1], remote: [remoteBundle2])

        XCTAssertEqual(result.mergedBundles.count, 2)
        let names = Set(result.mergedBundles.map { $0.name })
        XCTAssertTrue(names.contains("Bundle A"))
        XCTAssertTrue(names.contains("Bundle B"))
    }
}
