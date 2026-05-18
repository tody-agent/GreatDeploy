import XCTest
@testable import GreatDeploy

// MARK: - TransportTypeTests

final class TransportTypeTests: XCTestCase {

    func testAllCasesEncodeDecodeRoundtrip() {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for transport in TransportType.allCases {
            let data = try! encoder.encode(transport)
            let decoded = try! decoder.decode(TransportType.self, from: data)
            XCTAssertEqual(transport, decoded, "\(transport.rawValue) should roundtrip")
        }
    }

    func testDisplayNameCorrect() {
        XCTAssertEqual(TransportType.stdio.displayName, "Stdio")
        XCTAssertEqual(TransportType.sse.displayName, "SSE")
        XCTAssertEqual(TransportType.streamableHttp.displayName, "Streamable HTTP")
    }

    func testIconNameCorrect() {
        XCTAssertEqual(TransportType.stdio.iconName, "terminal")
        XCTAssertEqual(TransportType.sse.iconName, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(TransportType.streamableHttp.iconName, "network")
    }

    func testAllCasesCount() {
        XCTAssertEqual(TransportType.allCases.count, 3)
    }
}

// MARK: - MCPClientKindTests

final class MCPClientKindTests: XCTestCase {

    func testAllCasesEncodeDecodeRoundtrip() {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for client in MCPClientKind.allCases {
            let data = try! encoder.encode(client)
            let decoded = try! decoder.decode(MCPClientKind.self, from: data)
            XCTAssertEqual(client, decoded, "\(client.rawValue) should roundtrip")
        }
    }

