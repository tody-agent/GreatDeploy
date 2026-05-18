import XCTest
@testable import GreatDeploy

final class MacPlatformTests: XCTestCase {

    private var fileSystem: MacFileSystem!
    private var processRunner: MacProcessRunner!
    private var secretStore: MacSecretStore!
    private var platform: MacPlatform!
    private var testDirectory: URL!

    override func setUp() {
        super.setUp()
        fileSystem = MacFileSystem()
        processRunner = MacProcessRunner()
        secretStore = MacSecretStore.shared
        platform = MacPlatform.shared
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GreatDeployTests-\(UUID().uuidString)")
        try? fileSystem.createDirectory(at: testDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        fileSystem = nil
        processRunner = nil
        secretStore = nil
        platform = nil
        super.tearDown()
    }

    // MARK: - MacFileSystem Tests

    func testAtomicWriteFileExistsWithCorrectContent() throws {
        let targetURL = testDirectory.appendingPathComponent("test.txt")
        let content = "Hello, GreatDeploy!"
        let data = content.data(using: .utf8)!

        try fileSystem.atomicWrite(data, to: targetURL)

        XCTAssertTrue(fileSystem.exists(targetURL))
        let readData = try fileSystem.readData(from: targetURL)
        XCTAssertNotNil(readData)
        XCTAssertEqual(String(data: readData!, encoding: .utf8), content)
    }

    func testBackupCreatesBakFileOriginalUnchanged() throws {
        let targetURL = testDirectory.appendingPathComponent("original.txt")
        let content = "Original content"
        try fileSystem.atomicWrite(content.data(using: .utf8)!, to: targetURL)

        let backupURL = try fileSystem.backup(targetURL)

        XCTAssertTrue(fileSystem.exists(backupURL))
        XCTAssertTrue(fileSystem.exists(targetURL))

        let backupData = try fileSystem.readData(from: backupURL)
        XCTAssertEqual(String(data: backupData!, encoding: .utf8), content)

        let originalData = try fileSystem.readData(from: targetURL)
        XCTAssertEqual(String(data: originalData!, encoding: .utf8), content)

        XCTAssertTrue(backupURL.lastPathComponent.contains(".bak."))
    }

    func testReadDataFromNonExistentReturnsNil() throws {
        let nonExistentURL = testDirectory.appendingPathComponent("does-not-exist.txt")
        let result = try fileSystem.readData(from: nonExistentURL)
        XCTAssertNil(result)
    }

    func testCreateDirectoryDirectoryExists() throws {
        let newDirURL = testDirectory.appendingPathComponent("nested/deep/dir")

        try fileSystem.createDirectory(at: newDirURL)

        XCTAssertTrue(fileSystem.exists(newDirURL))
    }

    // MARK: - MacProcessRunner Tests

    func testRunEchoCapturesStdout() async throws {
        let result = try await processRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/echo"),
            arguments: ["hello", "world"],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("hello world"))
    }

    func testRunWithTimeoutThrowsTimeoutError() async {
        do {
            _ = try await processRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                timeout: 0.5
            )
            XCTFail("Expected timeout error")
        } catch let error as ProcessError {
            if case .timeout = error {
                // Expected
            } else {
                XCTFail("Expected .timeout error, got \(error)")
            }
        } catch {
            XCTFail("Expected ProcessError, got \(error)")
        }
    }

    // MARK: - MacSecretStore Tests

    func testWriteThenReadValueMatches() throws {
        let service = "com.greatdeploy.tests.\(UUID().uuidString)"
        let account = "test-account"
        let value = "secret-value-12345"

        try secretStore.write(service: service, account: account, value: value)
        let retrieved = try secretStore.read(service: service, account: account)

        XCTAssertEqual(retrieved, value)

        try? secretStore.delete(service: service, account: account)
    }

    func testDeleteThenReadReturnsNil() throws {
        let service = "com.greatdeploy.tests.\(UUID().uuidString)"
        let account = "delete-test-account"
        let value = "to-be-deleted"

        try secretStore.write(service: service, account: account, value: value)
        try secretStore.delete(service: service, account: account)

        let retrieved = try secretStore.read(service: service, account: account)
        XCTAssertNil(retrieved)
    }

    // MARK: - MacPlatform Tests

    func testAppSupportDirectoryIsValidURL() {
        let url = platform.appSupportDirectory
        XCTAssertNotNil(url)
        XCTAssertTrue(url.path.contains("GreatDeploy"))
        XCTAssertTrue(url.path.contains("Application Support"))
    }

    func testLogsDirectoryIsValidURL() {
        let url = platform.logsDirectory
        XCTAssertNotNil(url)
        XCTAssertTrue(url.path.contains("GreatDeploy"))
        XCTAssertTrue(url.path.contains("Library/Logs"))
    }
}
