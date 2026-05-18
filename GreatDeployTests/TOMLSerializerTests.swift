import XCTest
@testable import GreatDeploy

final class TOMLSerializerTests: XCTestCase {

    // MARK: - serialize

    func test_serialize_producesValidTOML() throws {
        let servers: [MCPServerDefinition] = [
            MCPServerDefinition(name: "filesystem", command: "npx", args: ["-y", "@mcp/fs"]),
            MCPServerDefinition(name: "github", command: "npx", args: ["-y", "@mcp/github"], env: ["GITHUB_TOKEN": "ghp_xxx"]),
        ]

        let toml = TOMLSerializer.serialize(servers)

        XCTAssertTrue(toml.contains("[mcp_servers.filesystem]"))
        XCTAssertTrue(toml.contains("[mcp_servers.github]"))
        XCTAssertTrue(toml.contains("command = \"npx\""))
        XCTAssertTrue(toml.contains("args = [\"-y\", \"@mcp/fs\"]"))
        XCTAssertTrue(toml.contains("GITHUB_TOKEN = \"ghp_xxx\""))
    }

    func test_serialize_emptyServers_returnsEmptyString() {
        let toml = TOMLSerializer.serialize([])
        XCTAssertEqual(toml, "")
    }

    func test_serialize_disabledServer_outputsEnabledFalse() {
        let server = MCPServerDefinition(name: "disabled-server", enabled: false, command: "echo")
        let toml = TOMLSerializer.serialize([server])

        XCTAssertTrue(toml.contains("enabled = false"))
    }

    func test_serialize_excludesSecretEnvKeys() {
        let server = MCPServerDefinition(
            name: "secret-server",
            command: "npx",
            args: [],
            env: ["PUBLIC_KEY": "visible", "SECRET_KEY": "hidden"],
            secretEnvKeys: ["SECRET_KEY"]
        )
        let toml = TOMLSerializer.serialize([server])

        XCTAssertTrue(toml.contains("PUBLIC_KEY = \"visible\""))
        XCTAssertFalse(toml.contains("SECRET_KEY"))
    }

    func test_serialize_outputsUrlForSseTransport() {
        let server = MCPServerDefinition(
            name: "sse-server",
            transport: .sse,
            url: "http://localhost:3000/mcp"
        )
        let toml = TOMLSerializer.serialize([server])

        XCTAssertTrue(toml.contains("url = \"http://localhost:3000/mcp\""))
    }

    // MARK: - parse

    func test_parse_roundtrip() throws {
        let original: [MCPServerDefinition] = [
            MCPServerDefinition(name: "filesystem", command: "npx", args: ["-y", "@mcp/fs"]),
            MCPServerDefinition(name: "github", command: "npx", args: ["-y", "@mcp/github"], env: ["GITHUB_TOKEN": "ghp_xxx"]),
        ]

        let toml = TOMLSerializer.serialize(original)
        let parsed = try TOMLSerializer.parse(toml)

        XCTAssertEqual(parsed.count, 2)
        let names = Set(parsed.map(\.name))
        XCTAssertTrue(names.contains("filesystem"))
        XCTAssertTrue(names.contains("github"))

        let fs = parsed.first { $0.name == "filesystem" }!
        XCTAssertEqual(fs.command, "npx")
        XCTAssertEqual(fs.args, ["-y", "@mcp/fs"])

        let gh = parsed.first { $0.name == "github" }!
        XCTAssertEqual(gh.env["GITHUB_TOKEN"], "ghp_xxx")
    }

    func test_parse_emptyContent_returnsEmptyArray() throws {
        let servers = try TOMLSerializer.parse("")
        XCTAssertEqual(servers.count, 0)
    }

    func test_parse_missingSections_returnsEmptyArray() throws {
        let content = """
        # Just a comment
        some_key = "value"
        """
        let servers = try TOMLSerializer.parse(content)
        XCTAssertEqual(servers.count, 0)
    }

    func test_parse_inlineTableWithMultipleEntries() throws {
        let content = """
        [mcp_servers.multi-env]
        command = "npx"
        args = ["-y", "@mcp/server"]
        env = { KEY_ONE = "val1", KEY_TWO = "val2", KEY_THREE = "val3" }
        """
        let servers = try TOMLSerializer.parse(content)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].env["KEY_ONE"], "val1")
        XCTAssertEqual(servers[0].env["KEY_TWO"], "val2")
        XCTAssertEqual(servers[0].env["KEY_THREE"], "val3")
    }

    func test_parse_arrayWithMultipleEntries() throws {
        let content = """
        [mcp_servers.multi-args]
        command = "npx"
        args = ["-y", "@mcp/server", "--port", "3000", "--verbose"]
        """
        let servers = try TOMLSerializer.parse(content)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].args, ["-y", "@mcp/server", "--port", "3000", "--verbose"])
    }

    func test_parse_parsesFixture() throws {
        let bundle = Bundle(for: TOMLSerializerTests.self)
        guard let url = bundle.url(forResource: "codex_config", withExtension: "toml") else {
            throw XCTSkip("Fixture file not found")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let servers = try TOMLSerializer.parse(content)

        XCTAssertEqual(servers.count, 3)
        let names = Set(servers.map(\.name))
        XCTAssertTrue(names.contains("filesystem"))
        XCTAssertTrue(names.contains("github"))
        XCTAssertTrue(names.contains("user-codex-server"))

        let fs = servers.first { $0.name == "filesystem" }!
        XCTAssertEqual(fs.command, "npx")
        XCTAssertEqual(fs.args, ["-y", "@modelcontextprotocol/server-filesystem", "/Users/test"])

        let gh = servers.first { $0.name == "github" }!
        XCTAssertEqual(gh.env["GITHUB_TOKEN"], "ghp_xxx")
    }

    func test_parse_disabledServer() throws {
        let content = """
        [mcp_servers.offline]
        command = "echo"
        enabled = false
        """
        let servers = try TOMLSerializer.parse(content)
        XCTAssertEqual(servers.count, 1)
        XCTAssertFalse(servers[0].enabled)
    }
}
