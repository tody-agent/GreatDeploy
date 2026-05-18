import XCTest
@testable import GreatDeploy

@MainActor
final class MigrationTests: XCTestCase {

    // MARK: - Codable Tests for mcpBundleId

    func testNewProfileWithMcpBundleIdEncodesAndDecodesCorrectly() throws {
        let bundleId = UUID()
        let profile = DevProfile(
            displayName: "Test",
            githubUsername: "testuser",
            gitUserName: "Test User",
            gitUserEmail: "test@example.com",
            mcpBundleId: bundleId
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DevProfile.self, from: data)

        XCTAssertEqual(decoded.mcpBundleId, bundleId)
        XCTAssertEqual(decoded.displayName, "Test")
        XCTAssertEqual(decoded.githubUsername, "testuser")
    }

    func testNewProfileWithoutMcpBundleIdDecodesAsNil() throws {
        let profile = DevProfile(
            displayName: "Test",
            githubUsername: "testuser",
            gitUserName: "Test User",
            gitUserEmail: "test@example.com"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DevProfile.self, from: data)

        XCTAssertNil(decoded.mcpBundleId)
    }

    func testExistingProfileWithoutMcpBundleIdFieldDecodesWithoutError() throws {
        // Simulate old JSON that doesn't have mcpBundleId field at all
        let oldJson = """
        {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "displayName": "Legacy Profile",
            "githubUsername": "legacyuser",
            "gitUserName": "Legacy User",
            "gitUserEmail": "legacy@example.com",
            "isActive": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """
        let data = oldJson.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DevProfile.self, from: data)

        XCTAssertNil(decoded.mcpBundleId)
        XCTAssertEqual(decoded.displayName, "Legacy Profile")
        XCTAssertEqual(decoded.id, UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"))
    }

    // MARK: - Migration Tests

    func testMigrationEmptyAccountsNoCrashAndFlagSet() throws {
        let harness = MigrationHarness()
        harness.userDefaults.set(true, forKey: "keychainMigrationComplete_v1")

        // No accounts saved — should not crash
        let store = AccountStore(
            keychainService: harness.keychain,
            gitConfigService: harness.gitConfig,
            gitHubCLIService: harness.gitHubCLI,
            cloudflareAdapter: harness.cloudflare,
            userDefaults: harness.userDefaults,
            startServices: false
        )

        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertTrue(harness.userDefaults.bool(forKey: "mcpMigrationComplete_v1"))
    }

    func testMigrationAccountsWithoutMcpBundleIdGetsUUIDAssigned() throws {
        let harness = MigrationHarness()
        harness.userDefaults.set(true, forKey: "keychainMigrationComplete_v1")

        // Save accounts without mcpBundleId
        let profile = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-123",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([profile])
        harness.userDefaults.set(data, forKey: "savedAccounts")

        let store = AccountStore(
            keychainService: harness.keychain,
            gitConfigService: harness.gitConfig,
            gitHubCLIService: harness.gitHubCLI,
            cloudflareAdapter: harness.cloudflare,
            userDefaults: harness.userDefaults,
            startServices: false
        )

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertNotNil(store.accounts[0].mcpBundleId)
        XCTAssertTrue(harness.userDefaults.bool(forKey: "mcpMigrationComplete_v1"))
    }

