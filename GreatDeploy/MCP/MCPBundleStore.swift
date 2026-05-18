import Foundation
import SwiftUI
import os.log

/// Observable store for managing MCP bundles.
@MainActor
final class MCPBundleStore: ObservableObject {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "MCPBundleStore")

    // MARK: - Published Properties

    @Published private(set) var bundles: [MCPBundle] = []
    @Published private(set) var syncStates: [MCPClientKind: MCPSyncState] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: Error?

    // MARK: - Storage

    private let userDefaults: UserDefaults
    private let bundlesStorageKey = "mcpBundles"
    private let syncStatesStorageKey = "mcpSyncStates"
    private let fileSystem: FileSystem

    // MARK: - Initialization

    init(
        userDefaults: UserDefaults = .standard,
        fileSystem: FileSystem = MacFileSystem(),
        startLoading: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.fileSystem = fileSystem
        if startLoading {
            loadBundles()
            loadSyncStates()
        }
    }

    // MARK: - Computed Properties

    var activeBundle: MCPBundle? {
        bundles.first { $0.isActive } ?? bundles.first
    }

    var hasBundles: Bool {
        !bundles.isEmpty
    }

    // MARK: - CRUD Operations

    /// Creates a new bundle with the given name.
    func createBundle(name: String, description: String = "") throws -> MCPBundle {
        let bundle = MCPBundle(name: name, bundleDescription: description)
        bundles.append(bundle)
        saveBundles()
        return bundle
    }

    /// Updates an existing bundle.
    func updateBundle(_ bundle: MCPBundle) throws {
        guard let index = bundles.firstIndex(where: { $0.id == bundle.id }) else {
            throw MCPBundleStoreError.bundleNotFound(bundle.id)
        }
        var updated = bundle
        updated.updatedAt = Date()
        bundles[index] = updated
        saveBundles()
    }

    /// Deletes a bundle and cleans up its Keychain secrets.
    func deleteBundle(_ bundle: MCPBundle) throws {
        try? KeychainService.shared.deleteAllMCPSecrets(bundleId: bundle.id)

        bundles.removeAll { $0.id == bundle.id }
        saveBundles()
    }

    /// Adds a server to a bundle.
    func addServer(_ server: MCPServerDefinition, to bundleId: UUID) throws {
        guard let index = bundles.firstIndex(where: { $0.id == bundleId }) else {
            throw MCPBundleStoreError.bundleNotFound(bundleId)
        }
        if bundles[index].servers.contains(where: { $0.name.lowercased() == server.name.lowercased() }) {
            throw MCPBundleStoreError.duplicateServer(server.name)
        }
        bundles[index].servers.append(server)
        bundles[index].updatedAt = Date()
        saveBundles()
    }

    /// Removes a server from a bundle.
    func removeServer(id: UUID, from bundleId: UUID) throws {
        guard let bundleIndex = bundles.firstIndex(where: { $0.id == bundleId }) else {
            throw MCPBundleStoreError.bundleNotFound(bundleId)
        }
        bundles[bundleIndex].servers.removeAll { $0.id == id }
        bundles[bundleIndex].updatedAt = Date()
        saveBundles()
    }

    /// Updates a server within a bundle.
    func updateServer(_ server: MCPServerDefinition, in bundleId: UUID) throws {
        guard let bundleIndex = bundles.firstIndex(where: { $0.id == bundleId }) else {
            throw MCPBundleStoreError.bundleNotFound(bundleId)
        }
        guard let serverIndex = bundles[bundleIndex].servers.firstIndex(where: { $0.id == server.id }) else {
            throw MCPBundleStoreError.serverNotFound(server.id)
        }
        var updated = server
        updated.updatedAt = Date()
        bundles[bundleIndex].servers[serverIndex] = updated
        bundles[bundleIndex].updatedAt = Date()
        saveBundles()
    }

    // MARK: - Multi-Device Sync

    /// Replaces all bundles with merged result from conflict resolution.
    func applyMergedBundles(_ mergedBundles: [MCPBundle]) {
        bundles = mergedBundles
        saveBundles()
    }

    // MARK: - Sync State

    func updateSyncState(_ state: MCPSyncState) {
        syncStates[state.clientId] = state
        saveSyncStates()
    }

    func syncState(for client: MCPClientKind) -> MCPSyncState? {
        syncStates[client]
    }

    // MARK: - Persistence

    private func saveBundles() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(bundles)
            userDefaults.set(data, forKey: bundlesStorageKey)
        } catch {
            lastError = MCPBundleStoreError.saveFailed(error)
            Self.logger.error("Failed to save bundles: \(error)")
        }
    }

    private func loadBundles() {
        guard let data = userDefaults.data(forKey: bundlesStorageKey) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            bundles = try decoder.decode([MCPBundle].self, from: data)
        } catch {
            lastError = MCPBundleStoreError.loadFailed(error)
            Self.logger.error("Failed to load bundles: \(error)")
            bundles = []
        }
    }

    private func saveSyncStates() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(syncStates)
            userDefaults.set(data, forKey: syncStatesStorageKey)
        } catch {
            Self.logger.error("Failed to save sync states: \(error)")
        }
    }

    private func loadSyncStates() {
        guard let data = userDefaults.data(forKey: syncStatesStorageKey) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            syncStates = try decoder.decode([MCPClientKind: MCPSyncState].self, from: data)
        } catch {
            Self.logger.error("Failed to load sync states: \(error)")
            syncStates = [:]
        }
    }

    // MARK: - Error Types

    enum MCPBundleStoreError: LocalizedError {
        case bundleNotFound(UUID)
        case serverNotFound(UUID)
        case duplicateServer(String)
        case saveFailed(Error)
        case loadFailed(Error)

        var errorDescription: String? {
            switch self {
            case .bundleNotFound(let id): return "Bundle not found: \(id.uuidString)"
            case .serverNotFound(let id): return "Server not found: \(id.uuidString)"
            case .duplicateServer(let name): return "Server '\(name)' already exists in bundle"
            case .saveFailed(let error): return "Failed to save: \(error.localizedDescription)"
            case .loadFailed(let error): return "Failed to load: \(error.localizedDescription)"
            }
        }
    }
}
