import Foundation
import os.log

/// Protocol abstracting URLSession for testability.
protocol SmitherySession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: SmitherySession {}

/// HTTP client for the Smithery MCP Registry.
/// https://registry.smithery.ai
@MainActor
final class SmitheryClient {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "SmitheryClient")

    private let session: SmitherySession
    private var cache: [String: [RegistryEntry]] = [:]
    private var cacheTimestamp: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 600

    init(session: SmitherySession = URLSession.shared) {
        self.session = session
    }

    /// Search for MCP servers in the registry.
    func search(query: String) async -> [RegistryEntry] {
        if let cached = cache[query],
           let timestamp = cacheTimestamp[query],
           Date().timeIntervalSince(timestamp) < cacheTTL {
            return cached
        }

        do {
            let entries = try await fetchFromSmithery(query: query)
            cache[query] = entries
            cacheTimestamp[query] = Date()
            return entries
        } catch {
            Self.logger.warning("Smithery API unavailable: \(error.localizedDescription)")
            return cache[query] ?? []
        }
    }

    /// Get popular servers (no query).
    func getPopular() async -> [RegistryEntry] {
        await search(query: "")
    }

    /// Invalidate cache.
    func invalidateCache() {
        cache.removeAll()
        cacheTimestamp.removeAll()
    }

    private func fetchFromSmithery(query: String) async throws -> [RegistryEntry] {
        var urlComponents = URLComponents(string: "https://registry.smithery.ai/servers")!
        if !query.isEmpty {
            urlComponents.queryItems = [URLQueryItem(name: "q", value: query)]
        }

        guard let url = urlComponents.url else {
            throw SmitheryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SmitheryError.httpError
        }

        let decoder = JSONDecoder()
        do {
            let entries = try decoder.decode([RegistryEntry].self, from: data)
            return entries
        } catch {
            throw SmitheryError.decodeFailed(error.localizedDescription)
        }
    }
}

/// A registry entry from Smithery.
struct RegistryEntry: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let displayName: String?
    let description: String?
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let url: String?
    let transport: String?
    let installCount: Int?
    let iconUrl: String?
    let tags: [String]?

    /// Convert to an MCPServerDefinition for installation.
    func toServerDefinition() -> MCPServerDefinition {
        let transportType: TransportType
        if transport == "streamable-http" {
            transportType = .streamableHttp
        } else if url != nil {
            transportType = .sse
        } else {
            transportType = .stdio
        }

        return MCPServerDefinition(
            name: name,
            displayName: displayName,
            serverDescription: description,
            transport: transportType,
            command: command,
            args: args ?? [],
            env: env ?? [:],
            url: url,
            secretEnvKeys: [],
            tags: tags ?? [],
            source: "smithery",
            registryId: id
        )
    }
}

enum SmitheryError: LocalizedError {
    case invalidURL
    case httpError
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid registry URL"
        case .httpError:
            return "Registry HTTP error"
        case .decodeFailed(let msg):
            return "Failed to decode registry response: \(msg)"
        }
    }
}
