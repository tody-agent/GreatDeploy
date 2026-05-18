import XCTest
@testable import GreatDeploy

// MARK: - Mock Implementations

final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    private func key(service: String, account: String) -> String {
        "\(service)::\(account)"
    }

    func read(service: String, account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key(service: service, account: account)]
    }

    func write(service: String, account: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key(service: service, account: account)] = value
    }

    func delete(service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key(service: service, account: account))
    }

    func deleteAll(servicePrefix: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let keysToRemove = storage.keys.filter { $0.hasPrefix("\(servicePrefix)::") }
        for key in keysToRemove {
            storage.removeValue(forKey: key)
        }
    }
}

final class MockFileSystem: FileSystem, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func atomicWrite(_ data: Data, to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[url.absoluteString] = data
    }

    func readData(from url: URL) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[url.absoluteString]
    }

    func exists(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage[url.absoluteString] != nil
    }

    func backup(_ url: URL) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let backupURL = URL(string: "\(url.absoluteString).bak.\(timestamp)")!
        if let data = storage[url.absoluteString] {
            storage[backupURL.absoluteString] = data
        }
        return backupURL
    }

    func createDirectory(at url: URL) throws {
        // No-op for mock
    }
}

final class MockProcessRunner: ProcessRunner, Sendable {
    private let lock = NSLock()
    private var _result: ProcessResult?

    func setMockResult(_ result: ProcessResult) {
        lock.lock()
        defer { lock.unlock() }
        _result = result
    }

    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        lock.lock()
        defer { lock.unlock() }
        guard let result = _result else {
            return ProcessResult(stdout: "", stderr: "", exitCode: 0)
        }
        return result
    }
}

final class MockPlatform: PlatformAdapter, Sendable {
    let secretStore: SecretStore
    let fileSystem: FileSystem
    let processRunner: ProcessRunner
    let appSupportDirectory: URL
    let logsDirectory: URL

    init(
        secretStore: SecretStore,
        fileSystem: FileSystem,
        processRunner: ProcessRunner,
        appSupportDirectory: URL = URL(fileURLWithPath: "/tmp/GreatDeploy"),
        logsDirectory: URL = URL(fileURLWithPath: "/tmp/GreatDeploy/Logs")
    ) {
        self.secretStore = secretStore
        self.fileSystem = fileSystem
        self.processRunner = processRunner
        self.appSupportDirectory = appSupportDirectory
        self.logsDirectory = logsDirectory
    }
}

// MARK: - Tests

final class PlatformProtocolTests: XCTestCase {

    // MARK: - SecretStore Tests

    func testSecretStoreWriteAndRead() throws {
        let store = MockSecretStore()
        try store.write(service: "com.test", account: "user1", value: "secret-token-123")
        let result = try store.read(service: "com.test", account: "user1")
        XCTAssertEqual(result, "secret-token-123")
    }

    func testSecretStoreReadNonExistentReturnsNil() throws {
        let store = MockSecretStore()
        let result = try store.read(service: "com.test", account: "nonexistent")
        XCTAssertNil(result)
    }

    func testSecretStoreDelete() throws {
        let store = MockSecretStore()
        try store.write(service: "com.test", account: "user1", value: "token")
        try store.delete(service: "com.test", account: "user1")
        let result = try store.read(service: "com.test", account: "user1")
        XCTAssertNil(result)
    }

    func testSecretStoreDeleteNonExistentDoesNotThrow() throws {
        let store = MockSecretStore()
        try store.delete(service: "com.test", account: "nonexistent")
    }

    func testSecretStoreOverwrite() throws {
        let store = MockSecretStore()
        try store.write(service: "com.test", account: "user1", value: "old-token")
        try store.write(service: "com.test", account: "user1", value: "new-token")
        let result = try store.read(service: "com.test", account: "user1")
        XCTAssertEqual(result, "new-token")
    }

    func testSecretStoreDeleteAll() throws {
        let store = MockSecretStore()
        try store.write(service: "com.github", account: "user1", value: "token1")
        try store.write(service: "com.github", account: "user2", value: "token2")
        try store.write(service: "com.cloudflare", account: "user1", value: "token3")

        try store.deleteAll(servicePrefix: "com.github")

        XCTAssertNil(try store.read(service: "com.github", account: "user1"))
        XCTAssertNil(try store.read(service: "com.github", account: "user2"))
        XCTAssertEqual(try store.read(service: "com.cloudflare", account: "user1"), "token3")
    }

    // MARK: - FileSystem Tests

