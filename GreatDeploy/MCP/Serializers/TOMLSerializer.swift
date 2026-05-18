import Foundation

/// Minimal TOML serializer/parser for Codex MCP config format.
/// ≤200 LOC — supports only the subset needed for MCP server configs.
enum TOMLSerializer {

    /// Serialize servers to TOML format.
    static func serialize(_ servers: [MCPServerDefinition]) -> String {
        var lines: [String] = []

        for server in servers {
            lines.append("[mcp_servers.\(escapeKey(server.name))]")

            if let command = server.command {
                lines.append("command = \(tomlString(command))")
            }

            if !server.args.isEmpty {
                let argsStr = server.args.map { tomlString($0) }.joined(separator: ", ")
                lines.append("args = [\(argsStr)]")
            }

            var envEntries: [String] = []
            for (key, value) in server.env where !server.secretEnvKeys.contains(key) {
                envEntries.append("\(escapeKey(key)) = \(tomlString(value))")
            }
            if !envEntries.isEmpty {
                lines.append("env = { \(envEntries.joined(separator: ", ")) }")
            }

            if let url = server.url {
                lines.append("url = \(tomlString(url))")
            }

            if !server.enabled {
                lines.append("enabled = false")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Parse TOML content to servers.
    static func parse(_ content: String) throws -> [MCPServerDefinition] {
        var servers: [MCPServerDefinition] = []
        var currentName: String?
        var currentCommand: String?
        var currentArgs: [String] = []
        var currentEnv: [String: String] = [:]
        var currentUrl: String?
        var currentEnabled = true
        var currentSecretKeys: [String] = []

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        func saveCurrent() {
            guard let name = currentName else { return }
            let server = MCPServerDefinition(
                name: name,
                enabled: currentEnabled,
                transport: currentUrl != nil ? .sse : .stdio,
                command: currentCommand,
                args: currentArgs,
                env: currentEnv,
                url: currentUrl,
                secretEnvKeys: currentSecretKeys,
                source: "codex"
            )
            servers.append(server)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("[mcp_servers.") && trimmed.hasSuffix("]") {
                saveCurrent()
                let inner = String(trimmed.dropFirst("[mcp_servers.".count).dropLast())
                currentName = unescapeKey(inner)
                currentCommand = nil
                currentArgs = []
                currentEnv = [:]
                currentUrl = nil
                currentEnabled = true
                currentSecretKeys = []
                continue
            }

            guard currentName != nil else { continue }

            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<eqIndex].trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)

                switch key {
                case "command":
                    currentCommand = parseTomlString(value)
                case "args":
                    currentArgs = parseTomlArray(value)
                case "env":
                    currentEnv = parseTomlInlineTable(value)
                case "url":
                    currentUrl = parseTomlString(value)
                case "enabled":
                    currentEnabled = (value == "true")
                default:
                    break
                }
            }
        }

        saveCurrent()
        return servers
    }

    // MARK: - Private helpers

    private static func tomlString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func escapeKey(_ key: String) -> String {
        if key.range(of: #"[^a-zA-Z0-9_-]"#, options: .regularExpression) != nil {
            return "\"\(key)\""
        }
        return key
    }

    private static func unescapeKey(_ key: String) -> String {
        if key.hasPrefix("\"") && key.hasSuffix("\"") {
            return String(key.dropFirst().dropLast())
        }
        return key
    }

    private static func parseTomlString(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseTomlArray(_ s: String) -> [String] {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return [] }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner.split(separator: ",").compactMap { part in
            parseTomlString(String(part.trimmingCharacters(in: .whitespaces)))
        }
    }

    private static func parseTomlInlineTable(_ s: String) -> [String: String] {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else { return [:] }
        let inner = String(trimmed.dropFirst().dropLast())

        var result: [String: String] = [:]
        let pairs = inner.split(separator: ",")
        for pair in pairs {
            let trimmedPair = pair.trimmingCharacters(in: .whitespaces)
            if let eqIndex = trimmedPair.firstIndex(of: "=") {
                let key = String(trimmedPair[..<eqIndex].trimmingCharacters(in: .whitespaces))
                let value = parseTomlString(String(trimmedPair[trimmedPair.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)))
                if let value = value {
                    result[key] = value
                }
            }
        }
        return result
    }
}
