import XCTest
@testable import GreatDeploy

@MainActor
final class ICloudKVSSyncTests: XCTestCase {

    // MARK: - InMemorySyncProvider Tests

    func testInMemoryPushPullRoundtrip() async throws {
        let provider = InMemorySyncProvider()
        let bundle = MCPBundle(name: "Test Bundle")

        try await provider.push([bundle])
        let pulled = try await provider.pull()

        XCTAssertEqual(pulled.count, 1)
        XCTAssertEqual(pulled.first?.name, "Test Bundle")
    }

    func testInMemorySimulateExternalChange() async throws {
        let provider = InMemorySyncProvider()
        let expectation = XCTestExpectation(description: "onChange called")

        provider.subscribe { bundles in
            XCTAssertEqual(bundles.count, 2)
            expectation.fulfill()
        }

        let bundle1 = MCPBundle(name: "Bundle 1")
        let bundle2 = MCPBundle(name: "Bundle 2")
        provider.simulateExternalChange([bundle1, bundle2])

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testInMemoryReset() async throws {
        let provider = InMemorySyncProvider()
        let bundle = MCPBundle(name: "Test Bundle")
        try await provider.push([bundle])

        provider.reset()
        let pulled = try await provider.pull()

        XCTAssertTrue(pulled.isEmpty)
    }

    func testInMemoryIsAvailable() {
        let provider = InMemorySyncProvider()
        XCTAssertTrue(provider.isAvailable)
    }

    func testInMemoryIsEnabled() {
        let provider = InMemorySyncProvider()
        XCTAssertTrue(provider.isEnabled)

        provider.setEnabled(false)
        XCTAssertFalse(provider.isEnabled)
    }

    // MARK: - ICloudKVSSyncProvider Tests

    func testICloudProviderIsAvailableWhenTokenExists() {
        let store = makeBundleStore()
        let provider = ICloudKVSSyncProvider(bundleStore: store)
        if FileManager.default.ubiquityIdentityToken != nil {
            XCTAssertTrue(provider.isAvailable)
        } else {
            XCTAssertFalse(provider.isAvailable)
        }
    }

    func testICloudProviderPullReturnsEmptyWhenNoData() async throws {
        let store = makeBundleStore()
        let provider = ICloudKVSSyncProvider(bundleStore: store)
        try XCTSkipIf(!provider.isAvailable, "iCloud not available")

        NSUbiquitousKeyValueStore.default.removeObject(forKey: "mcpBundleIndex")
        NSUbiquitousKeyValueStore.default.synchronize()

        let pulled = try await provider.pull()
        XCTAssertTrue(pulled.isEmpty)
    }

    func testICloudProviderPushStoresIndex() async throws {
        let store = makeBundleStore()
        let provider = ICloudKVSSyncProvider(bundleStore: store)
        try XCTSkipIf(!provider.isAvailable, "iCloud not available")

        let bundle = MCPBundle(name: "Push Test")
        try await provider.push([bundle])

        let kvsStore = NSUbiquitousKeyValueStore.default
        XCTAssertNotNil(kvsStore.string(forKey: "mcpBundleIndex"))
    }

    func testICloudProviderSetEnabled() {
        let store = makeBundleStore()
        let provider = ICloudKVSSyncProvider(bundleStore: store)
        guard provider.isAvailable else {
            return
        }

        provider.setEnabled(true)
        XCTAssertTrue(provider.isEnabled)

        provider.setEnabled(false)
        XCTAssertFalse(provider.isEnabled)
    }

    func testICloudProviderSubscribeAndExternalChange() async throws {
        let store = makeBundleStore()
        let provider = ICloudKVSSyncProvider(bundleStore: store)
        guard provider.isAvailable else {
            return
        }

        let expectation = XCTestExpectation(description: "onChange called")
        expectation.assertForOverFulfill = false

        provider.subscribe { bundles in
            expectation.fulfill()
        }

        NSUbiquitousKeyValueStore.default.set("{}", forKey: "mcpBundleIndex")
        NSUbiquitousKeyValueStore.default.synchronize()

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testICloudErrorDescription() {
        let error = ICloudKVSError.iCloudNotAvailable
        XCTAssertEqual(error.errorDescription, "iCloud is not available. Please sign in to iCloud.")
    }

    // MARK: - Helpers

    private func makeBundleStore() -> MCPBundleStore {
        let suiteName = "GreatDeployTests.ICloudKVS.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return MCPBundleStore(userDefaults: userDefaults, fileSystem: MacFileSystem(), startLoading: false)
    }
}
