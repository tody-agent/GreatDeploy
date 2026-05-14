import XCTest
@testable import GreatDeploy

final class CloudflareAdapterTests: XCTestCase {

    func testWranglerConfigIsNotWrittenWhenSyncIsDisabled() async throws {
        let harness = try AdapterHarness()

        try await harness.adapter.applyToken(
            "token-without-file",
            accountId: "account-id",
            syncWranglerConfig: false
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.configFile.path))
        XCTAssertEqual(harness.launchctlCalls.count, 2)
    }

    func testWranglerConfigWritesEscapedTomlWithSecurePermissionsWhenSyncIsEnabled() async throws {
        let harness = try AdapterHarness()

        try await harness.adapter.applyToken(
            "tok\"en\\with\nline",
            accountId: "acc\tid",
            syncWranglerConfig: true
        )

        let content = try String(contentsOf: harness.configFile, encoding: .utf8)
        XCTAssertTrue(content.contains(#"api_token = "tok\"en\\with\nline""#))
        XCTAssertTrue(content.contains(#"account_id = "acc\tid""#))

        let attributes = try FileManager.default.attributesOfItem(atPath: harness.configFile.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testClearCredentialsRemovesWranglerConfigOnlyWhenSyncIsEnabled() async throws {
        let harness = try AdapterHarness()
        try await harness.adapter.applyToken("token-123", accountId: "account-id", syncWranglerConfig: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.configFile.path))

        try await harness.adapter.clearCredentials(syncWranglerConfig: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.configFile.path))

        try await harness.adapter.clearCredentials(syncWranglerConfig: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.configFile.path))
    }

    func testCurrentAccountIdReadsLaunchctlEnvironment() async throws {
        let harness = try AdapterHarness()

        try await harness.adapter.applyToken("token-123", accountId: "account-id", syncWranglerConfig: false)

        let accountId = await harness.adapter.currentAccountId()
        XCTAssertEqual(accountId, "account-id")
    }
}

private final class AdapterHarness {
    let homeDirectory: URL
    let configFile: URL
    let adapter: CloudflareAdapter
    private let recorder = LaunchctlCallRecorder()

    var launchctlCalls: [(path: String, arguments: [String])] {
        recorder.calls
    }

    init() throws {
        homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GreatDeployCloudflareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        configFile = homeDirectory
            .appendingPathComponent(".wrangler/config", isDirectory: true)
            .appendingPathComponent("default.toml")

        adapter = CloudflareAdapter(
            homeDirectory: homeDirectory,
            launchctlRunner: { [recorder] path, arguments in
                recorder.calls.append((path, arguments))
                recorder.apply(arguments: arguments)
            },
            launchctlEnvironmentReader: { [recorder] name in
                recorder.environment[name]
            }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: homeDirectory)
    }
}

private final class LaunchctlCallRecorder {
    var calls: [(path: String, arguments: [String])] = []
    var environment: [String: String] = [:]

    func apply(arguments: [String]) {
        guard arguments.count >= 2 else { return }

        switch arguments[0] {
        case "setenv" where arguments.count >= 3:
            environment[arguments[1]] = arguments[2]
        case "unsetenv":
            environment[arguments[1]] = nil
        default:
            break
        }
    }
}
