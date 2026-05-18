import Foundation

protocol KeychainServicing {
    func readGitHubCredential() throws -> (username: String, token: String)?
    func updateGitHubCredential(username: String, token: String) throws
    func deleteGitHubCredential() throws
    func hasGitHubCredential(for username: String?) -> Bool

    func saveAccountToken(accountId: UUID, token: String) throws
    func readAccountToken(accountId: UUID) -> String?
    func deleteAccountToken(accountId: UUID) throws

    func saveCloudflareToken(accountId: UUID, token: String) throws
    func readCloudflareToken(accountId: UUID) -> String?
    func deleteCloudflareToken(accountId: UUID) throws
}

protocol GitConfigServicing {
    func ensureOsxKeychainHelper() throws
    func getCurrentConfigAsync() async throws -> (name: String?, email: String?)
    func setGlobalUserConfigAsync(name: String, email: String) async throws
    func clearGitHubCredentialCacheAsync() async throws
}

protocol GitHubCLIServicing {
    var isInstalled: Bool { get }
    func switchAccount(to username: String) async throws -> String
}

protocol CloudflareAdapting {
    func applyToken(_ token: String, accountId: String, syncWranglerConfig: Bool) async throws
    func clearCredentials(syncWranglerConfig: Bool) async throws
    func currentAccountId() async -> String?
}

// MARK: - Platform Protocols (v2)

/// Protocol for secure secret storage abstraction.
/// Current implementation: macOS Keychain via KeychainService.
/// Future: Linux Secret Service, Windows Credential Manager.
protocol SecretStore: Sendable {
    /// Read a secret value. Returns nil if not found.
    func read(service: String, account: String) throws -> String?

    /// Write a secret value. Overwrites if exists.
    func write(service: String, account: String, value: String) throws

    /// Delete a specific secret.
    func delete(service: String, account: String) throws

    /// Delete all secrets matching a service prefix (bulk cleanup).
    func deleteAll(servicePrefix: String) throws
}

/// Result from a process execution.
struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Protocol for subprocess execution abstraction.
protocol ProcessRunner: Sendable {
    /// Run a subprocess with timeout.
    /// - Parameters:
    ///   - executable: URL to the executable
    ///   - arguments: Command arguments (NOT shell-joined)
    ///   - timeout: Maximum execution time in seconds
    /// - Returns: ProcessResult with stdout, stderr, exitCode
    /// - Throws: ProcessError on timeout or execution failure
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

extension ProcessRunner {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        try await run(executable: URL(fileURLWithPath: executable), arguments: arguments, timeout: timeout)
    }
}

enum ProcessError: LocalizedError {
    case timeout(TimeInterval)
    case executionFailed(Int32, String)
    case notFound(URL)

    var errorDescription: String? {
        switch self {
        case .timeout(let t): return "Process timed out after \(t) seconds"
        case .executionFailed(let code, let err): return "Process failed with exit code \(code): \(err)"
        case .notFound(let url): return "Executable not found: \(url.path)"
        }
    }
}

/// Protocol for filesystem operations abstraction.
protocol FileSystem: Sendable {
    /// Atomically write data to a URL (write .tmp, rename).
    func atomicWrite(_ data: Data, to url: URL) throws

    /// Read data from a URL. Returns nil if not found.
    func readData(from url: URL) throws -> Data?

    /// Check if a URL exists.
    func exists(_ url: URL) -> Bool

    /// Create a backup of a file. Returns the backup URL.
    /// Backup naming: <original>.bak.<ISO8601>
    func backup(_ url: URL) throws -> URL

    /// Create directory and all intermediate directories.
    func createDirectory(at url: URL) throws
}

/// Top-level platform abstraction combining secret storage, filesystem, and process execution.
protocol PlatformAdapter: Sendable {
    var secretStore: SecretStore { get }
    var fileSystem: FileSystem { get }
    var processRunner: ProcessRunner { get }
    var appSupportDirectory: URL { get }
    var logsDirectory: URL { get }
}

/// Global platform instance. Default: MacPlatform.
/// Override for testing with mock implementations.
enum Platform {
    static var current: PlatformAdapter = MacPlatform.shared
}

// MARK: - v2 Multi-Tool Protocols

struct CryptoEnvelope: Codable, Equatable {
    let v: Int
    let alg: String
    let kdf: CryptoEnvelope.KDFParams
    let nonce: Data
    let ct: Data
    let aad: String?
    
    struct KDFParams: Codable, Equatable {
        let name: String
        let salt: Data
        let memKiB: Int
        let iters: Int
        let parallel: Int
    }
}

struct SignedManifest: Codable, Equatable {
    let payload: Data
    let hmac: Data
    let alg: String
}

protocol ToolDiscoveryServicing {
    func discoverInstalledTools() -> [ToolDiscoveryService.DiscoveryResult]
    func discoverTool(_ tool: AITool) -> ToolDiscoveryService.DiscoveryResult
    func installedTools() -> [AITool]
    func installedSkillsCapableTools() -> [AITool]
    func installedMCPCapableTools() -> [AITool]
}

protocol SkillRegistryServicing {
    func listMasterSkills() throws -> [RegisteredSkill]
    func getMasterSkill(name: String) throws -> RegisteredSkill?
    func installSkill(name: String, content: String) throws -> RegisteredSkill
    func updateSkill(name: String, content: String) throws
    func deleteSkill(name: String) throws
    func createSkill(name: String, description: String) throws -> RegisteredSkill
    func importFromTool(skillName: String, from tool: AITool, content: String) throws -> RegisteredSkill
    func updateSyncRecord(for skillName: String, tool: AITool, record: ToolSyncRecord)
    func saveSyncRecords(_ records: [AITool: ToolSyncRecord], for skillName: String)
}

