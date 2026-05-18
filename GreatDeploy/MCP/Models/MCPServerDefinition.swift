import Foundation

/// Represents an MCP server configuration.
/// SECURITY: Secret values are NEVER serialized — only key names in `secretEnvKeys`.
struct MCPServerDefinition: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var displayName: String?
    var serverDescription: String?
    var enabled: Bool
    var transport: TransportType
    var command: String?
    var args: [String]
    var env: [String: String]
    var url: String?
    var secretEnvKeys: [String]
    var tags: [String]
    var source: String?
    var registryId: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String? = nil,
        serverDescription: String? = nil,
        enabled: Bool = true,
        transport: TransportType = .stdio,
        command: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        url: String? = nil,
        secretEnvKeys: [String] = [],
        tags: [String] = [],
        source: String? = nil,
        registryId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.serverDescription = serverDescription
        self.enabled = enabled
        self.transport = transport
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.secretEnvKeys = secretEnvKeys
        self.tags = tags
        self.source = source
        self.registryId = registryId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Codable (SECURITY: secret values EXCLUDED from serialization)

extension MCPServerDefinition {
    enum CodingKeys: String, CodingKey {
        case id, name, displayName, serverDescription, enabled, transport
        case command, args, env, url, secretEnvKeys, tags, source, registryId
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.serverDescription = try container.decodeIfPresent(String.self, forKey: .serverDescription)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        transport = try container.decode(TransportType.self, forKey: .transport)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        args = try container.decode([String].self, forKey: .args)
        env = try container.decode([String: String].self, forKey: .env)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        secretEnvKeys = try container.decodeIfPresent([String].self, forKey: .secretEnvKeys) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source)
        registryId = try container.decodeIfPresent(String.self, forKey: .registryId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(serverDescription, forKey: .serverDescription)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(transport, forKey: .transport)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encode(args, forKey: .args)

        var safeEnv = env
        for key in secretEnvKeys {
            safeEnv.removeValue(forKey: key)
        }
        try container.encode(safeEnv, forKey: .env)

        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(secretEnvKeys, forKey: .secretEnvKeys)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(registryId, forKey: .registryId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - CustomStringConvertible (Security: redact env values)

extension MCPServerDefinition: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        "MCPServerDefinition(name: \(name), transport: \(transport.rawValue), enabled: \(enabled))"
    }

    var debugDescription: String {
        """
        MCPServerDefinition {
            id: \(id.uuidString)
            name: \(name)
            transport: \(transport.rawValue)
            command: \(command ?? "nil")
            args: \(args)
            env: [REDACTED — \(secretEnvKeys.count) secret keys]
            url: \(url ?? "nil")
            enabled: \(enabled)
        }
        """
    }
}
