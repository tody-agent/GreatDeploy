import Foundation
import Security

// MARK: - MacSecretStore

final class MacSecretStore: SecretStore, @unchecked Sendable {
    static let shared = MacSecretStore()
    private init() {}

    func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    func write(service: String, account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        var status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let updateAttrs: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw KeychainService.KeychainError.unexpectedStatus(status)
        }
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainService.KeychainError.unexpectedStatus(status)
        }
    }

    func deleteAll(servicePrefix: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainService.KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - MacFileSystem

final class MacFileSystem: FileSystem, @unchecked Sendable {
    static let shared = MacFileSystem()
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func readData(from url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func backup(_ url: URL) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).bak.\(timestamp)")
        try fileManager.copyItem(at: url, to: backupURL)
        return backupURL
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

// MARK: - MacProcessRunner

final class MacProcessRunner: ProcessRunner, @unchecked Sendable {
    static let shared = MacProcessRunner()

    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        var resolvedURL = executable

        if !FileManager.default.fileExists(atPath: executable.path) {
            if let fallback = resolveExecutable(executable.lastPathComponent) {
                resolvedURL = fallback
            }
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = resolvedURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "en_US.UTF-8"
        ]

        try process.run()

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        let exited = semaphore.wait(timeout: .now() + timeout) == .success
        if !exited {
            process.terminate()
            throw ProcessError.timeout(timeout)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }

    private func resolveExecutable(_ name: String) -> URL? {
        let searchPaths = ["/bin", "/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        for dir in searchPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

// MARK: - MacPlatform

final class MacPlatform: PlatformAdapter, @unchecked Sendable {
    static let shared = MacPlatform()

    var secretStore: SecretStore { MacSecretStore.shared }
    var fileSystem: FileSystem { MacFileSystem.shared }
    var processRunner: ProcessRunner { MacProcessRunner.shared }

    var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GreatDeploy")
    }

    var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GreatDeploy")
    }

    private init() {}
}
