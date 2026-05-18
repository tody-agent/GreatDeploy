import XCTest
@testable import GreatDeploy

final class XMLSerializerTests: XCTestCase {

    // MARK: - serialize

    func test_serialize_producesValidXmlOutput() {
        let servers: [MCPServerDefinition] = [
            MCPServerDefinition(name: "filesystem", command: "npx", args: ["-y", "@mcp/filesystem"]),
            MCPServerDefinition(name: "disabled-server", enabled: false, command: "echo", args: ["test"]),
        ]

        let xml = XMLSerializer.serialize(servers)

        XCTAssertTrue(xml.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xml.contains("<mcpSettings version=\"1\">"))
        XCTAssertTrue(xml.contains("<servers>"))
        XCTAssertTrue(xml.contains("name=\"filesystem\""))
        XCTAssertTrue(xml.contains("command=\"npx\""))
        XCTAssertTrue(xml.contains("args=\"-y @mcp/filesystem\""))
        XCTAssertTrue(xml.contains("enabled=\"false\""))
        XCTAssertTrue(xml.contains("</mcpSettings>"))
    }

    func test_serialize_handlesEnvEntries() {
        let server = MCPServerDefinition(
            name: "env-server",
            command: "npx",
            args: [],
            env: ["API_KEY": "secret123", "DEBUG": "true"]
        )

        let xml = XMLSerializer.serialize([server])

        XCTAssertTrue(xml.contains("<envs>"))
        XCTAssertTrue(xml.contains("name=\"API_KEY\""))
        XCTAssertTrue(xml.contains("value=\"secret123\""))
        XCTAssertTrue(xml.contains("name=\"DEBUG\""))
        XCTAssertTrue(xml.contains("value=\"true\""))
        XCTAssertTrue(xml.contains("</envs>"))
    }

    func test_serialize_escapesXmlSpecialCharacters() {
        let server = MCPServerDefinition(
            name: "test&<name>",
            command: "echo \"hello\" 'world'",
            args: ["a<b>c"]
        )

        let xml = XMLSerializer.serialize([server])

        XCTAssertTrue(xml.contains("test&amp;&lt;name&gt;"))
        XCTAssertTrue(xml.contains("echo &quot;hello&quot; &apos;world&apos;"))
        XCTAssertTrue(xml.contains("a&lt;b&gt;c"))
    }

    func test_serialize_selfClosingTag_whenNoEnv() {
        let server = MCPServerDefinition(name: "no-env", command: "echo", args: [])

        let xml = XMLSerializer.serialize([server])

        XCTAssertTrue(xml.contains("/>"))
        XCTAssertFalse(xml.contains("<envs>"))
    }

    // MARK: - parse

    func test_parse_roundtrip_serializesAndParsesBack() throws {
        let original: [MCPServerDefinition] = [
            MCPServerDefinition(name: "alpha", command: "npx", args: ["-y", "pkg"]),
            MCPServerDefinition(name: "beta", command: "echo", args: ["hello"], env: ["KEY": "val"]),
        ]

        let xml = XMLSerializer.serialize(original)
        let parsed = try XMLSerializer.parse(xml)

        XCTAssertEqual(parsed.count, 2)

        let names = Set(parsed.map(\.name))
        XCTAssertEqual(names, ["alpha", "beta"])

        let alpha = parsed.first { $0.name == "alpha" }
        XCTAssertEqual(alpha?.command, "npx")
        XCTAssertEqual(alpha?.args, ["-y", "pkg"])
        XCTAssertEqual(alpha?.transport, .stdio)

        let beta = parsed.first { $0.name == "beta" }
        XCTAssertEqual(beta?.command, "echo")
        XCTAssertEqual(beta?.env["KEY"], "val")
    }

    func test_parse_handlesEmptyServers() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <mcpSettings version="1">
          <servers>
          </servers>
        </mcpSettings>
        """

        let servers = try XMLSerializer.parse(xml)
        XCTAssertEqual(servers.count, 0)
    }

    func test_parse_handlesEnvEntries() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <mcpSettings version="1">
          <servers>
            <serverConfiguration name="env-test" command="npx" args="-y pkg" enabled="true">
              <envs>
                <env name="API_KEY" value="secret"/>
                <env name="DEBUG" value="1"/>
              </envs>
            </serverConfiguration>
          </servers>
        </mcpSettings>
        """

        let servers = try XMLSerializer.parse(xml)
        XCTAssertEqual(servers.count, 1)

        let server = servers.first!
        XCTAssertEqual(server.name, "env-test")
        XCTAssertEqual(server.env["API_KEY"], "secret")
        XCTAssertEqual(server.env["DEBUG"], "1")
    }

    func test_parse_handlesSseTransport_whenUrlPresent() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <mcpSettings version="1">
          <servers>
            <serverConfiguration name="sse-server" url="http://localhost:3000" enabled="true"/>
          </servers>
        </mcpSettings>
        """

        let servers = try XMLSerializer.parse(xml)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.transport, .sse)
        XCTAssertEqual(servers.first?.url, "http://localhost:3000")
    }

    func test_parse_handlesDisabledServer() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <mcpSettings version="1">
          <servers>
            <serverConfiguration name="disabled" command="echo" enabled="false"/>
          </servers>
        </mcpSettings>
        """

        let servers = try XMLSerializer.parse(xml)
        XCTAssertEqual(servers.count, 1)
        XCTAssertFalse(servers.first?.enabled ?? true)
    }

    func test_parse_throwsError_forInvalidXml() {
        let invalidXml = "<broken><unclosed>"

        XCTAssertThrowsError(try XMLSerializer.parse(invalidXml)) { error in
            XCTAssertTrue(error is XMLSerializer.XMLError)
        }
    }

    func test_parse_fixtureFile() throws {
        let bundle = Bundle(for: XMLSerializerTests.self)
        guard let url = bundle.url(forResource: "jetbrains_mcp", withExtension: "xml") else {
            throw XCTSkip("Fixture file not found")
        }
        let content = try String(contentsOf: url, encoding: .utf8)

        let servers = try XMLSerializer.parse(content)
        XCTAssertEqual(servers.count, 2)

        let names = Set(servers.map(\.name))
        XCTAssertTrue(names.contains("filesystem"))
        XCTAssertTrue(names.contains("user-jb-server"))

        let fs = servers.first { $0.name == "filesystem" }!
        XCTAssertEqual(fs.command, "npx")
        XCTAssertEqual(fs.args, ["-y", "@mcp/filesystem"])
        XCTAssertEqual(fs.env["API_KEY"], "test-key")
        XCTAssertTrue(fs.enabled)

        let jb = servers.first { $0.name == "user-jb-server" }!
        XCTAssertEqual(jb.command, "echo")
        XCTAssertEqual(jb.args, ["jetbrains-specific"])
    }
}
