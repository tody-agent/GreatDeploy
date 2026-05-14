import Foundation
import SwiftUI
import os.log

/// Observable store for managing GitHub accounts
@MainActor @preconcurrency
final class AccountStore: ObservableObject {

    // MARK: - Logging

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "AccountStore")

    // MARK: - Published Properties

    @Published private(set) var accounts: [DevProfile] = [] {
        didSet {
            // PERFORMANCE: Invalidate active account cache when accounts array changes
            _cachedActiveAccount = nil
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: Error?
    @Published private(set) var currentGitConfig: (name: String?, email: String?) = (nil, nil)
    @Published private(set) var profilePairStatus: ProfilePairStatus = .unknown

    /// Status of the last GitHub CLI account switch attempt
    enum CLISwitchStatus: Equatable {
        case none
        case success(String)
        case notInstalled
        case accountNotInCLI(String)
        case notLoggedIn
        case failed(String)
    }

    enum ProfilePairStatus: Equatable {
        case unknown
        case inSync
        case outOfSync(String)

        var needsAttention: Bool {
            if case .outOfSync = self {
                return true
            }
            return false
        }
    }

    @Published private(set) var lastCLISwitchStatus: CLISwitchStatus = .none

    // MARK: - Services

    private let keychainService: KeychainServicing
    private let gitConfigService: GitConfigServicing
    private let gitHubCLIService: GitHubCLIServicing
    private let cloudflareAdapter: CloudflareAdapting
    private let userDefaults: UserDefaults

    // MARK: - Concurrency Control

    /// Task handle for the current account switch operation
    /// Ensures serial execution: new switches wait for the previous to complete
    private var currentSwitchTask: Task<Void, Error>?
    private var externalStateMonitorTask: Task<Void, Never>?

    // MARK: - Storage Keys

    private let accountsStorageKey = "savedAccounts"
    private let migrationCompleteKey = "keychainMigrationComplete_v1"
    private let syncCloudflareToWranglerConfigKey = "syncCloudflareToWranglerConfig"

    // MARK: - Performance Cache

    /// Cache for active account lookup to avoid O(n) search on every access
    /// Invalidated automatically via accounts.didSet
    private var _cachedActiveAccount: DevProfile?

    // MARK: - Computed Properties

    var activeAccount: DevProfile? {
        // PERFORMANCE: Cache active account lookup for O(1) access
        if let cached = _cachedActiveAccount {
            return cached
        }

        let active = accounts.first(where: { $0.isActive })
        _cachedActiveAccount = active
        return active
    }

    var hasAccounts: Bool {
        !accounts.isEmpty
    }

    // MARK: - Initialization

    init(
        keychainService: KeychainServicing = KeychainService.shared,
        gitConfigService: GitConfigServicing = GitConfigService.shared,
        gitHubCLIService: GitHubCLIServicing = GitHubCLIService.shared,
        cloudflareAdapter: CloudflareAdapting = CloudflareAdapter.shared,
        userDefaults: UserDefaults = .standard,
        startServices: Bool = true
    ) {
        self.keychainService = keychainService
        self.gitConfigService = gitConfigService
        self.gitHubCLIService = gitHubCLIService
        self.cloudflareAdapter = cloudflareAdapter
        self.userDefaults = userDefaults

        loadAccounts()
        guard startServices else { return }

        Task {
            // Ensure git is configured to use osxkeychain for credential storage
            await ensureGitCredentialHelper()
            // Restore active account credential to keychain on app startup
            await restoreActiveAccountCredential()
            await refreshCurrentGitConfig()
            await refreshProfilePairStatus()
        }

        startExternalStateMonitoring()
    }

    private var syncCloudflareToWranglerConfig: Bool {
        userDefaults.bool(forKey: syncCloudflareToWranglerConfigKey)
    }

    deinit {
        externalStateMonitorTask?.cancel()
    }

    private func startExternalStateMonitoring() {
        externalStateMonitorTask?.cancel()
        externalStateMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.refreshProfilePairStatus()
            }
        }
    }

    /// Ensures git credential helper is configured for osxkeychain
    /// This is required for the app to work - git must read credentials from macOS Keychain
    private func ensureGitCredentialHelper() async {
        do {
            try gitConfigService.ensureOsxKeychainHelper()
        } catch {
            Self.logger.warning("Could not configure osxkeychain credential helper: \(error)")
        }
    }

    /// Restores the active account's credential to keychain on app startup
    /// This ensures git can authenticate even after keychain is cleared or app reinstall
    private func restoreActiveAccountCredential() async {
        guard let active = activeAccount else { return }

        // Check if credential already exists in keychain
        if keychainService.hasGitHubCredential(for: active.githubUsername) {
            return
        }

        // SECURITY: Read PAT from per-account Keychain storage (not from model)
        guard let token = keychainService.readAccountToken(accountId: active.id),
              !token.isEmpty else { return }

        do {
            try keychainService.updateGitHubCredential(
                username: active.githubUsername,
                token: token
            )
        } catch {
            // Log error but don't fail - credential will be restored on next switch
            lastError = AccountStoreError.sanitized("Could not restore credential")
        }
    }

    // MARK: - Account Management

    /// Adds a new account to the store
    func addAccount(_ account: DevProfile) throws {
        // Check for duplicate GitHub username
        if accounts.contains(where: { $0.githubUsername.lowercased() == account.githubUsername.lowercased() }) {
            throw AccountStoreError.duplicateAccount(account.githubUsername)
        }

        var newAccount = account

        // SECURITY: Save PAT to per-account Keychain storage
        if !newAccount.personalAccessToken.isEmpty {
            try keychainService.saveAccountToken(
                accountId: newAccount.id,
                token: newAccount.personalAccessToken
            )
        }

        // SECURITY: Save Cloudflare Token to per-account Keychain storage
        if !newAccount.cloudflareApiToken.isEmpty {
            try keychainService.saveCloudflareToken(
                accountId: newAccount.id,
                token: newAccount.cloudflareApiToken
            )
        }

        // If this is the first account, make it active and update git credential
        if accounts.isEmpty {
            newAccount.isActive = true
            // Set as THE github.com credential in Keychain for git credential helper
            if !newAccount.personalAccessToken.isEmpty {
                try keychainService.updateGitHubCredential(
                    username: newAccount.githubUsername,
                    token: newAccount.personalAccessToken
                )
            }
            if !newAccount.cloudflareApiToken.isEmpty {
                Task {
                    try? await cloudflareAdapter.applyToken(
                        newAccount.cloudflareApiToken,
                        accountId: newAccount.cloudflareAccountId,
                        syncWranglerConfig: syncCloudflareToWranglerConfig
                    )
                }
            }
        }

        // Clear PAT and Cloudflare API Token from in-memory model before persisting
        // (Secrets are now safely in Keychain — no need to keep it in the model)
        newAccount.personalAccessToken = ""
        newAccount.cloudflareApiToken = ""
        accounts.append(newAccount)
        saveAccounts()
    }

    /// Updates an existing account
    func updateAccount(_ account: DevProfile) throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }

        // SECURITY: Update PAT in per-account Keychain storage
        if !account.personalAccessToken.isEmpty {
            try keychainService.saveAccountToken(
                accountId: account.id,
                token: account.personalAccessToken
            )
        }

        // SECURITY: Update Cloudflare Token in per-account Keychain storage
        if !account.cloudflareApiToken.isEmpty {
            try keychainService.saveCloudflareToken(
                accountId: account.id,
                token: account.cloudflareApiToken
            )
        }

        // If this is the active account, update THE github.com Keychain entry
        if account.isActive && !account.personalAccessToken.isEmpty {
            try keychainService.updateGitHubCredential(
                username: account.githubUsername,
                token: account.personalAccessToken
            )
        }

        // Clear PAT from model before persisting
        var cleanAccount = account
        cleanAccount.personalAccessToken = ""
        accounts[index] = cleanAccount

        saveAccounts()
    }

    /// Removes an account from the store
    func removeAccount(_ account: DevProfile) throws {
        // SECURITY: Delete PAT and Cloudflare token from per-account Keychain storage
        try? keychainService.deleteAccountToken(accountId: account.id)
        try? keychainService.deleteCloudflareToken(accountId: account.id)

        // If deleting the active account, clear THE github.com Keychain entry
        if account.isActive {
            try? keychainService.deleteGitHubCredential()

            // If there are other accounts, activate the first one
            accounts.removeAll { $0.id == account.id }
            if !accounts.isEmpty {
                accounts[0].isActive = true
                accounts[0].lastUsedAt = Date()
                // Read the new active account's tokens from Keychain and set as credentials
                if let token = keychainService.readAccountToken(accountId: accounts[0].id),
                   !token.isEmpty {
                    try keychainService.updateGitHubCredential(
                        username: accounts[0].githubUsername,
                        token: token
                    )
                }
                if let cfToken = keychainService.readCloudflareToken(accountId: accounts[0].id),
                   !cfToken.isEmpty {
                    Task {
                        try? await cloudflareAdapter.applyToken(
                            cfToken,
                            accountId: accounts[0].cloudflareAccountId,
                            syncWranglerConfig: syncCloudflareToWranglerConfig
                        )
                    }
                }
            } else {
                Task {
                    try? await cloudflareAdapter.clearCredentials(syncWranglerConfig: syncCloudflareToWranglerConfig)
                }
            }
        } else {
            // Just remove non-active account
            accounts.removeAll { $0.id == account.id }
        }

        saveAccounts()
    }

    // MARK: - Account Switching

    /// Captures current system state for transaction rollback
    private struct AccountSwitchSnapshot {
        let previousGitHubCredential: (username: String, token: String)?
        let previousCloudflareToken: String?
        let previousCloudflareAccountId: String?
        let previousGitConfig: (name: String?, email: String?)
        let previousActiveAccountId: UUID?
    }

    /// Captures current state before account switch for rollback capability
    private func captureCurrentState() async throws -> AccountSwitchSnapshot {
        let previousCredential = try? keychainService.readGitHubCredential()
        
        var prevCfToken: String? = nil
        var prevCfAccountId: String? = nil
        if let active = activeAccount {
            prevCfToken = keychainService.readCloudflareToken(accountId: active.id)
            prevCfAccountId = active.cloudflareAccountId
        }

        let previousConfig = try await gitConfigService.getCurrentConfigAsync()
        let previousActiveId = activeAccount?.id

        return AccountSwitchSnapshot(
            previousGitHubCredential: previousCredential,
            previousCloudflareToken: prevCfToken,
            previousCloudflareAccountId: prevCfAccountId,
            previousGitConfig: previousConfig,
            previousActiveAccountId: previousActiveId
        )
    }

    /// Rolls back to previous state after failed account switch
    private func rollbackToState(_ snapshot: AccountSwitchSnapshot) async {
        do {
            // Rollback GitHub credential
            if let credential = snapshot.previousGitHubCredential {
                try keychainService.updateGitHubCredential(
                    username: credential.username,
                    token: credential.token
                )
            }
            
            // Rollback Cloudflare credential
            if let cfToken = snapshot.previousCloudflareToken, let cfAccountId = snapshot.previousCloudflareAccountId {
                try await cloudflareAdapter.applyToken(
                    cfToken,
                    accountId: cfAccountId,
                    syncWranglerConfig: syncCloudflareToWranglerConfig
                )
            } else {
                try await cloudflareAdapter.clearCredentials(syncWranglerConfig: syncCloudflareToWranglerConfig)
            }

            // Rollback git config
            if let name = snapshot.previousGitConfig.name,
               let email = snapshot.previousGitConfig.email {
                try await gitConfigService.setGlobalUserConfigAsync(
                    name: name,
                    email: email
                )
            }

            // Rollback active state in accounts
            if let previousActiveId = snapshot.previousActiveAccountId {
                for i in accounts.indices {
                    accounts[i].isActive = accounts[i].id == previousActiveId
                }
                saveAccounts()
            }

            Self.logger.info("Successfully rolled back account switch to previous state")
        } catch {
            // ERROR HANDLING: Rollback failed - log error but don't throw
            // System is now in inconsistent state and may require manual intervention
            Self.logger.critical("Failed to rollback account switch: \(error.localizedDescription)")
            lastError = AccountStoreError.sanitized("Failed to rollback account switch")
        }
    }

    /// Switches to the specified account
    /// Uses task-based serialization to ensure only one switch operation runs at a time
    /// RELIABILITY: Implements transaction pattern with automatic rollback on failure
    func switchToAccount(_ account: DevProfile) async throws {

        // Wait for any in-flight switch operation to complete
        // This provides proper serialization following Apple's concurrency best practices
        _ = try? await currentSwitchTask?.value

        // Create new switch task
        let switchTask = Task { @MainActor in
            isLoading = true
            lastError = nil

            defer {
                isLoading = false
            }

            // RELIABILITY: Capture current state for rollback
            guard let snapshot = try? await captureCurrentState() else {
                throw AccountStoreError.sanitized("Failed to capture current state")
            }

            do {
                // SECURITY: Read PAT and Cloudflare Token from per-account Keychain
                let token = keychainService.readAccountToken(accountId: account.id) ?? ""
                let cfToken = keychainService.readCloudflareToken(accountId: account.id) ?? ""

                if token.isEmpty && cfToken.isEmpty {
                    throw AccountStoreError.tokenNotFound
                }

                // Update THE SINGLE GitHub Keychain credential entry
                if !token.isEmpty {
                    try keychainService.updateGitHubCredential(
                        username: account.githubUsername,
                        token: token
                    )
                } else {
                    try? keychainService.deleteGitHubCredential()
                }

                // Update Cloudflare credentials
                if !cfToken.isEmpty {
                    try await cloudflareAdapter.applyToken(
                        cfToken,
                        accountId: account.cloudflareAccountId,
                        syncWranglerConfig: syncCloudflareToWranglerConfig
                    )
                } else {
                    try await cloudflareAdapter.clearCredentials(syncWranglerConfig: syncCloudflareToWranglerConfig)
                }

                // Clear git credential cache to force fresh credential fetch
                // This prevents using cached credentials from previous account
                try? await gitConfigService.clearGitHubCredentialCacheAsync()

                // Update git config
                try await gitConfigService.setGlobalUserConfigAsync(
                    name: account.gitUserName,
                    email: account.gitUserEmail
                )

                // Update active state in store (atomic update protected by MainActor)
                for i in accounts.indices {
                    accounts[i].isActive = accounts[i].id == account.id
                    if accounts[i].id == account.id {
                        accounts[i].lastUsedAt = Date()
                    }
                }

                saveAccounts()

                // Refresh current config
                await refreshCurrentGitConfig()
                await refreshProfilePairStatus()

                // Switch GitHub CLI account in background (non-blocking)
                // This is best-effort and won't fail the switch if CLI is not set up
                await switchGitHubCLIAccount(to: account.githubUsername)

            } catch {
                // RELIABILITY: Rollback to previous state on any failure
                await rollbackToState(snapshot)
                lastError = error
                throw error
            }
        }

        // Store task reference for serialization
        currentSwitchTask = switchTask

        // Await completion and propagate any errors
        try await switchTask.value
    }

    /// Refreshes the current git configuration
    func refreshCurrentGitConfig() async {
        do {
            currentGitConfig = try await gitConfigService.getCurrentConfigAsync()
        } catch {
            currentGitConfig = (nil, nil)
        }
    }

    /// Checks whether the active GitHub and Cloudflare system credentials still match the active profile.
    func refreshProfilePairStatus() async {
        guard !isLoading else { return }
        guard let active = activeAccount else {
            profilePairStatus = .unknown
            return
        }

        do {
            if let credential = try keychainService.readGitHubCredential(),
               credential.username.caseInsensitiveCompare(active.githubUsername) != .orderedSame {
                profilePairStatus = .outOfSync("GitHub is using @\(credential.username), but active profile is @\(active.githubUsername).")
                return
            }
        } catch {
            profilePairStatus = .outOfSync("Could not verify GitHub credential state.")
            return
        }

        let expectedCloudflareAccountId = active.cloudflareAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentCloudflareAccountId = await cloudflareAdapter.currentAccountId() ?? ""

        if !expectedCloudflareAccountId.isEmpty,
           currentCloudflareAccountId.caseInsensitiveCompare(expectedCloudflareAccountId) != .orderedSame {
            let current = currentCloudflareAccountId.isEmpty ? "not set" : currentCloudflareAccountId
            profilePairStatus = .outOfSync("Cloudflare is using \(current), but active profile expects \(expectedCloudflareAccountId).")
            return
        }

        if expectedCloudflareAccountId.isEmpty, !currentCloudflareAccountId.isEmpty {
            profilePairStatus = .outOfSync("Cloudflare is set to \(currentCloudflareAccountId), but active profile has no Cloudflare account.")
            return
        }

        profilePairStatus = .inSync
    }

    /// Switches the GitHub CLI account and reports status via lastCLISwitchStatus
    /// This runs `gh auth switch --user <username>` to sync CLI authentication
    private func switchGitHubCLIAccount(to username: String) async {
        Self.logger.info("switchGitHubCLIAccount called for: \(username)")

        // Skip if CLI is not installed
        guard gitHubCLIService.isInstalled else {
            Self.logger.info("GitHub CLI not installed, skipping gh auth switch")
            lastCLISwitchStatus = .notInstalled
            return
        }

        Self.logger.info("GitHub CLI is installed, proceeding with switch...")

        do {
            let output = try await gitHubCLIService.switchAccount(to: username)
            Self.logger.info("Successfully switched GitHub CLI to account: \(username). Output: \(output)")
            lastCLISwitchStatus = .success(username)
        } catch GitHubCLIService.GitHubCLIError.accountNotFound {
            Self.logger.notice("Account '\(username)' not found in GitHub CLI (run 'gh auth login' to add it)")
            lastCLISwitchStatus = .accountNotInCLI(username)
        } catch GitHubCLIService.GitHubCLIError.notLoggedIn {
            Self.logger.notice("Not logged in to GitHub CLI (run 'gh auth login' to enable CLI switching)")
            lastCLISwitchStatus = .notLoggedIn
        } catch {
            Self.logger.error("GitHub CLI switch failed: \(error.localizedDescription)")
            lastCLISwitchStatus = .failed("GitHub CLI switch failed")
        }
    }

    /// Clears the CLI switch status (used to dismiss UI banners)
    func clearCLISwitchStatus() {
        lastCLISwitchStatus = .none
    }

    // MARK: - Persistence

    private func saveAccounts() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(accounts)
            userDefaults.set(data, forKey: accountsStorageKey)
        } catch {
            // ERROR HANDLING: Sanitized error message (MED-03 fix)
            lastError = AccountStoreError.sanitized("Failed to save accounts")
            Self.logger.error("Failed to encode accounts for persistence: \(error)")
        }
    }

    private func loadAccounts() {
        guard let data = userDefaults.data(forKey: accountsStorageKey) else {
            // No saved data is not an error - fresh install
            return
        }

        // Check if migration from legacy format (PAT in UserDefaults) is needed
        let migrationComplete = userDefaults.bool(forKey: migrationCompleteKey)

        if !migrationComplete {
            migrateFromLegacyStorage(data: data)
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            accounts = try decoder.decode([DevProfile].self, from: data)
        } catch {
            // ERROR HANDLING: Sanitized error message (MED-03 fix)
            lastError = AccountStoreError.sanitized("Failed to load accounts")
            Self.logger.error("Failed to decode saved accounts: \(error)")
            accounts = []
        }
    }

    /// Migrates legacy accounts that had PATs stored in UserDefaults to Keychain-only storage.
    /// This runs once on upgrade and then sets a flag so it never runs again.
    private func migrateFromLegacyStorage(data: Data) {
        Self.logger.info("Starting one-time migration of PATs from UserDefaults to Keychain...")

        do {
            // Try to decode using legacy format that includes PAT
            let legacyAccounts = try DevProfile.decodeLegacy(from: data)
            var migratedAccounts: [DevProfile] = []

            for (account, legacyToken) in legacyAccounts {
                // Save each PAT to per-account Keychain storage
                if !legacyToken.isEmpty {
                    try keychainService.saveAccountToken(
                        accountId: account.id,
                        token: legacyToken
                    )
                    Self.logger.info("Migrated PAT for account: \(account.githubUsername)")
                }
                
                var cleanAccount = account
                cleanAccount.cloudflareApiToken = "" // Just to be safe
                migratedAccounts.append(cleanAccount)
            }

            // Update in-memory accounts
            accounts = migratedAccounts

            // Re-save WITHOUT PATs (using the new Codable that excludes PAT)
            saveAccounts()

            // Mark migration as complete
            userDefaults.set(true, forKey: migrationCompleteKey)

            Self.logger.info("Successfully migrated \(legacyAccounts.count) account(s) to Keychain-only storage")

        } catch {
            // Migration failed — try loading with new format as fallback
            Self.logger.warning("Legacy migration failed, trying new format: \(error)")

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                accounts = try decoder.decode([DevProfile].self, from: data)
                // Data was already in new format, mark migration complete
                userDefaults.set(true, forKey: migrationCompleteKey)
            } catch {
                Self.logger.error("Failed to decode accounts in any format: \(error)")
                lastError = AccountStoreError.sanitized("Failed to load accounts")
                accounts = []
            }
        }
    }

    // MARK: - Error Types

    enum AccountStoreError: LocalizedError {
        case tokenNotFound
        case accountNotFound
        case duplicateAccount(String)
        /// SECURITY: Sanitized error message that does not leak internal details (MED-03 fix)
        case sanitized(String)

        var errorDescription: String? {
            switch self {
            case .tokenNotFound:
                return "Account credentials (PAT or API Token) not found in keychain"
            case .accountNotFound:
                return "Account not found"
            case .duplicateAccount(let username):
                return "An account with GitHub username '\(username)' already exists"
            case .sanitized(let message):
                return message
            }
        }
    }
}


// MARK: - Sync with System Keychain

extension AccountStore {

    /// Syncs accounts with current system keychain state
    func syncWithSystemKeychain() async {
        await refreshProfilePairStatus()
    }
}
