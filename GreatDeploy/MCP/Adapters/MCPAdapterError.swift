import Foundation

/// Error types for MCP client adapters.
enum MCPAdapterError: LocalizedError {
    case configPathUnavailable
    case serializationFailed
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .configPathUnavailable:
            return "Config path is not available for this client"
        case .serializationFailed:
            return "Failed to serialize server configuration"
        case .parseFailed(let reason):
            return "Failed to parse configuration: \(reason)"
        }
    }
}
