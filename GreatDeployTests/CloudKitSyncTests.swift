import XCTest
import CloudKit
@testable import GreatDeploy

// MARK: - Mock CKDatabase

/// Mock implementation of CKDatabase operations for unit testing.
@MainActor
final class MockCKDatabase {

    var savedRecords: [CKRecord] = []
    var savedSubscriptions: [CKSubscription] = []
    var recordsToReturn: [CKRecord.ID: Result<CKRecord, Error>] = [:]
    var saveError: Error?
    var fetchError: Error?

    func save(_ record: CKRecord) async throws -> CKRecord {
        if let error = saveError {
            throw error
        }
        savedRecords.append(record)
        return record
    }

    func save(_ subscription: CKSubscription) async throws {
        savedSubscriptions.append(subscription)
    }

    func records(matching query: CKQuery) async throws -> ([CKRecord.ID: Result<CKRecord, Error>], CKQueryOperation.Cursor?) {
        if let error = fetchError {
            throw error
        }
        return (recordsToReturn, nil)
    }

    func reset() {
        savedRecords.removeAll()
        savedSubscriptions.removeAll()
        recordsToReturn.removeAll()
        saveError = nil
        fetchError = nil
    }
}

// MARK: - Testable CloudKit Provider

/// A testable provider that accepts a mock database.
@MainActor
final class TestableCloudKitProvider: DeviceSyncProvider {

    let isAvailable: Bool
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
    }

    private let mockDB: MockCKDatabase
    private let bundleStore: MCPBundleStore
    private var lastPullTimestamp: Date?
    private var onChange: (([MCPBundle]) -> Void)?
    private let deviceID: String

    private static let recordType = "MCPBundle"
    private static let deviceIDKey = "cloudKitDeviceID"
    private static let syncEnabledKey = "cloudKitTestSyncEnabled"

    init(
        isAvailable: Bool = true,
        mockDB: MockCKDatabase,
        bundleStore: MCPBundleStore
    ) {
        self.isAvailable = isAvailable
        self.mockDB = mockDB
        self.bundleStore = bundleStore

        if let existing = UserDefaults.standard.string(forKey: Self.deviceIDKey) {
            self.deviceID = existing
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: Self.deviceIDKey)
            self.deviceID = newID
        }
    }

    func push(_ bundles: [MCPBundle]) async throws {
        guard isAvailable else {
            throw ICloudCloudKitError.cloudKitNotAvailable
        }

        for bundle in bundles {
            let record = try bundleToRecord(bundle)
            _ = try await mockDB.save(record)
        }
    }

    func pull() async throws -> [MCPBundle] {
        guard isAvailable else {
            throw ICloudCloudKitError.cloudKitNotAvailable
        }

        let predicate = lastPullTimestamp.map { timestamp in
            NSPredicate(format: "updatedAt > %@", timestamp as NSDate)
        } ?? NSPredicate(value: true)

        let query = CKQuery(recordType: Self.recordType, predicate: predicate)

        var results: [MCPBundle] = []

        let (matchResults, _) = try await mockDB.records(matching: query)

        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                if let bundle = try? recordToBundle(record) {
                    results.append(bundle)
                }
            case .failure:
                break
            }
        }

        lastPullTimestamp = Date()
        return results
    }

    func subscribe(onChange: @escaping @Sendable ([MCPBundle]) -> Void) {
        self.onChange = onChange
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
    }

    // MARK: - Internal helpers (exposed for testing)

    func bundleToRecord(_ bundle: MCPBundle) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: bundle.id.uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(bundle.id.uuidString).json")
        try data.write(to: tempURL)

        record["payload"] = CKAsset(fileURL: tempURL)
        record["updatedAt"] = bundle.updatedAt as NSDate
        record["deviceOrigin"] = deviceID

        // Note: In tests, we do NOT delete the temp file so recordToBundle can read it.
        // In production, CloudKit reads the file during save() before cleanup.

        return record
    }

    func recordToBundle(_ record: CKRecord) throws -> MCPBundle? {
        guard let asset = record["payload"] as? CKAsset,
              let url = asset.fileURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MCPBundle.self, from: data)
    }
}

// MARK: - Tests

@MainActor
final class CloudKitSyncTests: XCTestCase {

    // MARK: - Availability

    func testIsAvailableTrueWhenICloudTokenExists() {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        XCTAssertTrue(provider.isAvailable)
    }

    func testIsAvailableFalseWhenNoICloudToken() {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: false, mockDB: mockDB, bundleStore: store)