    func testMigrationAccountsWithMcpBundleIdSkippedIdempotent() throws {
        let harness = MigrationHarness()
        harness.userDefaults.set(true, forKey: "keychainMigrationComplete_v1")

        let existingBundleId = UUID()
        let profile = DevProfile(
            displayName: "Work",
            githubUsername: "work",
            personalAccessToken: "token-456",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            mcpBundleId: existingBundleId
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([profile])
        harness.userDefaults.set(data, forKey: "savedAccounts")

        let store = AccountStore(
            keychainService: harness.keychain,
            gitConfigService: harness.gitConfig,
            gitHubCLIService: harness.gitHubCLI,
            cloudflareAdapter: harness.cloudflare,
            userDefaults: harness.userDefaults,
            startServices: false
        )

        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertEqual(store.accounts[0].mcpBundleId, existingBundleId)
    }

    func testMigrationCreatesBackupBeforeModifying() throws {
        let harness = MigrationHarness()
        harness.userDefaults.set(true, forKey: "keychainMigrationComplete_v1")

        let profile = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-123",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([profile])
        harness.userDefaults.set(data, forKey: "savedAccounts")

        _ = AccountStore(
            keychainService: harness.keychain,
            gitConfigService: harness.gitConfig,
            gitHubCLIService: harness.gitHubCLI,
            cloudflareAdapter: harness.cloudflare,
            userDefaults: harness.userDefaults,
            startServices: false
        )

        // Check that a backup key was created
        let allKeys = harness.userDefaults.dictionaryRepresentation().keys
        let backupKeys = allKeys.filter { $0.hasPrefix("profiles.json.bak.") }
        XCTAssertFalse(backupKeys.isEmpty, "Expected at least one backup key to exist")

        // Verify backup contains the original data
        if let backupKey = backupKeys.first,
           let backupData = harness.userDefaults.data(forKey: backupKey) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backupAccounts = try decoder.decode([DevProfile].self, from: backupData)
            XCTAssertEqual(backupAccounts.count, 1)
            XCTAssertNil(backupAccounts[0].mcpBundleId, "Backup should have original data without mcpBundleId")
        }
    }

