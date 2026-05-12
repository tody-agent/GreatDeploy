import XCTest
@testable import GreatDeploy

@MainActor
final class AccountStoreCoreTests: XCTestCase {

    func testSwitchAccountSuccessUpdatesCredentialsGitConfigAndActiveAccount() async throws {
        let harness = StoreHarness()
        let first = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-personal-123456",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )
        let second = DevProfile(
            displayName: "Work",
            githubUsername: "work",
            personalAccessToken: "token-work-123456789",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com"
        )

        try harness.store.addAccount(first)
        try harness.store.addAccount(second)

        let liveSecond = try XCTUnwrap(harness.store.accounts.first { $0.githubUsername == "work" })
        try await harness.store.switchToAccount(liveSecond)

        XCTAssertEqual(harness.keychain.gitHubCredential?.username, "work")
        XCTAssertEqual(harness.gitConfig.currentConfig.name, "Work User")
        XCTAssertEqual(harness.gitConfig.currentConfig.email, "work@example.com")
        XCTAssertEqual(harness.store.activeAccount?.githubUsername, "work")
        XCTAssertEqual(harness.gitHubCLI.switchedUsernames, ["work"])
    }

    func testSwitchMissingTokenDoesNotChangeState() async throws {
        let harness = StoreHarness()
        let first = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-personal-123456",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )
        let second = DevProfile(
            displayName: "Work",
            githubUsername: "work",
            personalAccessToken: "token-work-123456789",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com"
        )

        try harness.store.addAccount(first)
        try harness.store.addAccount(second)
        let liveSecond = try XCTUnwrap(harness.store.accounts.first { $0.githubUsername == "work" })
        try harness.keychain.deleteAccountToken(accountId: liveSecond.id)

        do {
            try await harness.store.switchToAccount(liveSecond)
            XCTFail("Expected missing credentials to fail")
        } catch AccountStore.AccountStoreError.tokenNotFound {
            // Expected
        }

        XCTAssertEqual(harness.keychain.gitHubCredential?.username, "personal")
        XCTAssertEqual(harness.store.activeAccount?.githubUsername, "personal")
    }

    func testGitConfigFailureRollsBackCredentialAndLeavesActiveAccountUnchanged() async throws {
        let harness = StoreHarness()
        harness.gitConfig.currentConfig = (name: "Personal User", email: "personal@example.com")

        let first = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-personal-123456",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )
        let second = DevProfile(
            displayName: "Work",
            githubUsername: "work",
            personalAccessToken: "token-work-123456789",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com"
        )

        try harness.store.addAccount(first)
        try harness.store.addAccount(second)
        let liveSecond = try XCTUnwrap(harness.store.accounts.first { $0.githubUsername == "work" })
        harness.gitConfig.remainingSetConfigFailures = 1

        do {
            try await harness.store.switchToAccount(liveSecond)
            XCTFail("Expected git config failure")
        } catch {
            // Expected
        }

        XCTAssertEqual(harness.keychain.gitHubCredential?.username, "personal")
        XCTAssertEqual(harness.store.activeAccount?.githubUsername, "personal")
    }

    func testCloudflareFailureRollsBackCredentialAndLeavesActiveAccountUnchanged() async throws {
        let harness = StoreHarness()
        let first = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-personal-123456",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )
        let second = DevProfile(
            displayName: "Work",
            githubUsername: "work",
            personalAccessToken: "token-work-123456789",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            cloudflareAccountId: "cf-account",
            cloudflareApiToken: "cf-token-123456789"
        )

        try harness.store.addAccount(first)
        try harness.store.addAccount(second)
        let liveSecond = try XCTUnwrap(harness.store.accounts.first { $0.githubUsername == "work" })
        harness.cloudflare.failNextNonEmptyApply = true

        do {
            try await harness.store.switchToAccount(liveSecond)
            XCTFail("Expected Cloudflare failure")
        } catch {
            // Expected
        }

        XCTAssertEqual(harness.keychain.gitHubCredential?.username, "personal")
        XCTAssertEqual(harness.store.activeAccount?.githubUsername, "personal")
        XCTAssertTrue(harness.cloudflare.didClearCredentials)
    }

