import Foundation

/// Shared helpers for JSON-based MCP client adapters.
enum JSONAdapterHelpers {
    /// Parse servers from a JSON config with the given mcpServers key path.
    static func parseServers(from content: String, keyPath: [String] = ["mcpServers"]) throws -> [MCPServerDefinition] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var current: Any = json
        for key in keyPath {
            guard let dict = current as? [String: Any],
                  let value = dict[key] else {
                return []
            }
            current = value
        }

        guard let serversDict = current as? [String: Any] else {
            return []
        }

        return serversDict.map { name, value in
            jsonValueToServer(name: name, value: value)
        }
    }

    /// Merge and serialize servers into JSON config.
    static func serializeServers(
        _ servers: [MCPServerDefinition],
        existingContent: String?,
        previouslySyncedNames: Set<String>,
        keyPath: [String] = ["mcpServers"]
    ) throws -> String {
        var root: [String: Any] = [:]

        if let existingContent,
           let data = existingContent.data(using: .utf8),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        // Get existing servers from the nested path
        let existingServers = getNestedValue(in: root, keyPath: keyPath) as? [String: Any] ?? [:]

        // Compute preserved (user-added) servers
        var preservedServers: [String: Any] = [:]
        for (name, value) in existingServers {
            let matchedPreviously = previouslySyncedNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            if !matchedPreviously {
                preservedServers[name] = value
            }
        }

        // Compute bundle servers
        let bundleServers = Dictionary(uniqueKeysWithValues: servers.map { ($0.name, serverToJSONDict($0)) })

        // Merge: preserved + bundle (bundle overwrites on conflict)
        let mergedServers = preservedServers.merging(bundleServers) { _, new in new }

        // Set the merged servers back into root at the nested path
        setNestedValue(mergedServers, in: &root, keyPath: keyPath)

        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        let data = try JSONSerialization.data(withJSONObject: root, options: options)
        guard let result = String(data: data, encoding: .utf8) else {
            throw MCPAdapterError.serializationFailed
        }
        return result
    }

    /// Get a value from a nested dictionary path.
    private static func getNestedValue(in dict: [String: Any], keyPath: [String]) -> Any? {
        var current: Any = dict
        for key in keyPath {
            guard let d = current as? [String: Any] else { return nil }
            guard let value = d[key] else { return nil }
            current = value
        }
        return current
    }

    /// Set a value into a nested dictionary path, creating intermediates as needed.
    private static func setNestedValue(_ value: Any, in dict: inout [String: Any], keyPath: [String]) {
        guard let firstKey = keyPath.first else { return }
        if keyPath.count == 1 {
            dict[firstKey] = value
        } else {
            var child = dict[firstKey] as? [String: Any] ?? [:]
            setNestedValue(value, in: &child, keyPath: Array(keyPath.dropFirst()))
            dict[firstKey] = child
        }
    }

    /// Convert a JSON value to an MCPServerDefinition.
    static func jsonValueToServer(name: String, value: Any) -> MCPServerDefinition {
        guard let dict = value as? [String: Any] else {
            return MCPServerDefinition(name: name, enabled: true)
        }

        let command = dict["command"] as? String
        let args = dict["args"] as? [String] ?? []
        let env = dict["env"] as? [String: String] ?? [:]
        let url = dict["url"] as? String
        let transportRaw = dict["transport"] as? String
        let disabled = dict["disabled"] as? Bool ?? false

        let transport: TransportType
        if let transportRaw {
            if transportRaw == "streamable-http" || transportRaw == "streamableHttp" {
                transport = .streamableHttp
            } else if transportRaw == "sse" {
                transport = .sse
            } else {
                transport = .stdio
            }
        } else if url != nil {
            transport = .sse
        } else {
            transport = .stdio
        }

        return MCPServerDefinition(
            name: name,
            enabled: !disabled,
            transport: transport,
            command: command,
            args: args,
            env: env,
            url: url
        )
    }

    /// Convert an MCPServerDefinition to a JSON-compatible dictionary.
    static func serverToJSONDict(_ server: MCPServerDefinition) -> [String: Any] {
        var dict: [String: Any] = [:]

        if server.transport == .sse || server.transport == .streamableHttp {
            if let url = server.url {
                dict["url"] = url
            }
            if server.transport == .streamableHttp {
                dict["transport"] = "streamable-http"
            }
        }

        if let command = server.command {
            dict["command"] = command
        }
        if !server.args.isEmpty {
            dict["args"] = server.args
        }
        if !server.env.isEmpty {
            dict["env"] = server.env
        }
        if !server.enabled {
            dict["disabled"] = true
        }

        return dict
    }
}