    func testFileSystemAtomicWriteAndRead() throws {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/test-file.txt")
        let data = "Hello, World!".data(using: .utf8)!

        try fs.atomicWrite(data, to: url)
        let readData = try fs.readData(from: url)

        XCTAssertEqual(readData, data)
    }

    func testFileSystemReadNonExistentReturnsNil() throws {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/nonexistent.txt")
        let result = try fs.readData(from: url)
        XCTAssertNil(result)
    }

    func testFileSystemExists() throws {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/existing.txt")
        let data = "test".data(using: .utf8)!

        XCTAssertFalse(fs.exists(url))
        try fs.atomicWrite(data, to: url)
        XCTAssertTrue(fs.exists(url))
    }

    func testFileSystemBackup() throws {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/config.json")
        let data = "{\"key\": \"value\"}".data(using: .utf8)!

        try fs.atomicWrite(data, to: url)
        let backupURL = try fs.backup(url)

        XCTAssertTrue(fs.exists(backupURL))
        let backupData = try fs.readData(from: backupURL)
        XCTAssertEqual(backupData, data)
    }

    func testFileSystemCreateDirectory() throws {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/nested/deep/dir")
        try fs.createDirectory(at: url)
        // No-op in mock, should not throw
    }

    // MARK: - ProcessRunner Tests

    func testProcessRunnerReturnsMockResult() async throws {
        let runner = MockProcessRunner()
        let expected = ProcessResult(
            stdout: "git version 2.39.0",
            stderr: "",
            exitCode: 0
        )
        runner.setMockResult(expected)

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["--version"],
            timeout: 5.0
        )

        XCTAssertEqual(result.stdout, "git version 2.39.0")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testProcessRunnerReturnsErrorOutput() async throws {
        let runner = MockProcessRunner()
        runner.setMockResult(ProcessResult(
            stdout: "",
            stderr: "fatal: not a git repository",
            exitCode: 128
        ))

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["status"],
            timeout: 5.0
        )

        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "fatal: not a git repository")
        XCTAssertEqual(result.exitCode, 128)
    }

    // MARK: - ProcessError Tests

    func testProcessErrorTimeoutDescription() {
        let error = ProcessError.timeout(10.0)
        XCTAssertEqual(error.errorDescription, "Process timed out after 10.0 seconds")
    }

    func testProcessErrorExecutionFailedDescription() {
        let error = ProcessError.executionFailed(1, "command not found")
        XCTAssertEqual(error.errorDescription, "Process failed with exit code 1: command not found")
    }

    func testProcessErrorNotFoundDescription() {
        let url = URL(fileURLWithPath: "/usr/local/bin/nonexistent")
        let error = ProcessError.notFound(url)
        XCTAssertEqual(error.errorDescription, "Executable not found: /usr/local/bin/nonexistent")
    }

    // MARK: - Platform Integration Tests

    func testMockPlatformCombinesAllMocks() async throws {
        let secretStore = MockSecretStore()
        let fileSystem = MockFileSystem()
        let processRunner = MockProcessRunner()

        processRunner.setMockResult(ProcessResult(
            stdout: "test-user",
            stderr: "",
            exitCode: 0
        ))

        let platform = MockPlatform(
            secretStore: secretStore,
            fileSystem: fileSystem,
            processRunner: processRunner
        )

        try platform.secretStore.write(service: "test", account: "key", value: "secret")
        XCTAssertEqual(try platform.secretStore.read(service: "test", account: "key"), "secret")

        let data = "config".data(using: .utf8)!
        let url = URL(fileURLWithPath: "/tmp/test-config")
        try platform.fileSystem.atomicWrite(data, to: url)
        XCTAssertTrue(platform.fileSystem.exists(url))

        let result = try await platform.processRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/whoami"),
            arguments: [],
            timeout: 5.0
        )
        XCTAssertEqual(result.stdout, "test-user")

        XCTAssertEqual(platform.appSupportDirectory.path, "/tmp/GreatDeploy")
        XCTAssertEqual(platform.logsDirectory.path, "/tmp/GreatDeploy/Logs")
    }

    func testPlatformGlobalInstanceExists() {
        let _ = Platform.current
        XCTAssertNotNil(Platform.current.secretStore)
        XCTAssertNotNil(Platform.current.fileSystem)
        XCTAssertNotNil(Platform.current.processRunner)
    }

    func testProcessResultIsSendable() {
        let result = ProcessResult(stdout: "out", stderr: "err", exitCode: 0)
        let _ = result as Sendable
        XCTAssertEqual(result.stdout, "out")
        XCTAssertEqual(result.stderr, "err")
        XCTAssertEqual(result.exitCode, 0)
    }
}
