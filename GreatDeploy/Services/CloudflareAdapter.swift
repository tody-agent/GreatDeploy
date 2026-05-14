import Foundation
import os.log

/// Adapter for applying Cloudflare credentials to the system environment and Wrangler CLI
final class CloudflareAdapter: CloudflareAdapting {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "CloudflareAdapter")

    static let shared = CloudflareAdapter()

    private let homeDirectory: URL
    private let fileManager: FileManager
    private let launchctlRunner: ((String, [String]) throws -> Void)?
    private let launchctlEnvironmentReader: ((String) -> String?)?

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        launchctlRunner: ((String, [String]) throws -> Void)? = nil,
        launchctlEnvironmentReader: ((String) -> String?)? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.launchctlRunner = launchctlRunner
        self.launchctlEnvironmentReader = launchctlEnvironmentReader
    }
    
    /// Applies the Cloudflare token and account ID to the system
    /// - Parameters:
    ///   - token: The Cloudflare API Token
    ///   - accountId: The Cloudflare Account ID
    ///   - syncWranglerConfig: When true, also writes/removes Wrangler's plaintext config file.
    func applyToken(_ token: String, accountId: String, syncWranglerConfig: Bool = false) async throws {
        try await Task.detached(priority: .userInitiated) {
            // 1. Update macOS GUI environment variables via launchctl.
            try self.updateLaunchctlEnvironment(token: token, accountId: accountId)

            // 2. Wrangler config is plaintext, so keep it explicit opt-in only.
            if syncWranglerConfig {
                try self.updateWranglerConfig(token: token, accountId: accountId)
            }
        }.value
    }
    
    /// Clear all Cloudflare credentials
    func clearCredentials(syncWranglerConfig: Bool = false) async throws {
        try await applyToken("", accountId: "", syncWranglerConfig: syncWranglerConfig)
    }

    /// Reads the Cloudflare account ID visible to GUI apps via launchctl.
    func currentAccountId() async -> String? {
        if let launchctlEnvironmentReader {
            return launchctlEnvironmentReader("CLOUDFLARE_ACCOUNT_ID")
        }

        return await Task<String?, Never>.detached(priority: .utility) { () -> String? in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["getenv", "CLOUDFLARE_ACCOUNT_ID"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let completed = process.waitUntilExitOrTimeout(seconds: 5)
                guard completed, process.terminationStatus == 0 else {
                    if !completed {
                        process.terminate()
                    }
                    return nil
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value?.isEmpty == false ? value : nil
            } catch {
                return nil
            }
        }.value
    }

    private func updateLaunchctlEnvironment(token: String, accountId: String) throws {
        let setenvPath = "/bin/launchctl"

        try runLaunchctl(
            executablePath: setenvPath,
            arguments: token.isEmpty
                ? ["unsetenv", "CLOUDFLARE_API_TOKEN"]
                : ["setenv", "CLOUDFLARE_API_TOKEN", token]
        )

        try runLaunchctl(
            executablePath: setenvPath,
            arguments: accountId.isEmpty
                ? ["unsetenv", "CLOUDFLARE_ACCOUNT_ID"]
                : ["setenv", "CLOUDFLARE_ACCOUNT_ID", accountId]
        )
    }

    private func runLaunchctl(executablePath: String, arguments: [String]) throws {
        if let launchctlRunner {
            try launchctlRunner(executablePath, arguments)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        let completed = process.waitUntilExitOrTimeout(seconds: 10)
        if !completed {
            process.terminate()
            throw CloudflareAdapterError.processTimeout
        }
        guard process.terminationStatus == 0 else {
            throw CloudflareAdapterError.commandFailed
        }
    }

    private func updateWranglerConfig(token: String, accountId: String) throws {
        let primaryConfigDir = homeDirectory.appendingPathComponent(".wrangler/config", isDirectory: true)
        if !fileManager.fileExists(atPath: primaryConfigDir.path) {
            try fileManager.createDirectory(at: primaryConfigDir, withIntermediateDirectories: true, attributes: nil)
        }

        let configFile = primaryConfigDir.appendingPathComponent("default.toml")

        if token.isEmpty {
            if fileManager.fileExists(atPath: configFile.path) {
                try fileManager.removeItem(at: configFile)
            }
        } else {
            let content = """
            # Generated by GreatDeploy
            api_token = "\(Self.escapeTomlString(token))"
            account_id = "\(Self.escapeTomlString(accountId))"
            """
            guard let data = content.data(using: .utf8) else {
                throw CloudflareAdapterError.encodingFailed
            }
            try data.write(to: configFile, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        }
    }

    static func escapeTomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    enum CloudflareAdapterError: LocalizedError {
        case commandFailed
        case encodingFailed
        case processTimeout

        var errorDescription: String? {
            switch self {
            case .commandFailed:
                return "Cloudflare environment update failed"
            case .encodingFailed:
                return "Cloudflare config encoding failed"
            case .processTimeout:
                return "Cloudflare environment update timed out"
            }
        }
    }
}
