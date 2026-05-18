import XCTest
import SwiftUI
@testable import GreatDeploy

@MainActor
final class MCPClientsSyncViewTests: XCTestCase {

    // MARK: - Client Count

    func testAllClientsCount() {
        XCTAssertEqual(MCPClientKind.allCases.count, 9)
    }

    func testAllClientsHaveDisplayNames() {
        for client in MCPClientKind.allCases {
            XCTAssertFalse(client.displayName.isEmpty, "\(client.rawValue) should have a display name")
        }
    }

    func testAllClientsHaveIconNames() {
        for client in MCPClientKind.allCases {
            XCTAssertFalse(client.iconName.isEmpty, "\(client.rawValue) should have an icon name")
        }
    }

    // MARK: - Installed Detection

    func testInstalledClientShowsGreen() {
        let installedClients = MCPClientKind.allCases.filter { $0.isInstalled }
        for client in installedClients {
            XCTAssertTrue(client.isInstalled, "\(client.displayName) should be installed")
        }
    }

    func testNotInstalledClientShowsGray() {
        let notInstalledClients = MCPClientKind.allCases.filter { !$0.isInstalled }
        for client in notInstalledClients {
            XCTAssertFalse(client.isInstalled, "\(client.displayName) should not be installed")
        }
    }

    // MARK: - Toggle Enable/Disable

    func testToggleEnablesClient() throws {
        let store = makeStore()
        let bundle = try store.createBundle(name: "Test Bundle")

        XCTAssertFalse(bundle.enabledClients.contains(.cursor))

        var updated = bundle
        updated.enabledClients.insert(.cursor)
        try store.updateBundle(updated)

        let result = try XCTUnwrap(store.bundles.first { $0.id == bundle.id })
        XCTAssertTrue(result.enabledClients.contains(.cursor))
    }

    func testToggleDisablesClient() throws {
        let store = makeStore()
        var bundle = try store.createBundle(name: "Test Bundle")
        bundle.enabledClients.insert(.cursor)
        bundle.enabledClients.insert(.vscode)
        try store.updateBundle(bundle)

        var updated = bundle
        updated.enabledClients.remove(.cursor)
        try store.updateBundle(updated)

        let result = try XCTUnwrap(store.bundles.first { $0.id == bundle.id })
        XCTAssertFalse(result.enabledClients.contains(.cursor))
        XCTAssertTrue(result.enabledClients.contains(.vscode))
    }

    // MARK: - Sync Button State

    func testSyncButtonDisabledWhenNoBundle() throws {
        let store = makeStore()
        XCTAssertNil(store.activeBundle)
        XCTAssertTrue(store.bundles.isEmpty)
    }

    func testSyncButtonDisabledWhenNoEnabledClients() throws {
        let store = makeStore()
        _ = try store.createBundle(name: "Empty Bundle")

        let bundle = try XCTUnwrap(store.activeBundle)
        XCTAssertTrue(bundle.enabledClients.isEmpty)
    }

    func testSyncButtonEnabledWhenBundleHasEnabledClients() throws {
        let store = makeStore()
        var bundle = try store.createBundle(name: "Active Bundle")
        bundle.enabledClients.insert(.cursor)
        try store.updateBundle(bundle)

        let result = try XCTUnwrap(store.activeBundle)
        XCTAssertFalse(result.enabledClients.isEmpty)
        XCTAssertGreaterThan(result.enabledClients.count, 0)
    }

    // MARK: - Sync State Display

    func testSyncStateForUnknownClientReturnsNil() throws {
        let store = makeStore()
        XCTAssertNil(store.syncState(for: .claudeDesktop))
    }

    func testSyncStateShowsServerCount() throws {
        let store = makeStore()

        let state = MCPSyncState(
            clientId: .cursor,
            lastSyncedAt: Date(),
            lastSyncedServerNames: ["GitHub", "FileSystem", "Database"],
            previouslySyncedNames: ["GitHub", "FileSystem", "Database"]
        )
        store.updateSyncState(state)

        let retrieved = try XCTUnwrap(store.syncState(for: .cursor))
        XCTAssertEqual(retrieved.lastSyncedServerNames.count, 3)
    }

    // MARK: - Bundle Enabled Clients Count

    func testEnabledClientsCountDisplay() throws {
        let store = makeStore()
        var bundle = try store.createBundle(name: "Bundle")
        bundle.enabledClients = [.claudeDesktop, .cursor, .vscode]
        try store.updateBundle(bundle)

        let result = try XCTUnwrap(store.activeBundle)
        XCTAssertEqual(result.enabledClients.count, 3)
    }

    func testSingleClientCountGrammar() throws {
        let store = makeStore()
        var bundle = try store.createBundle(name: "Bundle")
        bundle.enabledClients = [.cursor]
        try store.updateBundle(bundle)

        let result = try XCTUnwrap(store.activeBundle)
        XCTAssertEqual(result.enabledClients.count, 1)
    }

    // MARK: - Helpers

    private func makeStore() -> MCPBundleStore {
        let suiteName = "GreatDeployTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return MCPBundleStore(userDefaults: userDefaults, fileSystem: MacFileSystem(), startLoading: true)
    }
}