    func testDisplayNameCorrect() {
        XCTAssertEqual(MCPClientKind.claudeDesktop.displayName, "Claude Desktop")
        XCTAssertEqual(MCPClientKind.cursor.displayName, "Cursor")
        XCTAssertEqual(MCPClientKind.vscode.displayName, "VS Code")
        XCTAssertEqual(MCPClientKind.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(MCPClientKind.windsurf.displayName, "Windsurf")
        XCTAssertEqual(MCPClientKind.zed.displayName, "Zed")
        XCTAssertEqual(MCPClientKind.jetbrains.displayName, "JetBrains IDE")
        XCTAssertEqual(MCPClientKind.codex.displayName, "Codex CLI")
        XCTAssertEqual(MCPClientKind.antigravity.displayName, "Antigravity")
    }

    func testIconNameNotEmpty() {
        for client in MCPClientKind.allCases {
            XCTAssertFalse(client.iconName.isEmpty, "\(client.rawValue) should have an icon name")
        }
    }

    func testConfigPathCorrect() {
        let claudePath = MCPClientKind.claudeDesktop.configPath
        XCTAssertNotNil(claudePath)
        XCTAssertTrue(claudePath!.path.contains("claude_desktop_config.json"))

        let cursorPath = MCPClientKind.cursor.configPath
        XCTAssertNotNil(cursorPath)
        XCTAssertTrue(cursorPath!.path.contains(".cursor/mcp.json"))

        let vscodePath = MCPClientKind.vscode.configPath
        XCTAssertNotNil(vscodePath)
        XCTAssertTrue(vscodePath!.path.contains("Code/User/settings.json"))

        let claudeCodePath = MCPClientKind.claudeCode.configPath
        XCTAssertNotNil(claudeCodePath)
        XCTAssertTrue(claudeCodePath!.path.contains(".claude/settings.json"))

        let windsurfPath = MCPClientKind.windsurf.configPath
        XCTAssertNotNil(windsurfPath)
        XCTAssertTrue(windsurfPath!.path.contains(".codeium/windsurf/mcp_config.json"))

        let zedPath = MCPClientKind.zed.configPath
        XCTAssertNotNil(zedPath)
        XCTAssertTrue(zedPath!.path.contains(".config/zed/settings.json"))

        let jetbrainsPath = MCPClientKind.jetbrains.configPath
        XCTAssertNotNil(jetbrainsPath)
        XCTAssertTrue(jetbrainsPath!.path.contains("JetBrains"))

        let codexPath = MCPClientKind.codex.configPath
        XCTAssertNotNil(codexPath)
        XCTAssertTrue(codexPath!.path.contains(".codex/config.toml"))

        XCTAssertNil(MCPClientKind.antigravity.configPath, "Antigravity should have no config path")
    }

    func testIsInstalledWithTempDir() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let jsonFile = tempDir.appendingPathComponent("config.json")
        FileManager.default.createFile(atPath: jsonFile.path, contents: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }

    func testBundleIdentifiers() {
        XCTAssertEqual(MCPClientKind.claudeDesktop.bundleIdentifier, "com.anthropic.claudefordesktop")
        XCTAssertEqual(MCPClientKind.cursor.bundleIdentifier, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(MCPClientKind.vscode.bundleIdentifier, "com.microsoft.VSCode")
        XCTAssertEqual(MCPClientKind.windsurf.bundleIdentifier, "com.windsurf.app")
        XCTAssertEqual(MCPClientKind.zed.bundleIdentifier, "dev.zed.Zed")
        XCTAssertNil(MCPClientKind.jetbrains.bundleIdentifier)
        XCTAssertNil(MCPClientKind.codex.bundleIdentifier)
        XCTAssertNil(MCPClientKind.antigravity.bundleIdentifier)
    }

    func testAllCasesCount() {
        XCTAssertEqual(MCPClientKind.allCases.count, 9)
    }
}

// MARK: - MCPServerDefinitionCodableTests

final class MCPServerDefinitionCodableTests: XCTestCase {

    func testEncodeServerWithSecretEnvDoesNotContainSecretValues() throws {
        let server = MCPServerDefinition(
            name: "test-server",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server"],
            env: [
                "OPENAI_API_KEY": "sk-secret-key-12345",
                "NODE_ENV": "production"
            ],
            url: nil,
            secretEnvKeys: ["OPENAI_API_KEY"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(server)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertFalse(json.contains("sk-secret-key-12345"), "Encoded JSON must NOT contain secret values")
        XCTAssertTrue(json.contains("OPENAI_API_KEY"), "Encoded JSON must contain the secret key NAME in secretEnvKeys")
        XCTAssertTrue(json.contains("production"), "Non-secret env values should be present")
    }

    func testDecodeJSONWithEnvValues() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "decoded-server",
            "enabled": true,
            "transport": "stdio",
            "command": "node",
            "args": ["server.js"],
            "env": {"API_KEY": "decoded-value", "DEBUG": "true"},
            "secretEnvKeys": ["API_KEY"],
            "tags": [],
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        let server = try decoder.decode(MCPServerDefinition.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(server.name, "decoded-server")
        XCTAssertEqual(server.env["API_KEY"], "decoded-value")
        XCTAssertEqual(server.env["DEBUG"], "true")
        XCTAssertEqual(server.secretEnvKeys, ["API_KEY"])
    }

    func testRoundtripPreservesNonSecretEnvAndSecretKeys() throws {
        var original = MCPServerDefinition(
            name: "roundtrip-server",
            displayName: "Roundtrip Server",
            enabled: true,
            transport: .sse,
            command: nil,
            args: [],
            env: [
                "PUBLIC_VAR": "visible",
                "SECRET_KEY": "super-secret-value",
                "ANOTHER_SECRET": "another-secret"
            ],
            url: "https://example.com/mcp",
            secretEnvKeys: ["SECRET_KEY", "ANOTHER_SECRET"],
            tags: ["test", "roundtrip"],
            source: "manual"
        )
        // Note: description property exists but cannot be used as init label due to CustomStringConvertible conflict

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertFalse(json.contains("super-secret-value"), "Secret value must not appear in JSON")
        XCTAssertFalse(json.contains("another-secret"), "Secret value must not appear in JSON")
        XCTAssertTrue(json.contains("visible"), "Non-secret value must appear in JSON")

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPServerDefinition.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.displayName, original.displayName)
        // Note: description property tested separately due to CustomStringConvertible conflict
        XCTAssertEqual(decoded.enabled, original.enabled)
        XCTAssertEqual(decoded.transport, original.transport)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.source, original.source)
        XCTAssertEqual(decoded.secretEnvKeys, original.secretEnvKeys)

        XCTAssertEqual(decoded.env["PUBLIC_VAR"], "visible", "Non-secret env must be preserved")
        XCTAssertNil(decoded.env["SECRET_KEY"], "Secret env value must be stripped after roundtrip")
        XCTAssertNil(decoded.env["ANOTHER_SECRET"], "Secret env value must be stripped after roundtrip")
        XCTAssertEqual(decoded.secretEnvKeys, ["SECRET_KEY", "ANOTHER_SECRET"], "Secret key names must be preserved")
    }

    func testDescriptionDoesNotContainEnvValues() {
        let server = MCPServerDefinition(
            name: "log-test",
            transport: .stdio,
            env: ["SECRET": "should-not-appear"],
            url: nil,
            secretEnvKeys: ["SECRET"]
        )

        let desc = server.description
        XCTAssertFalse(desc.contains("should-not-appear"), "description must not contain env values")
        XCTAssertFalse(desc.contains("SECRET"), "description must not contain secret key names")
        XCTAssertTrue(desc.contains("log-test"), "description must contain server name")
    }

    func testDebugDescriptionRedactsEnvValues() {
        let server = MCPServerDefinition(
            name: "debug-test",
            transport: .streamableHttp,
            command: "python",
            args: ["-m", "server"],
            env: ["TOKEN": "abc123", "LOG_LEVEL": "debug"],
            url: "https://api.example.com",
            secretEnvKeys: ["TOKEN"]
        )

        let debug = server.debugDescription

        XCTAssertFalse(debug.contains("abc123"), "debugDescription must not contain secret values")
        XCTAssertTrue(debug.contains("REDACTED"), "debugDescription must show REDACTED marker")
        XCTAssertTrue(debug.contains("1 secret keys"), "debugDescription must show secret key count")
        XCTAssertTrue(debug.contains("debug-test"), "debugDescription must contain server name")
        XCTAssertTrue(debug.contains("streamableHttp"), "debugDescription must contain transport")
    }

    func testServerWithNoSecretsEncodesEnvFully() throws {
        let server = MCPServerDefinition(
            name: "no-secrets",
            transport: .stdio,
            command: "echo",
            env: ["FOO": "bar", "BAZ": "qux"],
            url: nil,
            secretEnvKeys: []
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(server)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("bar"), "Non-secret env values should be in JSON")
        XCTAssertTrue(json.contains("qux"), "Non-secret env values should be in JSON")

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPServerDefinition.self, from: data)
        XCTAssertEqual(decoded.env["FOO"], "bar")
        XCTAssertEqual(decoded.env["BAZ"], "qux")
    }

    func testServerEqualityAndHashable() {
        let server1 = MCPServerDefinition(name: "test", transport: .stdio)
        let server2 = MCPServerDefinition(name: "test", transport: .stdio)
        let server3 = MCPServerDefinition(name: "different", transport: .stdio)

        XCTAssertEqual(server1, server2)
        XCTAssertNotEqual(server1, server3)
        XCTAssertEqual(server1.hashValue, server2.hashValue)
    }

    func testServerIdentifiable() {
        let server = MCPServerDefinition(name: "id-test", transport: .stdio)
        XCTAssertNotNil(server.id)
    }
}

// MARK: - MCPBundleCodableTests

final class MCPBundleCodableTests: XCTestCase {