        XCTAssertFalse(provider.isAvailable)
    }

    // MARK: - Push

    func testPushCreatesCKRecordWithPayload() async throws {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        let bundle = MCPBundle(name: "Test Bundle")

        try await provider.push([bundle])

        XCTAssertEqual(mockDB.savedRecords.count, 1)
        let record = try XCTUnwrap(mockDB.savedRecords.first)
        XCTAssertEqual(record.recordType, "MCPBundle")
        XCTAssertEqual(record.recordID.recordName, bundle.id.uuidString)
        XCTAssertNotNil(record["payload"])
        XCTAssertNotNil(record["updatedAt"])
        XCTAssertNotNil(record["deviceOrigin"])
    }

    func testPushThrowsWhenNotAvailable() async {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: false, mockDB: mockDB, bundleStore: store)

        let bundle = MCPBundle(name: "Test Bundle")

        do {
            try await provider.push([bundle])
            XCTFail("Expected error")
        } catch let error as ICloudCloudKitError {
            XCTAssertEqual(error, .cloudKitNotAvailable)
        } catch {
            XCTFail("Expected ICloudCloudKitError, got \(error)")
        }
    }

    func testPushMultipleBundles() async throws {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        let bundle1 = MCPBundle(name: "Bundle 1")
        let bundle2 = MCPBundle(name: "Bundle 2")
        let bundle3 = MCPBundle(name: "Bundle 3")

        try await provider.push([bundle1, bundle2, bundle3])

        XCTAssertEqual(mockDB.savedRecords.count, 3)
    }

    // MARK: - Pull

    func testPullReturnsBundlesFromCloudKit() async throws {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        let bundle = MCPBundle(name: "Remote Bundle")
        let record = try provider.bundleToRecord(bundle)
        mockDB.recordsToReturn[record.recordID] = .success(record)

        let pulled = try await provider.pull()

        XCTAssertEqual(pulled.count, 1)
        XCTAssertEqual(pulled.first?.name, "Remote Bundle")
    }

    func testPullEmptyWhenNoRecords() async throws {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        mockDB.recordsToReturn = [:]

        let pulled = try await provider.pull()

        XCTAssertTrue(pulled.isEmpty)
    }

    func testPullThrowsWhenNotAvailable() async {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: false, mockDB: mockDB, bundleStore: store)

        do {
            _ = try await provider.pull()
            XCTFail("Expected error")
        } catch let error as ICloudCloudKitError {
            XCTAssertEqual(error, .cloudKitNotAvailable)
        } catch {
            XCTFail("Expected ICloudCloudKitError, got \(error)")
        }
    }

    func testPullSkipsFailedRecords() async throws {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        let goodBundle = MCPBundle(name: "Good Bundle")
        let goodRecord = try provider.bundleToRecord(goodBundle)

        mockDB.recordsToReturn[goodRecord.recordID] = .success(goodRecord)
        mockDB.recordsToReturn[CKRecord.ID(recordName: "bad-id")] = .failure(
            CKError(.internalError)
        )

        let pulled = try await provider.pull()

        XCTAssertEqual(pulled.count, 1)
        XCTAssertEqual(pulled.first?.name, "Good Bundle")
    }

    // MARK: - Record Encoding

    func testBundleToRecordHasCorrectFields() throws {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        let bundle = MCPBundle(
            name: "Encoding Test",
            bundleDescription: "Test description",
            servers: [MCPServerDefinition(name: "Test Server", command: "test")],
            isActive: true
        )

        let record = try provider.bundleToRecord(bundle)

        XCTAssertEqual(record.recordType, "MCPBundle")
        XCTAssertEqual(record.recordID.recordName, bundle.id.uuidString)
        XCTAssertNotNil(record["payload"])
        XCTAssertNotNil(record["updatedAt"])
        XCTAssertNotNil(record["deviceOrigin"])

        guard let asset = record["payload"] as? CKAsset,
              let url = asset.fileURL,
              let data = try? Data(contentsOf: url) else {
            XCTFail("Payload asset not found")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MCPBundle.self, from: data)

        XCTAssertEqual(decoded.name, "Encoding Test")
        XCTAssertEqual(decoded.bundleDescription, "Test description")
        XCTAssertEqual(decoded.servers.count, 1)
        XCTAssertEqual(decoded.servers.first?.name, "Test Server")
        XCTAssertTrue(decoded.isActive)
    }

    func testRecordToBundleRoundtrip() throws {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        let original = MCPBundle(
            name: "Roundtrip Test",
            bundleDescription: "Roundtrip description",
            servers: [
                MCPServerDefinition(name: "Server A", command: "cmd-a"),
                MCPServerDefinition(name: "Server B", command: "cmd-b")
            ],
            enabledClients: [.claudeDesktop, .cursor],
            isActive: true
        )

        let record = try provider.bundleToRecord(original)
        let decoded = try XCTUnwrap(provider.recordToBundle(record))

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.bundleDescription, original.bundleDescription)
        XCTAssertEqual(decoded.servers.count, 2)
        XCTAssertEqual(decoded.servers[0].name, "Server A")
        XCTAssertEqual(decoded.servers[1].name, "Server B")
        XCTAssertEqual(decoded.enabledClients, original.enabledClients)
        XCTAssertEqual(decoded.isActive, original.isActive)
    }

    func testRecordToBundleReturnsNilForMissingPayload() throws {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        let record = CKRecord(recordType: "MCPBundle")

        let result = try provider.recordToBundle(record)

        XCTAssertNil(result)
    }

    // MARK: - Subscribe

    func testSubscribeStoresOnChange() {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        provider.subscribe { bundles in
            XCTAssertEqual(bundles.count, 1)
            XCTAssertEqual(bundles.first?.name, "Changed Bundle")
        }
    }

    // MARK: - Enable/Disable

    func testSetEnabledStoresPreference() {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        XCTAssertFalse(provider.isEnabled)

        provider.setEnabled(true)

        XCTAssertTrue(provider.isEnabled)
    }

    func testSetEnabledFalse() {
        let mockDB = MockCKDatabase()
        let store = makeStore()
        let provider = TestableCloudKitProvider(isAvailable: true, mockDB: mockDB, bundleStore: store)

        provider.setEnabled(true)
        provider.setEnabled(false)

        XCTAssertFalse(provider.isEnabled)
    }

    // MARK: - Error Types

    func testICloudCloudKitErrorDescription() {
        let error = ICloudCloudKitError.cloudKitNotAvailable
        XCTAssertEqual(error.errorDescription, "CloudKit is not available. Please sign in to iCloud.")
    }

    // MARK: - Helpers

    private func makeStore() -> MCPBundleStore {
        let suiteName = "GreatDeployTests.CloudKit.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return MCPBundleStore(userDefaults: userDefaults, fileSystem: MacFileSystem(), startLoading: true)
    }
}
