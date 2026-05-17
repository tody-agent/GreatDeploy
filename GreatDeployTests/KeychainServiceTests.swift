import XCTest
@testable import GreatDeploy

final class KeychainServiceTests: XCTestCase {

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
        let testIds = [UUID(), UUID(), UUID()]
        for id in testIds {
            try? sut.deleteAccountToken(accountId: id)
            try? sut.deleteCloudflareToken(accountId: id)
        }
        try? sut.deleteGitHubCredential()
    }

    // MARK: - Per-Account Token Tests

    func testSaveAndReadAccountToken() throws {
        let accountId = UUID()
        let token = "ghp_test1234567890abcdefghij"

        try sut.saveAccountToken(accountId: accountId, token: token)
        let retrieved = sut.readAccountToken(accountId: accountId)

        XCTAssertEqual(retrieved, token)

        try sut.deleteAccountToken(accountId: accountId)
    }

    func testReadNonExistentAccountTokenReturnsNil() {
        let accountId = UUID()
        let result = sut.readAccountToken(accountId: accountId)
        XCTAssertNil(result)
    }

    func testDeleteAccountToken() throws {
        let accountId = UUID()
        let token = "ghp_deletetest1234567890abcdef"

        try sut.saveAccountToken(accountId: accountId, token: token)
        try sut.deleteAccountToken(accountId: accountId)

        let result = sut.readAccountToken(accountId: accountId)
        XCTAssertNil(result)
    }

    func testDeleteNonExistentAccountTokenDoesNotThrow() throws {
        let accountId = UUID()
        try sut.deleteAccountToken(accountId: accountId)
    }

    func testOverwriteAccountToken() throws {
        let accountId = UUID()
        let token1 = "ghp_first1234567890abcdefghij"
        let token2 = "ghp_second1234567890abcdefgh"

        try sut.saveAccountToken(accountId: accountId, token: token1)
        try sut.saveAccountToken(accountId: accountId, token: token2)

        let retrieved = sut.readAccountToken(accountId: accountId)
        XCTAssertEqual(retrieved, token2)

        try sut.deleteAccountToken(accountId: accountId)
    }

    // MARK: - Cloudflare Token Tests

    func testSaveAndReadCloudflareToken() throws {
        let accountId = UUID()
        let token = "cf_test_token_1234567890abcdef1234"

        try sut.saveCloudflareToken(accountId: accountId, token: token)
        let retrieved = sut.readCloudflareToken(accountId: accountId)

        XCTAssertEqual(retrieved, token)

        try sut.deleteCloudflareToken(accountId: accountId)
    }

    func testReadNonExistentCloudflareTokenReturnsNil() {
        let accountId = UUID()
        let result = sut.readCloudflareToken(accountId: accountId)
        XCTAssertNil(result)
    }

    func testDeleteCloudflareToken() throws {
        let accountId = UUID()
        let token = "cf_delete_test_token_1234567890ab"

        try sut.saveCloudflareToken(accountId: accountId, token: token)
        try sut.deleteCloudflareToken(accountId: accountId)

        let result = sut.readCloudflareToken(accountId: accountId)
        XCTAssertNil(result)
    }

    func testOverwriteCloudflareToken() throws {
        let accountId = UUID()
        let token1 = "cf_first_token_1234567890abcdef"
        let token2 = "cf_second_token_1234567890abcde"

        try sut.saveCloudflareToken(accountId: accountId, token: token1)
        try sut.saveCloudflareToken(accountId: accountId, token: token2)

        let retrieved = sut.readCloudflareToken(accountId: accountId)
        XCTAssertEqual(retrieved, token2)

        try sut.deleteCloudflareToken(accountId: accountId)
    }

    // MARK: - GitHub Credential Tests

    func testUpdateAndReadGitHubCredential() throws {
        let username = "test-user-greatdeploy"
        let token = "ghp_github_credential_test12345678"

        try sut.updateGitHubCredential(username: username, token: token)
        let credential = try sut.readGitHubCredential()

        XCTAssertNotNil(credential)
        XCTAssertEqual(credential?.username, username)
        XCTAssertEqual(credential?.token, token)

        try sut.deleteGitHubCredential()
    }

    func testDeleteGitHubCredential() throws {
        let username = "test-delete-user"
        let token = "ghp_delete_credential_test12345678"

        try sut.updateGitHubCredential(username: username, token: token)
        try sut.deleteGitHubCredential()

        let credential = try sut.readGitHubCredential()
        XCTAssertNil(credential)
    }

    func testHasGitHubCredentialReturnsFalseWhenEmpty() throws {
        try sut.deleteGitHubCredential()
        XCTAssertFalse(sut.hasGitHubCredential())
    }

    func testHasGitHubCredentialReturnsTrueAfterAdding() throws {
        try sut.updateGitHubCredential(username: "test-has-user", token: "ghp_has_test_1234567890abcdef")
        XCTAssertTrue(sut.hasGitHubCredential())

        try sut.deleteGitHubCredential()
    }

    func testHasGitHubCredentialForSpecificUsername() throws {
        try sut.updateGitHubCredential(username: "specific-user", token: "ghp_specific_1234567890abcdef")

        XCTAssertTrue(sut.hasGitHubCredential(for: "specific-user"))
        XCTAssertFalse(sut.hasGitHubCredential(for: "other-user"))

        try sut.deleteGitHubCredential()
    }

    func testUpdateGitHubCredentialReplacesPrevious() throws {
        try sut.updateGitHubCredential(username: "old-user", token: "ghp_old_token_1234567890abcdef")
        try sut.updateGitHubCredential(username: "new-user", token: "ghp_new_token_1234567890abcdef")

        let credential = try sut.readGitHubCredential()
        XCTAssertEqual(credential?.username, "new-user")
        XCTAssertEqual(credential?.token, "ghp_new_token_1234567890abcdef")

        try sut.deleteGitHubCredential()
    }

    // MARK: - Multiple Account Isolation

    func testMultipleAccountsAreIsolated() throws {
        let id1 = UUID()
        let id2 = UUID()
        let token1 = "ghp_account1_token_1234567890abc"
        let token2 = "ghp_account2_token_1234567890abc"

        try sut.saveAccountToken(accountId: id1, token: token1)
        try sut.saveAccountToken(accountId: id2, token: token2)

        XCTAssertEqual(sut.readAccountToken(accountId: id1), token1)
        XCTAssertEqual(sut.readAccountToken(accountId: id2), token2)

        try sut.deleteAccountToken(accountId: id1)
        XCTAssertNil(sut.readAccountToken(accountId: id1))
        XCTAssertEqual(sut.readAccountToken(accountId: id2), token2)

        try sut.deleteAccountToken(accountId: id2)
    }

    func testCloudflareTokensAreIsolatedAcrossAccounts() throws {
        let id1 = UUID()
        let id2 = UUID()
        let token1 = "cf_isolation_token_1_1234567890ab"
        let token2 = "cf_isolation_token_2_1234567890ab"

        try sut.saveCloudflareToken(accountId: id1, token: token1)
        try sut.saveCloudflareToken(accountId: id2, token: token2)

        XCTAssertEqual(sut.readCloudflareToken(accountId: id1), token1)
        XCTAssertEqual(sut.readCloudflareToken(accountId: id2), token2)

        try sut.deleteCloudflareToken(accountId: id1)
        XCTAssertNil(sut.readCloudflareToken(accountId: id1))
        XCTAssertEqual(sut.readCloudflareToken(accountId: id2), token2)

        try sut.deleteCloudflareToken(accountId: id2)
    }

    func testAccountAndCloudflareTokensAreIndependent() throws {
        let accountId = UUID()
        let patToken = "ghp_independent_test_1234567890ab"
        let cfToken = "cf_independent_test_1234567890abcd"

        try sut.saveAccountToken(accountId: accountId, token: patToken)
        try sut.saveCloudflareToken(accountId: accountId, token: cfToken)

        XCTAssertEqual(sut.readAccountToken(accountId: accountId), patToken)
        XCTAssertEqual(sut.readCloudflareToken(accountId: accountId), cfToken)

        try sut.deleteAccountToken(accountId: accountId)
        XCTAssertNil(sut.readAccountToken(accountId: accountId))
        XCTAssertEqual(sut.readCloudflareToken(accountId: accountId), cfToken)

        try sut.deleteCloudflareToken(accountId: accountId)
    }
}