    func testEncodeDecodeBundleWithThreeServers() throws {
        let servers = [
            MCPServerDefinition(name: "server-1", transport: .stdio, command: "cmd1"),
            MCPServerDefinition(name: "server-2", transport: .sse, url: "https://api.example.com"),
            MCPServerDefinition(name: "server-3", transport: .streamableHttp, url: "https://stream.example.com")
        ]

        let bundle = MCPBundle(
            name: "test-bundle",
            servers: servers,
            enabledClients: [.cursor, .claudeCode, .vscode]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(bundle)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPBundle.self, from: data)

        XCTAssertEqual(decoded.name, bundle.name)
        XCTAssertEqual(decoded.servers.count, 3)
        XCTAssertEqual(decoded.servers[0].name, "server-1")
        XCTAssertEqual(decoded.servers[1].name, "server-2")
        XCTAssertEqual(decoded.servers[2].name, "server-3")
        XCTAssertEqual(decoded.enabledClients, bundle.enabledClients)
        XCTAssertTrue(decoded.enabledClients.contains(.cursor))
        XCTAssertTrue(decoded.enabledClients.contains(.claudeCode))
        XCTAssertTrue(decoded.enabledClients.contains(.vscode))
    }

    func testEmptyBundleRoundtrip() throws {
        let bundle = MCPBundle(name: "empty-bundle")

        let encoder = JSONEncoder()
        let data = try encoder.encode(bundle)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPBundle.self, from: data)

        XCTAssertEqual(decoded.name, "empty-bundle")
        XCTAssertTrue(decoded.servers.isEmpty)
        XCTAssertTrue(decoded.enabledClients.isEmpty)
    }

    func testEnabledClientsSetRoundtrip() throws {
        let allClients = Set(MCPClientKind.allCases)
        let bundle = MCPBundle(
            name: "all-clients",
            enabledClients: allClients
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(bundle)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPBundle.self, from: data)

        XCTAssertEqual(decoded.enabledClients, allClients)
        XCTAssertEqual(decoded.enabledClients.count, MCPClientKind.allCases.count)
    }

    func testBundleIdentifiable() {
        let bundle = MCPBundle(name: "id-bundle")
        XCTAssertNotNil(bundle.id)
    }

