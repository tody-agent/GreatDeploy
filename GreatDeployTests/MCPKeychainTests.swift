import XCTest
@testable import GreatDeploy

final class MCPKeychainTests: XCTestCase {

    private var sut: KeychainService!

    override func setUp() {
        super.setUp()
        sut = KeychainService.shared
        cleanupTestData()
    }

    override func tearDown() {
        cleanupTestData()
        sut = nil
        super.tearDown()
    }

    private func cleanupTestData() {
        let testBundleId = UUID()
        let testServerId = UUID()
        let testEnvKeys = ["TEST_KEY", "ANOTHER_KEY", "MY_API-KEY.2"]

        for envKey in testEnvKeys {
            try? sut.deleteMCPSecret(bundleId: testBundleId, serverId: testServerId, envKey: envKey)
        }

        // Cleanup from isolation tests
        let bundleA = UUID()
        let bundleB = UUID()
        let serverA = UUID()
        let serverB = UUID()
        try? sut.deleteAllMCPSecrets(bundleId: bundleA)
        try? sut.deleteAllMCPSecrets(bundleId: bundleB)
        try? sut.deleteAllMCPSecrets(bundleId: testBundleId)
    }

    // MARK: - Save and Read

    func testSaveAndReadMCPSecret() throws {
        let bundleId = UUID()
        let serverId = UUID()
        let envKey = "DATABASE_URL"
        let value = "postgres://user:pass@localhost:5432/db"

        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey, value: value)
        let retrieved = sut.readMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey)

        XCTAssertEqual(retrieved, value)

        try sut.deleteMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey)
    }

    func testReadNonExistentMCPSecretReturnsNil() {
        let bundleId = UUID()
        let serverId = UUID()
        let result = sut.readMCPSecret(bundleId: bundleId, serverId: serverId, envKey: "NONEXISTENT")
        XCTAssertNil(result)
    }

    // MARK: - Delete

    func testDeleteMCPSecret() throws {
        let bundleId = UUID()
        let serverId = UUID()
        let envKey = "DELETE_TEST"
        let value = "secret_value_123"

        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey, value: value)
        try sut.deleteMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey)

        let result = sut.readMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey)
        XCTAssertNil(result)
    }

    func testDeleteNonExistentMCPSecretDoesNotThrow() throws {
        let bundleId = UUID()
        let serverId = UUID()
        try sut.deleteMCPSecret(bundleId: bundleId, serverId: serverId, envKey: "NONEXISTENT")
    }

    // MARK: - Delete All

    func testDeleteAllMCPSecretsForBundle() throws {
        let bundleId = UUID()
        let serverId1 = UUID()
        let serverId2 = UUID()

        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId1, envKey: "KEY_A", value: "value_a")
        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId1, envKey: "KEY_B", value: "value_b")
        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId2, envKey: "KEY_C", value: "value_c")

        try sut.deleteAllMCPSecrets(bundleId: bundleId)

        XCTAssertNil(sut.readMCPSecret(bundleId: bundleId, serverId: serverId1, envKey: "KEY_A"))
        XCTAssertNil(sut.readMCPSecret(bundleId: bundleId, serverId: serverId1, envKey: "KEY_B"))
        XCTAssertNil(sut.readMCPSecret(bundleId: bundleId, serverId: serverId2, envKey: "KEY_C"))
    }

    func testDeleteAllMCPSecretsDoesNotAffectOtherBundles() throws {
        let bundleA = UUID()
        let bundleB = UUID()
        let serverId = UUID()

        try sut.saveMCPSecret(bundleId: bundleA, serverId: serverId, envKey: "SHARED_KEY", value: "bundle_a_value")
        try sut.saveMCPSecret(bundleId: bundleB, serverId: serverId, envKey: "SHARED_KEY", value: "bundle_b_value")

        try sut.deleteAllMCPSecrets(bundleId: bundleA)

        XCTAssertNil(sut.readMCPSecret(bundleId: bundleA, serverId: serverId, envKey: "SHARED_KEY"))
        XCTAssertEqual(sut.readMCPSecret(bundleId: bundleB, serverId: serverId, envKey: "SHARED_KEY"), "bundle_b_value")

        try sut.deleteAllMCPSecrets(bundleId: bundleB)
    }

    // MARK: - Namespace Isolation

    func testMCPEntriesDoNotAffectGitHubEntries() throws {
        let bundleId = UUID()
        let serverId = UUID()

        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId, envKey: "TEST", value: "mcp_value")

        let username = "mcp-isolation-test-user"
        let ghToken = "ghp_mcp_isolation_test_1234567890"
        try sut.updateGitHubCredential(username: username, token: ghToken)

        try sut.deleteAllMCPSecrets(bundleId: bundleId)

        let ghCred = try sut.readGitHubCredential()
        XCTAssertNotNil(ghCred)
        XCTAssertEqual(ghCred?.username, username)
        XCTAssertEqual(ghCred?.token, ghToken)

        try sut.deleteGitHubCredential()
    }

    func testMCPEntriesDoNotAffectAccountTokenEntries() throws {
        let bundleId = UUID()
        let serverId = UUID()
        let accountId = UUID()
        let patToken = "ghp_isolation_pat_test_1234567890ab"

        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId, envKey: "TEST", value: "mcp_value")
        try sut.saveAccountToken(accountId: accountId, token: patToken)

        try sut.deleteAllMCPSecrets(bundleId: bundleId)

        XCTAssertEqual(sut.readAccountToken(accountId: accountId), patToken)

        try sut.deleteAccountToken(accountId: accountId)
    }

    // MARK: - Special Characters

    func testSpecialCharactersInEnvKey() throws {
        let bundleId = UUID()
        let serverId = UUID()
        let envKey = "MY_API-KEY.2"
        let value = "special_chars_value_123"

        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey, value: value)
        let retrieved = sut.readMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey)

        XCTAssertEqual(retrieved, value)

        try sut.deleteMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey)
    }

    // MARK: - Overwrite

    func testOverwriteExistingMCPSecret() throws {
        let bundleId = UUID()
        let serverId = UUID()
        let envKey = "OVERWRITE_TEST"
        let value1 = "first_value_1234567890abcdef"
        let value2 = "second_value_1234567890abcde"

        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey, value: value1)
        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey, value: value2)

        let retrieved = sut.readMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey)
        XCTAssertEqual(retrieved, value2)

        try sut.deleteMCPSecret(bundleId: bundleId, serverId: serverId, envKey: envKey)
    }

    // MARK: - Bulk Delete Empty Bundle

    func testDeleteAllMCPSecretsEmptyBundleDoesNotThrow() throws {
        let bundleId = UUID()
        try sut.deleteAllMCPSecrets(bundleId: bundleId)
    }

    // MARK: - Server Isolation

    func testSecretsIsolatedByServerId() throws {
        let bundleId = UUID()
        let serverA = UUID()
        let serverB = UUID()
        let envKey = "SAME_KEY"

        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverA, envKey: envKey, value: "server_a_value")
        try sut.saveMCPSecret(bundleId: bundleId, serverId: serverB, envKey: envKey, value: "server_b_value")

        XCTAssertEqual(sut.readMCPSecret(bundleId: bundleId, serverId: serverA, envKey: envKey), "server_a_value")
        XCTAssertEqual(sut.readMCPSecret(bundleId: bundleId, serverId: serverB, envKey: envKey), "server_b_value")

        try sut.deleteMCPSecret(bundleId: bundleId, serverId: serverA, envKey: envKey)
        try sut.deleteMCPSecret(bundleId: bundleId, serverId: serverB, envKey: envKey)
    }
}
