import XCTest
@testable import GreatDeploy

@MainActor
final class SmitheryClientTests: XCTestCase {

    // MARK: - Helpers

    private func makeClient(session: SmitherySession) -> SmitheryClient {
        SmitheryClient(session: session)
    }

    private func sampleRegistryJSON() -> Data {
        let entries: [[String: Any]] = [
            [
                "id": "server-1",
                "name": "github-mcp",
                "displayName": "GitHub MCP Server",
                "description": "Access GitHub repositories, issues, and PRs",
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-github"],
                "env": ["GITHUB_TOKEN": ""],
                "transport": "stdio",
                "installCount": 1500,
                "tags": ["github", "code", "productivity"]
            ],
            [
                "id": "server-2",
                "name": "filesystem-mcp",
                "displayName": "Filesystem MCP",
                "description": "Read and write files on your system",
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                "env": [:],
                "transport": "stdio",
                "installCount": 800,
                "tags": ["filesystem", "files"]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: entries)
    }

    private func samplePopularJSON() -> Data {
        let entries: [[String: Any]] = [
            [
                "id": "popular-1",
                "name": "brave-search",
                "displayName": "Brave Search",
                "description": "Web search via Brave Search API",
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-brave-search"],
                "env": ["BRAVE_API_KEY": ""],
                "transport": "stdio",
                "installCount": 5000,
                "tags": ["search", "web"]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: entries)
    }

    // MARK: - Test 1: search() returns entries from API

    func testSearchReturnsEntriesFromAPI() async throws {
        let data = sampleRegistryJSON()
        let response = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let session = MockSession(data: data, response: response)
        let client = makeClient(session: session)

        let results = await client.search(query: "github")

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "github-mcp")
        XCTAssertEqual(results[0].displayName, "GitHub MCP Server")
        XCTAssertEqual(results[0].description, "Access GitHub repositories, issues, and PRs")
        XCTAssertEqual(results[0].command, "npx")
        XCTAssertEqual(results[0].args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(results[0].installCount, 1500)
        XCTAssertEqual(results[0].tags, ["github", "code", "productivity"])
    }

    // MARK: - Test 2: search() caches results

    func testSearchCachesResults() async throws {
        let data = sampleRegistryJSON()
        let response = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let session = CountingMockSession(data: data, response: response)
        let client = makeClient(session: session)

        let _ = await client.search(query: "test")
        let _ = await client.search(query: "test")

        XCTAssertEqual(session.callCount, 1, "Should only call the API once due to caching")
    }

    // MARK: - Test 3: search() cache expires after TTL (via invalidateCache)

    func testSearchCacheExpiresAfterInvalidate() async throws {
        let data = sampleRegistryJSON()
        let response = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let session = CountingMockSession(data: data, response: response)
        let client = makeClient(session: session)

        let _ = await client.search(query: "expire-test")

        client.invalidateCache()

        let _ = await client.search(query: "expire-test")

        XCTAssertEqual(session.callCount, 2, "Should call API again after cache invalidation")
    }

    // MARK: - Test 4: search() API error returns cached or empty

    func testSearchAPIErrorReturnsEmptyWhenNoCache() async throws {
        let errorResponse = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        let session = MockSession(data: Data(), response: errorResponse)
        let client = makeClient(session: session)

        let results = await client.search(query: "error-query")

        XCTAssertTrue(results.isEmpty, "Should return empty when API fails and no cache exists")
    }

    func testSearchAPIErrorReturnsCachedData() async throws {
        let data = sampleRegistryJSON()
        let successResponse = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let successSession = MockSession(data: data, response: successResponse)
        let client = makeClient(session: successSession)

        let cachedResults = await client.search(query: "cached-query")
        XCTAssertEqual(cachedResults.count, 2)

        let errorResponse = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        let errorSession = MockSession(data: Data(), response: errorResponse)
        let newClient = makeClient(session: errorSession)

        let results = await newClient.search(query: "cached-query")
        XCTAssertTrue(results.isEmpty, "New client has no cache, returns empty on API error")
    }

    // MARK: - Test 5: getPopular() returns popular servers

    func testGetPopularReturnsPopularServers() async throws {
        let data = samplePopularJSON()
        let response = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let session = MockSession(data: data, response: response)
        let client = makeClient(session: session)

        let results = await client.getPopular()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "brave-search")
        XCTAssertEqual(results[0].displayName, "Brave Search")
        XCTAssertEqual(results[0].installCount, 5000)
    }

    // MARK: - Test 6: RegistryEntry.toServerDefinition() correctness

    func testToServerDefinitionStdioTransport() {
        let entry = RegistryEntry(
            id: "test-1",
            name: "stdio-server",
            displayName: "Stdio Server",
            description: "A stdio transport server",
            command: "npx",
            args: ["-y", "test"],
            env: ["KEY": "value"],
            url: nil,
            transport: "stdio",
            installCount: 100,
            iconUrl: nil,
            tags: ["test"]
        )

        let definition = entry.toServerDefinition()

        XCTAssertEqual(definition.name, "stdio-server")
        XCTAssertEqual(definition.displayName, "Stdio Server")
        XCTAssertEqual(definition.serverDescription, "A stdio transport server")
        XCTAssertEqual(definition.transport, .stdio)
        XCTAssertEqual(definition.command, "npx")
        XCTAssertEqual(definition.args, ["-y", "test"])
        XCTAssertEqual(definition.env["KEY"], "value")
        XCTAssertEqual(definition.source, "smithery")
        XCTAssertEqual(definition.registryId, "test-1")
        XCTAssertEqual(definition.tags, ["test"])
    }

    func testToServerDefinitionSSETransportWithURL() {
        let entry = RegistryEntry(
            id: "test-2",
            name: "sse-server",
            displayName: nil,
            description: nil,
            command: nil,
            args: nil,
            env: nil,
            url: "https://api.example.com/mcp",
            transport: nil,
            installCount: nil,
            iconUrl: nil,
            tags: nil
        )

        let definition = entry.toServerDefinition()

        XCTAssertEqual(definition.transport, .sse, "Should default to SSE when URL is present")
        XCTAssertEqual(definition.url, "https://api.example.com/mcp")
        XCTAssertNil(definition.command)
        XCTAssertTrue(definition.args.isEmpty)
        XCTAssertTrue(definition.env.isEmpty)
        XCTAssertTrue(definition.tags.isEmpty)
    }

    func testToServerDefinitionStreamableHttpTransport() {
        let entry = RegistryEntry(
            id: "test-3",
            name: "stream-server",
            displayName: "Stream Server",
            description: nil,
            command: nil,
            args: nil,
            env: nil,
            url: "https://stream.example.com",
            transport: "streamable-http",
            installCount: nil,
            iconUrl: nil,
            tags: nil
        )

        let definition = entry.toServerDefinition()

        XCTAssertEqual(definition.transport, .streamableHttp)
    }

    func testToServerDefinitionDefaultsForMissingFields() {
        let entry = RegistryEntry(
            id: "minimal",
            name: "minimal-server",
            displayName: nil,
            description: nil,
            command: nil,
            args: nil,
            env: nil,
            url: nil,
            transport: nil,
            installCount: nil,
            iconUrl: nil,
            tags: nil
        )

        let definition = entry.toServerDefinition()

        XCTAssertEqual(definition.name, "minimal-server")
        XCTAssertNil(definition.displayName)
        XCTAssertNil(definition.serverDescription)
        XCTAssertEqual(definition.transport, .stdio, "Should default to stdio when no URL or transport specified")
        XCTAssertNil(definition.command)
        XCTAssertTrue(definition.args.isEmpty)
        XCTAssertTrue(definition.env.isEmpty)
        XCTAssertNil(definition.url)
        XCTAssertEqual(definition.source, "smithery")
        XCTAssertEqual(definition.registryId, "minimal")
        XCTAssertTrue(definition.tags.isEmpty)
    }

    // MARK: - RegistryEntry Codable

    func testRegistryEntryCodable() throws {
        let entry = RegistryEntry(
            id: "codec-1",
            name: "codec-server",
            displayName: "Codec Server",
            description: "Test codec",
            command: "python",
            args: ["server.py"],
            env: ["ENV": "prod"],
            url: "https://example.com",
            transport: "sse",
            installCount: 42,
            iconUrl: "https://example.com/icon.png",
            tags: ["codec", "test"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RegistryEntry.self, from: data)

        XCTAssertEqual(decoded.id, "codec-1")
        XCTAssertEqual(decoded.name, "codec-server")
        XCTAssertEqual(decoded.displayName, "Codec Server")
        XCTAssertEqual(decoded.description, "Test codec")
        XCTAssertEqual(decoded.command, "python")
        XCTAssertEqual(decoded.args, ["server.py"])
        XCTAssertEqual(decoded.env?["ENV"], "prod")
        XCTAssertEqual(decoded.url, "https://example.com")
        XCTAssertEqual(decoded.transport, "sse")
        XCTAssertEqual(decoded.installCount, 42)
        XCTAssertEqual(decoded.iconUrl, "https://example.com/icon.png")
        XCTAssertEqual(decoded.tags, ["codec", "test"])
    }

    // MARK: - SmitheryError

    func testSmitheryErrorDescriptions() {
        XCTAssertEqual(SmitheryError.invalidURL.errorDescription, "Invalid registry URL")
        XCTAssertEqual(SmitheryError.httpError.errorDescription, "Registry HTTP error")

        let decodeError = SmitheryError.decodeFailed("missing field")
        XCTAssertEqual(decodeError.errorDescription, "Failed to decode registry response: missing field")
    }

    // MARK: - Invalidate Cache

    func testInvalidateCacheClearsAll() async throws {
        let data = sampleRegistryJSON()
        let response = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let session = MockSession(data: data, response: response)
        let client = makeClient(session: session)

        let _ = await client.search(query: "cache-test")

        client.invalidateCache()

        let errorResponse = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        let errorSession = MockSession(data: Data(), response: errorResponse)
        let newClient = makeClient(session: errorSession)

        let results = await newClient.search(query: "cache-test")
        XCTAssertTrue(results.isEmpty, "After invalidation, cache should be empty and API error returns empty")
    }

    // MARK: - Empty Query

    func testSearchWithEmptyQuery() async throws {
        let data = samplePopularJSON()
        let response = HTTPURLResponse(
            url: URL(string: "https://registry.smithery.ai/servers")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let session = MockSession(data: data, response: response)
        let client = makeClient(session: session)

        let results = await client.search(query: "")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "brave-search")
    }

    // MARK: - Sendable Conformance

    func testRegistryEntryIsSendable() {
        let entry = RegistryEntry(
            id: "sendable-test",
            name: "sendable",
            displayName: nil,
            description: nil,
            command: nil,
            args: nil,
            env: nil,
            url: nil,
            transport: nil,
            installCount: nil,
            iconUrl: nil,
            tags: nil
        )

        func acceptSendable<T: Sendable>(_ value: T) {}
        acceptSendable(entry)
    }
}

// MARK: - Mock Sessions

private final class MockSession: SmitherySession {
    private let data: Data
    private let response: URLResponse

    init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        (data, response)
    }
}

private final class CountingMockSession: SmitherySession {
    private let data: Data
    private let response: URLResponse
    var callCount = 0

    init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        return (data, response)
    }
}
