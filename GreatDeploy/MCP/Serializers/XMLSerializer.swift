import Foundation

/// Minimal XML serializer/parser for JetBrains MCP config format.
/// Uses XMLParser (SAX) for parsing, string building for serialization.
enum XMLSerializer {

    /// Serialize servers to JetBrains XML format.
    static func serialize(_ servers: [MCPServerDefinition]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<mcpSettings version=\"1\">\n"
        xml += "  <servers>\n"

        for server in servers {
            var attrs = "name=\"\(escapeXml(server.name))\""
            if let command = server.command {
                attrs += " command=\"\(escapeXml(command))\""
            }
            if !server.args.isEmpty {
                attrs += " args=\"\(escapeXml(server.args.joined(separator: " ")))\""
            }
            if let url = server.url {
                attrs += " url=\"\(escapeXml(url))\""
            }
            attrs += " enabled=\"\(server.enabled)\""

            let hasEnv = !server.env.isEmpty
            if hasEnv {
                xml += "    <serverConfiguration \(attrs)>\n"
                xml += "      <envs>\n"
                for (key, value) in server.env {
                    xml += "        <env name=\"\(escapeXml(key))\" value=\"\(escapeXml(value))\"/>\n"
                }
                xml += "      </envs>\n"
                xml += "    </serverConfiguration>\n"
            } else {
                xml += "    <serverConfiguration \(attrs)/>\n"
            }
        }

        xml += "  </servers>\n"
        xml += "</mcpSettings>\n"
        return xml
    }

    /// Parse JetBrains XML to servers.
    static func parse(_ content: String) throws -> [MCPServerDefinition] {
        guard let data = content.data(using: .utf8) else {
            throw XMLError.invalidUTF8
        }

        let parser = XMLParser(data: data)
        let delegate = XMLParserDelegateImpl()
        parser.delegate = delegate
        parser.parse()

        if let error = parser.parserError {
            throw XMLError.parseFailed(error.localizedDescription)
        }

        return delegate.servers
    }

    private static func escapeXml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    enum XMLError: LocalizedError {
        case invalidUTF8
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidUTF8: return "Invalid UTF-8 content"
            case .parseFailed(let msg): return "XML parse failed: \(msg)"
            }
        }
    }
}

/// XMLParser delegate for parsing JetBrains MCP XML.
private class XMLParserDelegateImpl: NSObject, XMLParserDelegate {
    var servers: [MCPServerDefinition] = []

    private var currentServerName: String?
    private var currentCommand: String?
    private var currentArgs: String?
    private var currentUrl: String?
    private var currentEnabled = true
    private var currentEnv: [String: String] = [:]
    private var inEnvs = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "serverConfiguration":
            currentServerName = attributeDict["name"]
            currentCommand = attributeDict["command"]
            currentArgs = attributeDict["args"]
            currentUrl = attributeDict["url"]
            currentEnabled = attributeDict["enabled"] == "true"
            currentEnv = [:]
        case "envs":
            inEnvs = true
        case "env" where inEnvs:
            if let name = attributeDict["name"], let value = attributeDict["value"] {
                currentEnv[name] = value
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "serverConfiguration" {
            saveServer()
        } else if elementName == "envs" {
            inEnvs = false
        }
    }

    private func saveServer() {
        guard let name = currentServerName else { return }

        let args = currentArgs?.split(separator: " ").map(String.init).filter { !$0.isEmpty } ?? []

        let server = MCPServerDefinition(
            name: name,
            enabled: currentEnabled,
            transport: currentUrl != nil ? .sse : .stdio,
            command: currentCommand,
            args: args,
            env: currentEnv,
            url: currentUrl,
            source: "jetbrains"
        )
        servers.append(server)
    }
}
