import Foundation

protocol KeychainServicing {
    func readGitHubCredential() throws -> (username: String, token: String)?
    func updateGitHubCredential(username: String, token: String) throws
    func deleteGitHubCredential() throws
    func hasGitHubCredential(for username: String?) -> Bool

    func saveAccountToken(accountId: UUID, token: String) throws
    func readAccountToken(accountId: UUID) -> String?
    func deleteAccountToken(accountId: UUID) throws

    func saveCloudflareToken(accountId: UUID, token: String) throws
    func readCloudflareToken(accountId: UUID) -> String?
    func deleteCloudflareToken(accountId: UUID) throws
}

protocol GitConfigServicing {
    func ensureOsxKeychainHelper() throws
    func getCurrentConfigAsync() async throws -> (name: String?, email: String?)
    func setGlobalUserConfigAsync(name: String, email: String) async throws
    func clearGitHubCredentialCacheAsync() async throws
}

protocol GitHubCLIServicing {
    var isInstalled: Bool { get }
    func switchAccount(to username: String) async throws -> String
}

protocol CloudflareAdapting {
    func applyToken(_ token: String, accountId: String, syncWranglerConfig: Bool) async throws
    func clearCredentials(syncWranglerConfig: Bool) async throws
}

