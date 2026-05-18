import Foundation

/// Represents a GitHub account configuration for switching
/// Conforms to Sendable for safe usage across actor boundaries (Swift 6 compatibility)
struct DevProfile: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var displayName: String       // e.g., "Personal", "Work"
    var githubUsername: String    // GitHub account username
    var personalAccessToken: String // SECURITY: Transient only — NEVER serialized. Stored in Keychain via KeychainService.
    var gitUserName: String       // git config user.name
    var gitUserEmail: String      // git config user.email
    var cloudflareAccountId: String
    var cloudflareApiToken: String // SECURITY: Transient only — NEVER serialized.
    var isActive: Bool
    var createdAt: Date
    var lastUsedAt: Date?
    var mcpBundleId: UUID?

    init(
        id: UUID = UUID(),
        displayName: String,
        githubUsername: String,
        personalAccessToken: String = "",
        gitUserName: String,
        gitUserEmail: String,
        cloudflareAccountId: String = "",
        cloudflareApiToken: String = "",
        isActive: Bool = false,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        mcpBundleId: UUID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.githubUsername = githubUsername
        self.personalAccessToken = personalAccessToken
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.cloudflareAccountId = cloudflareAccountId
        self.cloudflareApiToken = cloudflareApiToken
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.mcpBundleId = mcpBundleId
    }

    /// Creates a copy with updated active state
    func withActiveState(_ active: Bool) -> DevProfile {
        var copy = self
        copy.isActive = active
        if active {
            copy.lastUsedAt = Date()
        }
        return copy
    }
}

// MARK: - Codable (SECURITY: PAT is EXCLUDED from serialization)

extension DevProfile: Codable {
    enum CodingKeys: String, CodingKey {
        // SECURITY: personalAccessToken is intentionally EXCLUDED.
        // PATs and Cloudflare tokens are stored exclusively in the macOS Keychain via KeychainService.
        case id, displayName, githubUsername
        case gitUserName, gitUserEmail, cloudflareAccountId, isActive, createdAt, lastUsedAt, mcpBundleId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        githubUsername = try container.decode(String.self, forKey: .githubUsername)
        // SECURITY: Tokens are never decoded from storage — always loaded from Keychain
        personalAccessToken = ""
        cloudflareApiToken = ""
        gitUserName = try container.decode(String.self, forKey: .gitUserName)
        gitUserEmail = try container.decode(String.self, forKey: .gitUserEmail)
        cloudflareAccountId = try container.decodeIfPresent(String.self, forKey: .cloudflareAccountId) ?? ""
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        mcpBundleId = try container.decodeIfPresent(UUID.self, forKey: .mcpBundleId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(githubUsername, forKey: .githubUsername)
        // SECURITY: PAT and Cloudflare API tokens are NEVER encoded
        try container.encode(gitUserName, forKey: .gitUserName)
        try container.encode(gitUserEmail, forKey: .gitUserEmail)
        try container.encode(cloudflareAccountId, forKey: .cloudflareAccountId)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(mcpBundleId, forKey: .mcpBundleId)
    }
}

// MARK: - Legacy Migration Support

extension DevProfile {
    /// CodingKeys that include personalAccessToken for one-time migration from legacy UserDefaults storage.
    /// Used ONLY during migration — after migration PATs are deleted from UserDefaults.
    enum LegacyCodingKeys: String, CodingKey {
        case id, displayName, githubUsername, personalAccessToken
        case gitUserName, gitUserEmail, isActive, createdAt, lastUsedAt
    }

    /// Decodes from legacy format that included PAT in UserDefaults.
    /// Returns the PAT so the caller can migrate it to the Keychain.
    static func decodeLegacy(from data: Data) throws -> [(account: DevProfile, legacyToken: String)] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try to decode with legacy keys that include PAT
        let container = try decoder.decode([LegacyAccount].self, from: data)
        return container.map { legacy in
            let account = DevProfile(
                id: legacy.id,
                displayName: legacy.displayName,
                githubUsername: legacy.githubUsername,
                personalAccessToken: "", // Don't keep PAT in model
                gitUserName: legacy.gitUserName,
                gitUserEmail: legacy.gitUserEmail,
                cloudflareAccountId: "",
                cloudflareApiToken: "",
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

extension DevProfile: CustomDebugStringConvertible, CustomStringConvertible {
    /// String representation that redacts sensitive token data
    var description: String {
        "DevProfile(displayName: \(displayName), username: @\(githubUsername))"
    }

    /// Debug description that shows all fields except the sensitive token
    var debugDescription: String {
        """
        DevProfile {
            id: \(id.uuidString)
            displayName: \(displayName)
            githubUsername: @\(githubUsername)
            personalAccessToken: [REDACTED — Keychain only]
            gitUserName: \(gitUserName)
            gitUserEmail: \(gitUserEmail)
            cloudflareAccountId: \(cloudflareAccountId)
            cloudflareApiToken: [REDACTED — Keychain only]
            isActive: \(isActive)
            createdAt: \(createdAt)
            lastUsedAt: \(lastUsedAt?.description ?? "nil")
            mcpBundleId: \(mcpBundleId?.uuidString ?? "nil")
        }
        """
    }
}

// MARK: - Preview/Testing Support
extension DevProfile {
    static let preview = DevProfile(
        displayName: "Personal",
        githubUsername: "preview-user",
        personalAccessToken: "",  // SECURITY: Always empty in preview - tokens never needed for UI
        gitUserName: "Preview User",
        gitUserEmail: "preview@example.com",
        cloudflareAccountId: "cloudflare-preview-id",
        cloudflareApiToken: "",
        isActive: true
    )

    static let previewWork = DevProfile(
        displayName: "Work",
        githubUsername: "preview-work",
        personalAccessToken: "",  // SECURITY: Always empty in preview
        gitUserName: "Preview Work User",
        gitUserEmail: "work@example.com",
        cloudflareAccountId: "cloudflare-work-id",
        cloudflareApiToken: "",
        isActive: false
    )
}