    func testDuplicateAccountIsRejected() throws {
        let harness = StoreHarness()
        let account = DevProfile(
            displayName: "Personal",
            githubUsername: "personal",
            personalAccessToken: "token-personal-123456",
            gitUserName: "Personal User",
            gitUserEmail: "personal@example.com"
        )

        try harness.store.addAccount(account)

        XCTAssertThrowsError(try harness.store.addAccount(account)) { error in
            guard case AccountStore.AccountStoreError.duplicateAccount = error else {
                return XCTFail("Expected duplicateAccount error, got \(error)")
            }
        }
    }
}

private final class StoreHarness {
    let keychain = FakeKeychainService()
    let gitConfig = FakeGitConfigService()
    let gitHubCLI = FakeGitHubCLIService()
    let cloudflare = FakeCloudflareAdapter()
    let userDefaults: UserDefaults
    let store: AccountStore

    @MainActor
    init() {
        let suiteName = "GreatDeployTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        store = AccountStore(
            keychainService: keychain,
            gitConfigService: gitConfig,
            gitHubCLIService: gitHubCLI,
            cloudflareAdapter: cloudflare,
            userDefaults: userDefaults,
            startServices: false
        )
    }
}

private final class FakeKeychainService: KeychainServicing {
    var gitHubCredential: (username: String, token: String)?
    var accountTokens: [UUID: String] = [:]
    var cloudflareTokens: [UUID: String] = [:]

    func readGitHubCredential() throws -> (username: String, token: String)? {
        gitHubCredential
    }

    func updateGitHubCredential(username: String, token: String) throws {
        gitHubCredential = (username, token)
    }

    func deleteGitHubCredential() throws {
        gitHubCredential = nil
    }

    func hasGitHubCredential(for username: String?) -> Bool {
        guard let username else { return gitHubCredential != nil }
        return gitHubCredential?.username == username
    }

    func saveAccountToken(accountId: UUID, token: String) throws {
        accountTokens[accountId] = token
    }

    func readAccountToken(accountId: UUID) -> String? {
        accountTokens[accountId]
    }

    func deleteAccountToken(accountId: UUID) throws {
        accountTokens[accountId] = nil
    }

    func saveCloudflareToken(accountId: UUID, token: String) throws {
        cloudflareTokens[accountId] = token
    }

    func readCloudflareToken(accountId: UUID) -> String? {
        cloudflareTokens[accountId]
    }

    func deleteCloudflareToken(accountId: UUID) throws {
        cloudflareTokens[accountId] = nil
    }
}

private final class FakeGitConfigService: GitConfigServicing {
    var currentConfig: (name: String?, email: String?) = (nil, nil)
    var remainingSetConfigFailures = 0
    var clearCacheCallCount = 0

    func ensureOsxKeychainHelper() throws {}

    func getCurrentConfigAsync() async throws -> (name: String?, email: String?) {
        currentConfig
    }

    func setGlobalUserConfigAsync(name: String, email: String) async throws {
        if remainingSetConfigFailures > 0 {
            remainingSetConfigFailures -= 1
            throw TestError.intentionalFailure
        }
        currentConfig = (name, email)
    }

    func clearGitHubCredentialCacheAsync() async throws {
        clearCacheCallCount += 1
    }
}

private final class FakeGitHubCLIService: GitHubCLIServicing {
    var isInstalled = true
    var switchedUsernames: [String] = []

    func switchAccount(to username: String) async throws -> String {
        switchedUsernames.append(username)
        return "switched"
    }
}

private final class FakeCloudflareAdapter: CloudflareAdapting {
    var failNextNonEmptyApply = false
    var appliedTokens: [(token: String, accountId: String, syncWranglerConfig: Bool)] = []
    var didClearCredentials = false

    func applyToken(_ token: String, accountId: String, syncWranglerConfig: Bool) async throws {
        if failNextNonEmptyApply && !token.isEmpty {
            failNextNonEmptyApply = false
            throw TestError.intentionalFailure
        }

        appliedTokens.append((token, accountId, syncWranglerConfig))
        if token.isEmpty && accountId.isEmpty {
            didClearCredentials = true
        }
    }

    func clearCredentials(syncWranglerConfig: Bool) async throws {
        didClearCredentials = true
        appliedTokens.append(("", "", syncWranglerConfig))
    }
}

private enum TestError: Error {
    case intentionalFailure
}
