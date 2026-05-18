import Foundation

/// Transport mechanism for MCP server communication.
enum TransportType: String, Codable, Sendable, CaseIterable {
    case stdio
    case sse
    case streamableHttp

    var displayName: String {
        switch self {
        case .stdio: return "Stdio"
        case .sse: return "SSE"
        case .streamableHttp: return "Streamable HTTP"
        }
    }

    var iconName: String {
        switch self {
        case .stdio: return "terminal"
        case .sse: return "antenna.radiowaves.left.and.right"
        case .streamableHttp: return "network"
        }
    }
}