    func testDowngradeSimulationOldDecoderIgnoresNewField() throws {
        // Create a profile with mcpBundleId
        let bundleId = UUID()
        let profile = DevProfile(
            displayName: "Test",
            githubUsername: "testuser",
            gitUserName: "Test User",
            gitUserEmail: "test@example.com",
            mcpBundleId: bundleId
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        // Decode using a struct that doesn't have mcpBundleId (simulating old code)
        struct OldProfile: Codable {
            let id: UUID
            let displayName: String
            let githubUsername: String
            let gitUserName: String
            let gitUserEmail: String
            let isActive: Bool
            let createdAt: Date
            let lastUsedAt: Date?
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldDecoded = try decoder.decode(OldProfile.self, from: data)

        XCTAssertEqual(oldDecoded.displayName, "Test")
        XCTAssertEqual(oldDecoded.githubUsername, "testuser")
        // Old decoder ignores the new field — no crash
    }

    func testCorruptedDataMigrationDoesNotCrashFallsBackToEmpty() throws {
        let harness = MigrationHarness()
        harness.userDefaults.set(true, forKey: "keychainMigrationComplete_v1")
        harness.userDefaults.set("not valid json".data(using: .utf8)!, forKey: "savedAccounts")

        let store = AccountStore(
            keychainService: harness.keychain,
            gitConfigService: harness.gitConfig,
            gitHubCLIService: harness.gitHubCLI,
            cloudflareAdapter: harness.cloudflare,
            userDefaults: harness.userDefaults,
            startServices: false
        )

        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNotNil(store.lastError)
    }

    func testMultipleAccountsMigrationAssignsUniqueIds() throws {
        let harness = MigrationHarness()
        harness.userDefaults.set(true, forKey: "keychainMigrationComplete_v1")

        let profile1 = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-1",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )
        let profile2 = DevProfile(
            displayName: "Work",
            githubUsername: "work",
            personalAccessToken: "token-2",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com"
        )
        let profile3 = DevProfile(
            displayName: "Freelance",
            githubUsername: "freelance",
            personalAccessToken: "token-3",
            gitUserName: "Freelance User",
            gitUserEmail: "freelance@example.com",
            mcpBundleId: UUID() // Already has one
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([profile1, profile2, profile3])
        harness.userDefaults.set(data, forKey: "savedAccounts")

        let store = AccountStore(
            keychainService: harness.keychain,
            gitConfigService: harness.gitConfig,
            gitHubCLIService: harness.gitHubCLI,
            cloudflareAdapter: harness.cloudflare,
            userDefaults: harness.userDefaults,
            startServices: false
        )

        XCTAssertEqual(store.accounts.count, 3)

        // First two should have new bundle IDs
        XCTAssertNotNil(store.accounts[0].mcpBundleId)
        XCTAssertNotNil(store.accounts[1].mcpBundleId)

        // Third should keep its original bundle ID
        XCTAssertEqual(store.accounts[2].mcpBundleId, profile3.mcpBundleId)

        // All bundle IDs should be unique
        let allIds = store.accounts.compactMap(\.mcpBundleId)
        XCTAssertEqual(Set(allIds).count, allIds.count, "All MCP bundle IDs should be unique")
    }

    func testMigrationIsIdempotentAcrossMultipleStoreInits() throws {
        let harness = MigrationHarness()
        harness.userDefaults.set(true, forKey: "keychainMigrationComplete_v1")

        let profile = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-123",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([profile])
        harness.userDefaults.set(data, forKey: "savedAccounts")

        // First init — runs migration
        let store1 = AccountStore(
            keychainService: harness.keychain,
            gitConfigService: harness.gitConfig,
            gitHubCLIService: harness.gitHubCLI,
            cloudflareAdapter: harness.cloudflare,
            userDefaults: harness.userDefaults,
            startServices: false
        )
        let firstBundleId = store1.accounts[0].mcpBundleId
        XCTAssertNotNil(firstBundleId)

        // Second init — should NOT change the bundle ID
        let store2 = AccountStore(
            keychainService: harness.keychain,
            gitConfigService: harness.gitConfig,
            gitHubCLIService: harness.gitHubCLI,
            cloudflareAdapter: harness.cloudflare,
            userDefaults: harness.userDefaults,
            startServices: false
        )
        XCTAssertEqual(store2.accounts[0].mcpBundleId, firstBundleId, "Bundle ID should not change on second init")
    }
}

// MARK: - Migration Test Harness

private final class MigrationHarness {
    let keychain = MigrationFakeKeychainService()
    let gitConfig = MigrationFakeGitConfigService()
    let gitHubCLI = MigrationFakeGitHubCLIService()
    let cloudflare = MigrationFakeCloudflareAdapter()
    let userDefaults: UserDefaults

    @MainActor
    init() {
        let suiteName = "GreatDeployMigrationTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

private final class MigrationFakeKeychainService: KeychainServicing {
    var gitHubCredential: (username: String, token: String)?
    var accountTokens: [UUID: String] = [:]
    var cloudflareTokens: [UUID: String] = [:]

    func readGitHubCredential() throws -> (username: String, token: String)? { gitHubCredential }
    func updateGitHubCredential(username: String, token: String) throws { gitHubCredential = (username, token) }
    func deleteGitHubCredential() throws { gitHubCredential = nil }
    func hasGitHubCredential(for username: String?) -> Bool {
        guard let username else { return gitHubCredential != nil }
        return gitHubCredential?.username == username
    }
    func saveAccountToken(accountId: UUID, token: String) throws { accountTokens[accountId] = token }
    func readAccountToken(accountId: UUID) -> String? { accountTokens[accountId] }
    func deleteAccountToken(accountId: UUID) throws { accountTokens[accountId] = nil }
    func saveCloudflareToken(accountId: UUID, token: String) throws { cloudflareTokens[accountId] = token }
    func readCloudflareToken(accountId: UUID) -> String? { cloudflareTokens[accountId] }
    func deleteCloudflareToken(accountId: UUID) throws { cloudflareTokens[accountId] = nil }
}

private final class MigrationFakeGitConfigService: GitConfigServicing {
    var currentConfig: (name: String?, email: String?) = (nil, nil)
    func ensureOsxKeychainHelper() throws {}
    func getCurrentConfigAsync() async throws -> (name: String?, email: String?) { currentConfig }
    func setGlobalUserConfigAsync(name: String, email: String) async throws { currentConfig = (name, email) }
    func clearGitHubCredentialCacheAsync() async throws {}
}

private final class MigrationFakeGitHubCLIService: GitHubCLIServicing {
    var isInstalled = false
    func switchAccount(to username: String) async throws -> String { "" }
}

private final class MigrationFakeCloudflareAdapter: CloudflareAdapting {
    var currentAccountIdValue: String?
    func applyToken(_ token: String, accountId: String, syncWranglerConfig: Bool) async throws {}
    func clearCredentials(syncWranglerConfig: Bool) async throws {}
    func currentAccountId() async -> String? { currentAccountIdValue }
}
