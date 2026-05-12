import Foundation
import Security
import LocalAuthentication

/// Service for managing GitHub credentials in macOS Keychain
final class KeychainService {

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case invalidData
        case encodingFailed
        case biometricAuthFailed(String)
        case processTimeout

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Keychain item not found"
            case .duplicateItem:
                return "Keychain item already exists"
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain error: \(status)"
            case .invalidData:
                return "Invalid data format"
            case .encodingFailed:
                return "Failed to encode data"
            case .biometricAuthFailed(let message):
                return "Biometric authentication failed: \(message)"
            case .processTimeout:
                return "Git credential operation timed out"
            }
        }
    }

    // MARK: - Constants

    private let githubServer = "github.com"

    /// Service name for per-account PAT storage in Keychain
    /// Uses kSecClassGenericPassword to avoid conflicts with git credential helper entries
    private let accountTokenService = "com.gitaccountswitcher.account-tokens"

    /// Default timeout for external process execution (seconds)
    private let processTimeoutSeconds: TimeInterval = 10

    // MARK: - Singleton

    static let shared = KeychainService()
    private init() {}

    // MARK: - Biometric Authentication

    /// Authentication method available on the device
    enum AuthMethod {
        case touchID
        case faceID
        case opticID
        case password
        case none

        var displayName: String {
            switch self {
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            case .opticID: return "Optic ID"
            case .password: return "Password"
            case .none: return "None"
            }
        }
    }

    /// Returns the available authentication method on this device
    func availableAuthMethod() -> AuthMethod {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .touchID:
                return .touchID
            case .faceID:
                return .faceID
            case .opticID:
                return .opticID
            case .none:
                return .password
            @unknown default:
                return .password
            }
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return .password
        }

        return .none
    }

    /// Requests biometric authentication before accessing sensitive Keychain items
    /// SECURITY: Adds an extra layer of protection for token retrieval
    /// - Parameter reason: The reason displayed to the user for authentication
    /// - Returns: True if authentication succeeded
    func authenticateWithBiometrics(reason: String) async throws {
        let context = LAContext()
        var error: NSError?

        // Configure context for better UX
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password"

        // Check if biometric authentication is available
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // Try biometric authentication first
            do {
                try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
                return // Success
            } catch let authError as LAError {
                // If user chose fallback or biometrics failed, try password
                if authError.code == .userFallback || authError.code == .biometryLockout {
                    try await authenticateWithPassword(context: context, reason: reason)
                    return
                }
                // User cancelled or other error
                throw KeychainError.biometricAuthFailed(authError.localizedDescription)
            }
        }

        // Biometrics not available, try password authentication
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw KeychainError.biometricAuthFailed(
                "Authentication not available: \(error?.localizedDescription ?? "unknown error")"
            )
        }

        try await authenticateWithPassword(context: context, reason: reason)
    }

    /// Authenticates using device password
    private func authenticateWithPassword(context: LAContext, reason: String) async throws {
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            throw KeychainError.biometricAuthFailed("Password authentication failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Read GitHub Credential (with Biometric Auth)

    /// Reads the current GitHub credential from Keychain with biometric authentication
    /// SECURITY: Requires Touch ID, Face ID, or password before returning sensitive token data
    /// - Parameter reason: The reason displayed to the user for authentication
    /// - Returns: Tuple of (username, token) if found and authenticated
    func readGitHubCredentialWithAuth(reason: String = "Access GitHub credentials") async throws -> (username: String, token: String)? {
        // First authenticate with biometrics/password
        try await authenticateWithBiometrics(reason: reason)

        // Then read the credential
        return try readGitHubCredential()
    }

    /// Reads the current GitHub credential from Keychain (no authentication required)
    /// - Returns: Tuple of (username, token) if found
    func readGitHubCredential() throws -> (username: String, token: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let dict = result as? [String: Any],
              let account = dict[kSecAttrAccount as String] as? String,
              let passwordData = dict[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return (account, password)
    }

    /// Reads all GitHub credentials from Keychain
    /// - Returns: Array of (username, token) tuples
    func readAllGitHubCredentials() throws -> [(username: String, token: String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { dict in
            guard let account = dict[kSecAttrAccount as String] as? String,
                  let passwordData = dict[kSecValueData as String] as? Data,
                  let password = String(data: passwordData, encoding: .utf8) else {
                return nil
            }
            return (account, password)
        }
    }

    // MARK: - Update/Add GitHub Credential (Single Entry)

    /// Updates or adds THE SINGLE GitHub credential in Keychain
    /// This app maintains only ONE github.com entry that gets updated on account switch
    /// Uses Security framework directly for reliable keychain access
    /// - Parameters:
    ///   - username: GitHub username for current account
    ///   - token: Personal Access Token for current account
    func updateGitHubCredential(username: String, token: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Clean up existing entries (git erase + SecItemDelete)
        try? deleteGitHubCredential()

        // Add new credential via Security framework
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS
        ]

        var addQuery = query
        addQuery[kSecAttrAccount as String] = username
        addQuery[kSecValueData as String] = tokenData

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Existing entry couldn't be deleted (partition ID mismatch) — update it instead
            let attrs: [String: Any] = [
                kSecAttrAccount as String: username,
                kSecValueData as String: tokenData
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Runs a git credential-osxkeychain command with the given action and input
    /// SECURITY: Includes process timeout to prevent indefinite hangs
    private func runGitCredentialCommand(action: String, input: String) throws {
        let process = Process()
        let inputPipe = Pipe()

        // Use GitConfigService's validated git path (includes code signature verification)
        let gitPath: String
        do {
            gitPath = try GitConfigService.shared.getValidatedGitPath()
        } catch {
            // Fallback to standard path if GitConfigService fails
            gitPath = "/usr/bin/git"
        }

        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["credential-osxkeychain", action]
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Sanitize environment (matches GitConfigService pattern)
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "en_US.UTF-8"
        ]

        do {
            try process.run()

            if let data = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
                try? inputPipe.fileHandleForWriting.close()
            }

            // SECURITY: Use timeout to prevent indefinite hangs (MED-01 fix)
            let waitResult = process.waitUntilExitOrTimeout(seconds: processTimeoutSeconds)
            if !waitResult {
                process.terminate()
                throw KeychainError.processTimeout
            }

            guard process.terminationStatus == 0 else {
                throw KeychainError.unexpectedStatus(OSStatus(process.terminationStatus))
            }
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.unexpectedStatus(-1)
        }
    }

    // MARK: - Delete GitHub Credential

    /// Deletes THE SINGLE GitHub credential from Keychain
    /// Call this when deleting the active account or when app needs to clear credentials
    func deleteGitHubCredential() throws {
        // Use git credential-osxkeychain erase for proper cleanup
        eraseCredentialUsingGit()

        // Also try Security framework delete as backup
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Erases credential using git credential-osxkeychain for proper cleanup
    private func eraseCredentialUsingGit() {
        // Ignore errors since credential might not exist
        try? runGitCredentialCommand(
            action: "erase",
            input: """
            protocol=https
            host=github.com

            """
        )
    }

    // MARK: - Verify Credential

    /// Checks if a GitHub credential exists in Keychain
    /// - Parameter username: Optional username to check for specific account
    /// - Returns: True if credential exists
    func hasGitHubCredential(for username: String? = nil) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: githubServer,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let username = username {
            query[kSecAttrAccount as String] = username
        }

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Per-Account Token Storage (Keychain-only)
    //
    // SECURITY: Each account's PAT is stored as a separate kSecClassGenericPassword
    // entry in the Keychain, keyed by the account's UUID. This ensures:
    // 1. PATs are NEVER written to UserDefaults
    // 2. Each account's token is independently secured by the Keychain
    // 3. Tokens are protected by the user's login keychain password

    /// Saves a PAT for a specific account in the Keychain
    /// - Parameters:
    ///   - accountId: The account's UUID
    ///   - token: The Personal Access Token to store
    func saveAccountToken(accountId: UUID, token: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let accountKey = accountId.uuidString

        // Delete any existing entry first
        try? deleteAccountToken(accountId: accountId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: accountTokenService,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Update existing
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: accountTokenService,
                kSecAttrAccount as String: accountKey
            ]
            let attrs: [String: Any] = [
                kSecValueData as String: tokenData
            ]
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Reads the PAT for a specific account from the Keychain
    /// - Parameter accountId: The account's UUID
    /// - Returns: The stored PAT, or nil if not found
    func readAccountToken(accountId: UUID) -> String? {
        let accountKey = accountId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: accountTokenService,
            kSecAttrAccount as String: accountKey,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let tokenData = result as? Data,
              let token = String(data: tokenData, encoding: .utf8) else {
            return nil
        }

        return token
    }

    /// Deletes the PAT for a specific account from the Keychain
    /// - Parameter accountId: The account's UUID
    func deleteAccountToken(accountId: UUID) throws {
        let accountKey = accountId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: accountTokenService,
            kSecAttrAccount as String: accountKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        // Ignore "not found" — it's fine if there's nothing to delete
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - Process Timeout Extension

extension Process {
    /// Waits for the process to exit with a timeout.
    /// - Parameter seconds: Maximum time to wait in seconds
    /// - Returns: true if the process exited within the timeout, false if it timed out
    func waitUntilExitOrTimeout(seconds: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)

        // Use terminationHandler to signal completion
        self.terminationHandler = { _ in
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + seconds)
        return result == .success
    }
}
