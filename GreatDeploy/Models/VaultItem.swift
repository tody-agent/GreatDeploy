import Foundation

/// Generic vault item — the core data model for GreatDeploy v2.
public struct VaultItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case githubAccount
        case cloudflareAccount
        case mcpServer
        case skill
        case file
    }

    public var id: UUID
    public var kind: Kind
    public var displayName: String
    public var metadata: [String: String]
    var sensitiveData: CryptoEnvelope?
    public var plainData: Data?
    var hmacSignature: Data?
    public var version: VectorClock
    public var createdAt: Date
    public var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        displayName: String,
        metadata: [String: String] = [:],
        sensitiveData: CryptoEnvelope? = nil,
        plainData: Data? = nil,
        hmacSignature: Data? = nil,
        version: VectorClock = VectorClock(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.metadata = metadata
        self.sensitiveData = sensitiveData
        self.plainData = plainData
        self.hmacSignature = hmacSignature
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
