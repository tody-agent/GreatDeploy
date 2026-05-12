import Foundation

/// Represents a GitHub account configuration for switching
/// Conforms to Sendable for safe usage across actor boundaries (Swift 6 compatibility)
struct GitAccount: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var displayName: String       // e.g., "Personal", "Work"
    var githubUsername: String    // GitHub account username
    var personalAccessToken: String // SECURITY: Transient only — NEVER serialized. Stored in Keychain via KeychainService.
    var gitUserName: String       // git config user.name
    var gitUserEmail: String      // git config user.email
    var isActive: Bool
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        githubUsername: String,
        personalAccessToken: String = "",
        gitUserName: String,
        gitUserEmail: String,
        isActive: Bool = false,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.githubUsername = githubUsername
        self.personalAccessToken = personalAccessToken
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// Creates a copy with updated active state
    func withActiveState(_ active: Bool) -> GitAccount {
        var copy = self
        copy.isActive = active
        if active {
            copy.lastUsedAt = Date()
        }
        return copy
    }
}

// MARK: - Codable (SECURITY: PAT is EXCLUDED from serialization)

extension GitAccount: Codable {
    enum CodingKeys: String, CodingKey {
        // SECURITY: personalAccessToken is intentionally EXCLUDED.
        // PATs are stored exclusively in the macOS Keychain via KeychainService.
        case id, displayName, githubUsername
        case gitUserName, gitUserEmail, isActive, createdAt, lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        githubUsername = try container.decode(String.self, forKey: .githubUsername)
        // SECURITY: PAT is never decoded from storage — always loaded from Keychain
        personalAccessToken = ""
        gitUserName = try container.decode(String.self, forKey: .gitUserName)
        gitUserEmail = try container.decode(String.self, forKey: .gitUserEmail)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(githubUsername, forKey: .githubUsername)
        // SECURITY: PAT is NEVER encoded — stored exclusively in Keychain
        try container.encode(gitUserName, forKey: .gitUserName)
        try container.encode(gitUserEmail, forKey: .gitUserEmail)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
    }
}

// MARK: - Legacy Migration Support

extension GitAccount {
    /// CodingKeys that include personalAccessToken for one-time migration from legacy UserDefaults storage.
    /// Used ONLY during migration — after migration PATs are deleted from UserDefaults.
    enum LegacyCodingKeys: String, CodingKey {
        case id, displayName, githubUsername, personalAccessToken
        case gitUserName, gitUserEmail, isActive, createdAt, lastUsedAt
    }

    /// Decodes from legacy format that included PAT in UserDefaults.
    /// Returns the PAT so the caller can migrate it to the Keychain.
    static func decodeLegacy(from data: Data) throws -> [(account: GitAccount, legacyToken: String)] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try to decode with legacy keys that include PAT
        let container = try decoder.decode([LegacyAccount].self, from: data)
        return container.map { legacy in
            let account = GitAccount(
                id: legacy.id,
                displayName: legacy.displayName,
                githubUsername: legacy.githubUsername,
                personalAccessToken: "", // Don't keep PAT in model
                gitUserName: legacy.gitUserName,
                gitUserEmail: legacy.gitUserEmail,
                isActive: legacy.isActive,
                createdAt: legacy.createdAt,
                lastUsedAt: legacy.lastUsedAt
            )
            return (account, legacy.personalAccessToken)
        }
    }

    /// Internal struct for decoding legacy data that includes PAT
    private struct LegacyAccount: Codable {
        let id: UUID
        let displayName: String
        let githubUsername: String
        let personalAccessToken: String
        let gitUserName: String
        let gitUserEmail: String
        let isActive: Bool
        let createdAt: Date
        let lastUsedAt: Date?
    }
}

// MARK: - Debug String (Security)

extension GitAccount: CustomDebugStringConvertible, CustomStringConvertible {
    /// String representation that redacts sensitive token data
    var description: String {
        "GitAccount(displayName: \(displayName), username: @\(githubUsername))"
    }

    /// Debug description that shows all fields except the sensitive token
    var debugDescription: String {
        """
        GitAccount {
            id: \(id.uuidString)
            displayName: \(displayName)
            githubUsername: @\(githubUsername)
            personalAccessToken: [REDACTED — Keychain only]
            gitUserName: \(gitUserName)
            gitUserEmail: \(gitUserEmail)
            isActive: \(isActive)
            createdAt: \(createdAt)
            lastUsedAt: \(lastUsedAt?.description ?? "nil")
        }
        """
    }
}

// MARK: - Preview/Testing Support
extension GitAccount {
    static let preview = GitAccount(
        displayName: "Personal",
        githubUsername: "preview-user",
        personalAccessToken: "",  // SECURITY: Always empty in preview - tokens never needed for UI
        gitUserName: "Preview User",
        gitUserEmail: "preview@example.com",
        isActive: true
    )

    static let previewWork = GitAccount(
        displayName: "Work",
        githubUsername: "preview-work",
        personalAccessToken: "",  // SECURITY: Always empty in preview
        gitUserName: "Preview Work User",
        gitUserEmail: "work@example.com",
        isActive: false
    )
}
