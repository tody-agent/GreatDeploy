import Foundation
import CloudKit
import Combine
import os.log

/// iCloud Key-Value Store sync provider.
/// Stores bundle index: { bundleId: ISO8601 timestamp }
/// Payload < 1KB, instant sync across devices.
/// Secrets are NOT synced — only bundle metadata.
@MainActor
final class ICloudKVSSyncProvider: DeviceSyncProvider {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "ICloudKVSSync")
    private static let indexKey = "mcpBundleIndex"
    private static let enabledKey = "mcpSyncEnabled"

    let isAvailable: Bool
    var isEnabled: Bool {
        store.bool(forKey: Self.enabledKey)
    }

    private let store: NSUbiquitousKeyValueStore
    private var onChange: (([MCPBundle]) -> Void)?
    private var cancellables: Set<AnyCancellable> = []
    private var bundleStore: MCPBundleStore

    init(bundleStore: MCPBundleStore) {
        self.bundleStore = bundleStore
        self.store = NSUbiquitousKeyValueStore.default

        if let containerURL = FileManager.default.ubiquityIdentityToken {
            self.isAvailable = true
            Self.logger.info("iCloud KVS available")
        } else {
            self.isAvailable = false
            Self.logger.warning("iCloud KVS not available — user not signed in")
        }

        if isAvailable {
            NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                .sink { [weak self] notification in
                    self?.handleExternalChange(notification)
                }
                .store(in: &cancellables)
        }
    }

    func push(_ bundles: [MCPBundle]) async throws {
        guard isAvailable else {
            throw ICloudKVSError.iCloudNotAvailable
        }

        var index: [String: String] = [:]
        for bundle in bundles {
            index[bundle.id.uuidString] = ISO8601DateFormatter().string(from: bundle.updatedAt)
        }

        if let data = try? JSONSerialization.data(withJSONObject: index),
           let jsonString = String(data: data, encoding: .utf8) {
            store.set(jsonString, forKey: Self.indexKey)
            store.synchronize()
            Self.logger.info("Pushed \(bundles.count) bundle(s) to iCloud KVS")
        }
    }

    func pull() async throws -> [MCPBundle] {
        guard isAvailable else {
            throw ICloudKVSError.iCloudNotAvailable
        }

        guard let jsonString = store.string(forKey: Self.indexKey),
              let data = jsonString.data(using: .utf8),
              let index = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return []
        }

        Self.logger.info("Pulled index with \(index.count) bundle(s) from iCloud KVS")

        return []
    }

    func subscribe(onChange: @escaping @Sendable ([MCPBundle]) -> Void) {
        self.onChange = onChange
    }

    func setEnabled(_ enabled: Bool) {
        store.set(enabled, forKey: Self.enabledKey)
        store.synchronize()
    }

    private func handleExternalChange(_ notification: Notification) {
        guard isAvailable, let onChange = onChange else { return }

        Task {
            do {
                let bundles = try await pull()
                onChange(bundles)
            } catch {
                Self.logger.error("Failed to handle external change: \(error.localizedDescription)")
            }
        }
    }
}

enum ICloudKVSError: LocalizedError {
    case iCloudNotAvailable

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable: return "iCloud is not available. Please sign in to iCloud."
        }
    }
}

/// iCloud CloudKit sync provider for larger bundle data.
@MainActor
final class ICloudCloudKitProvider: DeviceSyncProvider {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.greatdeploy.app", category: "ICloudCloudKit")
    private static let recordType = "MCPBundle"
    private static let subscriptionID = "mcp-bundle-changes"
    private static let deviceIDKey = "cloudKitDeviceID"
    private static let syncEnabledKey = "cloudKitSyncEnabled"

    let isAvailable: Bool
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
    }

    private let container: CKContainer
    private let database: CKDatabase
    private var lastPullTimestamp: Date?
    private var onChange: (([MCPBundle]) -> Void)?
    private let bundleStore: MCPBundleStore
    private let deviceID: String

    init(
        bundleStore: MCPBundleStore,
        container: CKContainer = .default()
    ) {
        self.bundleStore = bundleStore
        self.container = container
        self.database = container.privateCloudDatabase

        if let existing = UserDefaults.standard.string(forKey: Self.deviceIDKey) {
            self.deviceID = existing
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: Self.deviceIDKey)
            self.deviceID = newID
        }

        self.isAvailable = FileManager.default.ubiquityIdentityToken != nil

        if isAvailable {
            Self.logger.info("CloudKit available")
            setupSubscription()
        } else {
            Self.logger.warning("CloudKit not available")
        }
    }

    func push(_ bundles: [MCPBundle]) async throws {
        guard isAvailable else {
            throw ICloudCloudKitError.cloudKitNotAvailable
        }

        for bundle in bundles {
            let record = try bundleToRecord(bundle)
            do {
                _ = try await database.save(record)
                Self.logger.info("Pushed bundle: \(bundle.name)")
            } catch let error as CKError where error.code == .serverRecordChanged {
                Self.logger.warning("Conflict pushing bundle: \(bundle.name), attempting merge")
                guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                    throw error
                }
                let mergedRecord = try mergeRecords(local: record, server: serverRecord)
                _ = try await database.save(mergedRecord)
                Self.logger.info("Resolved conflict and pushed bundle: \(bundle.name)")
            } catch {
                Self.logger.error("Failed to push bundle: \(error.localizedDescription)")
                throw error
            }
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

        do {
            let (matchResults, _) = try await database.records(matching: query)

            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    if let bundle = try? recordToBundle(record) {
                        results.append(bundle)
                    }
                case .failure(let error):
                    Self.logger.warning("Failed to fetch record: \(error.localizedDescription)")
                }
            }

            lastPullTimestamp = Date()
            Self.logger.info("Pulled \(results.count) bundle(s) from CloudKit")

        } catch {
            Self.logger.error("CloudKit pull failed: \(error.localizedDescription)")
            throw error
        }

        return results
    }

    func subscribe(onChange: @escaping @Sendable ([MCPBundle]) -> Void) {
        self.onChange = onChange
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
    }

    private func setupSubscription() {
        let predicate = NSPredicate(value: true)

        let subscription = CKQuerySubscription(
            recordType: Self.recordType,
            predicate: predicate,
            subscriptionID: Self.subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        Task {
            do {
                try await database.save(subscription)
                Self.logger.info("CloudKit subscription saved")
            } catch {
                Self.logger.error("Failed to save subscription: \(error.localizedDescription)")
            }
        }
    }

    private func bundleToRecord(_ bundle: MCPBundle) throws -> CKRecord {
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

        try? FileManager.default.removeItem(at: tempURL)

        return record
    }

    private func recordToBundle(_ record: CKRecord) throws -> MCPBundle? {
        guard let asset = record["payload"] as? CKAsset,
              let url = asset.fileURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MCPBundle.self, from: data)
    }

    private func mergeRecords(local: CKRecord, server: CKRecord) throws -> CKRecord {
        let merged = server
        merged["updatedAt"] = local["updatedAt"]
        return merged
    }
}

enum ICloudCloudKitError: LocalizedError {
    case cloudKitNotAvailable

    var errorDescription: String? {
        switch self {
        case .cloudKitNotAvailable:
            return "CloudKit is not available. Please sign in to iCloud."
        }
    }
}
