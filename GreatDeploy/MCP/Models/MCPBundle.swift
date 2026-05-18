import Foundation

/// A bundle of MCP servers with enabled client targets.
struct MCPBundle: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var bundleDescription: String
    var servers: [MCPServerDefinition]
    var enabledClients: Set<MCPClientKind>
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date
    var deviceOrigin: String?

    init(
        id: UUID = UUID(),
        name: String,
        bundleDescription: String = "",
        servers: [MCPServerDefinition] = [],
        enabledClients: Set<MCPClientKind> = [],
        isActive: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deviceOrigin: String? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleDescription = bundleDescription
        self.servers = servers
        self.enabledClients = enabledClients
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deviceOrigin = deviceOrigin
    }

    var serverCount: Int {
        servers.count
    }

    var enabledServers: [MCPServerDefinition] {
        servers.filter { $0.enabled }
    }
}