protocol SkillsServicing {
    func skillsDirectory(for tool: AITool) -> URL?
    func projectSkillsSubpath(for tool: AITool) -> String?
    func scanGlobalSkills() throws -> [URL]
    func scanProjectSkills(at projectDir: URL) throws -> [URL]
    func scanGlobalSkills(for tool: AITool) throws -> [URL]
    func scanGlobalSkillItems() throws -> [SkillItem]
    func scanProjectSkillItems(at projectDir: URL) throws -> [SkillItem]
    func scanGlobalSkillItems(for tool: AITool) throws -> [SkillItem]
}

protocol ToolSyncServicing {
    func syncSkillToTool(skillName: String, tool: AITool) throws -> ToolSyncService.SyncResult
    func syncSkillToAllTools(skillName: String) -> ToolSyncService.BatchSyncResult
    func syncAllSkillsToAllTools() -> ToolSyncService.BatchSyncResult
    func syncAllSkillsToTool(tool: AITool) -> ToolSyncService.BatchSyncResult
    func pullSkillFromTool(skillName: String, from tool: AITool) throws -> RegisteredSkill
}

protocol MCPRegistryServicing {
    func listMasterServers() throws -> [RegisteredMCPServer]
    func getMasterServer(name: String) throws -> RegisteredMCPServer?
    func installServer(_ config: MCPServerConfig) throws -> RegisteredMCPServer
    func updateServer(_ config: MCPServerConfig) throws
    func deleteServer(name: String) throws
    func importFromTool(config: MCPServerConfig, from tool: AITool) throws -> RegisteredMCPServer
    func updateSyncRecord(for serverName: String, tool: AITool, record: ToolSyncRecord)
    func saveSyncRecords(_ records: [AITool: ToolSyncRecord], for serverName: String)
    func readMasterConfigs() throws -> [String: MCPServerConfig]
}

protocol MCPSyncServicing {
    func syncServerToTool(serverName: String, tool: AITool) throws -> MCPSyncService.SyncResult
    func syncAllServersToAllTools() -> MCPSyncService.BatchSyncResult
    func syncAllServersToTool(tool: AITool) -> MCPSyncService.BatchSyncResult
    func pullServersFromTool(_ tool: AITool) throws -> [RegisteredMCPServer]
}

protocol MCPConfigServicing {
    func isClaudeDesktopRunning() -> Bool
    func readClaudeDesktopConfig() throws -> [String: Any]
    func writeClaudeDesktopConfig(_ config: [String: Any]) throws
    func getMCPServers() throws -> [MCPServerConfig]
    func setMCPServer(_ server: MCPServerConfig) throws
    func removeMCPServer(named name: String) throws
    func readProjectMCPConfig(at projectDir: URL) throws -> [String: Any]
    func writeProjectMCPConfig(_ config: [String: Any], at projectDir: URL) throws
}


// MARK: - Additional v2 Types

struct SkillSource: Codable {
    let name: String
    let url: String
    let type: String
    init(name: String, url: String, type: String) {
        self.name = name
        self.url = url
        self.type = type
    }
}

struct SkillEntry: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let source: String
    let version: String
    let lastSynced: Date?
    init(id: String, name: String, description: String, source: String, version: String, lastSynced: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.source = source
        self.version = version
        self.lastSynced = lastSynced
    }
}

struct SkillExport: Codable {
    let skill: SkillEntry
    let format: String
    let content: String
    init(skill: SkillEntry, format: String, content: String) {
        self.skill = skill
        self.format = format
        self.content = content
    }
}

struct SyncReport: Codable {
    let source: AITool
    let destination: AITool
    let newSkills: [SkillEntry]
    let updatedSkills: [SkillEntry]
    let conflicts: [SkillEntry]
    let timestamp: Date
    init(source: AITool, destination: AITool, newSkills: [SkillEntry], updatedSkills: [SkillEntry], conflicts: [SkillEntry], timestamp: Date) {
        self.source = source
        self.destination = destination
        self.newSkills = newSkills
        self.updatedSkills = updatedSkills
        self.conflicts = conflicts
        self.timestamp = timestamp
    }
}

struct MCPServerExportItem: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]
    let transport: String
    let enabled: Bool
    let lastSynced: Date?
    init(id: String, name: String, command: String, args: [String], env: [String: String], transport: String, enabled: Bool, lastSynced: Date? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.transport = transport
        self.enabled = enabled
        self.lastSynced = lastSynced
    }
}

struct MCPExport: Codable {
    let server: MCPServerExportItem
    let tool: AITool
    let config: String
    init(server: MCPServerExportItem, tool: AITool, config: String) {
        self.server = server
        self.tool = tool
        self.config = config
    }
}

struct MCPSyncReport: Codable {
    let source: AITool
    let destination: AITool
    let newServers: [MCPServerExportItem]
    let updatedServers: [MCPServerExportItem]
    let conflicts: [MCPServerExportItem]
    let timestamp: Date
    init(source: AITool, destination: AITool, newServers: [MCPServerExportItem], updatedServers: [MCPServerExportItem], conflicts: [MCPServerExportItem], timestamp: Date) {
        self.source = source
        self.destination = destination
        self.newServers = newServers
        self.updatedServers = updatedServers
        self.conflicts = conflicts
        self.timestamp = timestamp
    }
}