    func testBundleDeviceOrigin() throws {
        let deviceUUID = UUID().uuidString
        let bundle = MCPBundle(name: "device-bundle", deviceOrigin: deviceUUID)

        let encoder = JSONEncoder()
        let data = try encoder.encode(bundle)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPBundle.self, from: data)

        XCTAssertEqual(decoded.deviceOrigin, deviceUUID)
    }
}

// MARK: - MCPSyncStateTests

final class MCPSyncStateTests: XCTestCase {

    func testPreviouslySyncedNamesCumulativeBehavior() {
        var state = MCPSyncState(clientId: .cursor)

        state.previouslySyncedNames.insert("server-a")
        state.previouslySyncedNames.insert("server-b")
        state.lastSyncedServerNames = ["server-a", "server-b"]

        XCTAssertEqual(state.previouslySyncedNames.count, 2)
        XCTAssertTrue(state.previouslySyncedNames.contains("server-a"))
        XCTAssertTrue(state.previouslySyncedNames.contains("server-b"))

        state.lastSyncedServerNames = ["server-a"]
        state.previouslySyncedNames.insert("server-c")

        XCTAssertTrue(state.previouslySyncedNames.contains("server-c"), "New server should be added to cumulative set")
        XCTAssertTrue(state.previouslySyncedNames.contains("server-b"), "Previously synced server should remain in set")
        XCTAssertEqual(state.previouslySyncedNames.count, 3, "Cumulative set should grow, not shrink")
    }

    func testEncodeDecodeRoundtripWithSet() throws {
        var state = MCPSyncState(
            clientId: .claudeCode,
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastSyncedServerNames: ["server-a", "server-b"],
            previouslySyncedNames: ["server-a", "server-b", "server-c", "old-server"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPSyncState.self, from: data)

        XCTAssertEqual(decoded.clientId, .claudeCode)
        XCTAssertNotNil(decoded.lastSyncedAt)
        XCTAssertEqual(decoded.lastSyncedServerNames, ["server-a", "server-b"])
        XCTAssertEqual(decoded.previouslySyncedNames.count, 4)
        XCTAssertTrue(decoded.previouslySyncedNames.contains("old-server"))
        XCTAssertTrue(decoded.previouslySyncedNames.contains("server-c"))
    }

    func testSyncStateEquality() {
        let state1 = MCPSyncState(
            clientId: .cursor,
            lastSyncedServerNames: ["a", "b"],
            previouslySyncedNames: ["a", "b", "c"]
        )
        let state2 = MCPSyncState(
            clientId: .cursor,
            lastSyncedServerNames: ["a", "b"],
            previouslySyncedNames: ["a", "b", "c"]
        )
        let state3 = MCPSyncState(
            clientId: .cursor,
            lastSyncedServerNames: ["a"],
            previouslySyncedNames: ["a", "b", "c"]
        )

        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }

    func testSyncStateHashable() {
        let state1 = MCPSyncState(clientId: .zed, previouslySyncedNames: ["x", "y"])
        let state2 = MCPSyncState(clientId: .zed, previouslySyncedNames: ["x", "y"])

        XCTAssertEqual(state1.hashValue, state2.hashValue)
    }
}

// MARK: - MCPSyncResultTests

final class MCPSyncResultTests: XCTestCase {

    func testSuccessResult() {
        let result = MCPSyncResult(
            client: .cursor,
            success: true,
            serversWritten: 3,
            warnings: ["Config file was empty"],
            durationMs: 150
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.client, .cursor)
        XCTAssertEqual(result.serversWritten, 3)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first, "Config file was empty")
        XCTAssertEqual(result.durationMs, 150)
    }

    func testFailureResultWithError() {
        let result = MCPSyncResult(
            client: .claudeDesktop,
            success: false,
            serversWritten: 0,
            error: "Permission denied: claude_desktop_config.json",
            durationMs: 50
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.client, .claudeDesktop)
        XCTAssertEqual(result.serversWritten, 0)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.error, "Permission denied: claude_desktop_config.json")
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.durationMs, 50)
    }

    func testWarningsCaptured() {
        let warnings = [
            "Server 'foo' has no command — skipped",
            "Config path does not exist — will create",
            "Client not running — changes may require restart"
        ]

        let result = MCPSyncResult(
            client: .windsurf,
            success: true,
            serversWritten: 2,
            warnings: warnings,
            durationMs: 200
        )

        XCTAssertEqual(result.warnings.count, 3)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.serversWritten, 2)
    }

    func testSendableConformance() {
        let result = MCPSyncResult(client: .zed, success: true)
        func acceptSendable<T: Sendable>(_ value: T) {}
        acceptSendable(result)
    }
}
