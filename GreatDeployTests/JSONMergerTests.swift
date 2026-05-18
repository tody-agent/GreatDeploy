import XCTest
@testable import GreatDeploy

final class JSONMergerTests: XCTestCase {

    // MARK: - Helpers

    private func makeServer(name: String, command: String? = nil) -> MCPServerDefinition {
        MCPServerDefinition(
            name: name,
            transport: .stdio,
            command: command ?? "node",
            args: ["server.js"]
        )
    }

    // MARK: - Basic merge tests

    func testEmptyExistingWithThreeBundleServers() {
        let bundle = [
            makeServer(name: "server-a"),
            makeServer(name: "server-b"),
            makeServer(name: "server-c")
        ]

        let result = JSONMerger.merge(
            existingServers: [:],
            bundleServers: bundle,
            previouslySyncedNames: []
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.keys.contains("server-a"))
        XCTAssertTrue(result.keys.contains("server-b"))
        XCTAssertTrue(result.keys.contains("server-c"))
    }

    func testEmptyExistingAndEmptyBundle() {
        let result = JSONMerger.merge(
            existingServers: [:],
            bundleServers: [],
            previouslySyncedNames: []
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testTwoExistingThreeBundleNoOverlap() {
        let existing: [String: MCPServerDefinition] = [
            "user-a": makeServer(name: "user-a"),
            "user-b": makeServer(name: "user-b")
        ]
        let bundle = [
            makeServer(name: "bundle-x"),
            makeServer(name: "bundle-y"),
            makeServer(name: "bundle-z")
        ]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: []
        )

        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.keys.contains("user-a"))
        XCTAssertTrue(result.keys.contains("user-b"))
        XCTAssertTrue(result.keys.contains("bundle-x"))
        XCTAssertTrue(result.keys.contains("bundle-y"))
        XCTAssertTrue(result.keys.contains("bundle-z"))
    }

    // MARK: - User-added preservation

    func testUserAddedServersPreservedWithBundle() {
        let existing: [String: MCPServerDefinition] = [
            "user-a": makeServer(name: "user-a"),
            "user-b": makeServer(name: "user-b")
        ]
        let bundle = [
            makeServer(name: "bundle-x"),
            makeServer(name: "bundle-y"),
            makeServer(name: "bundle-z")
        ]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: ["bundle-x", "bundle-y", "bundle-z"]
        )

        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.keys.contains("user-a"), "User-added server must be preserved")
        XCTAssertTrue(result.keys.contains("user-b"), "User-added server must be preserved")
    }

    func testUserAddedServerWithSameNameAsBundleOverwritten() {
        let userServer = makeServer(name: "collision", command: "user-cmd")
        let bundleServer = makeServer(name: "collision", command: "bundle-cmd")

        let existing: [String: MCPServerDefinition] = ["collision": userServer]
        let bundle = [bundleServer]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: []
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["collision"]?.command, "bundle-cmd", "Bundle should overwrite on name collision")
    }

    // MARK: - Orphan removal

    func testOrphanRemovedWhenNoLongerInBundle() {
        let existing: [String: MCPServerDefinition] = [
            "server-a": makeServer(name: "server-a"),
            "server-b": makeServer(name: "server-b"),
            "server-c": makeServer(name: "server-c")
        ]
        let bundle = [
            makeServer(name: "server-a"),
            makeServer(name: "server-b")
        ]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: ["server-a", "server-b", "server-c"]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.keys.contains("server-a"))
        XCTAssertTrue(result.keys.contains("server-b"))
        XCTAssertFalse(result.keys.contains("server-c"), "Orphan server-c must be removed")
    }

    func testUserAddedServerNotRemovedEvenIfOrphanPattern() {
        let existing: [String: MCPServerDefinition] = [
            "user-server": makeServer(name: "user-server"),
            "managed-server": makeServer(name: "managed-server")
        ]
        let bundle = [
            makeServer(name: "managed-server")
        ]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: ["managed-server"]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.keys.contains("user-server"), "User-added server must NOT be removed")
        XCTAssertTrue(result.keys.contains("managed-server"))
    }

    // MARK: - Case-insensitive matching

    func testCaseInsensitiveNameCollision() {
        let existingServer = makeServer(name: "MyServer", command: "old-cmd")
        let bundleServer = makeServer(name: "myserver", command: "new-cmd")

        let existing: [String: MCPServerDefinition] = ["MyServer": existingServer]
        let bundle = [bundleServer]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: []
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.keys.contains("myserver"))
        XCTAssertEqual(result["myserver"]?.command, "new-cmd", "Bundle should overwrite case-insensitively")
    }

    func testCaseInsensitiveOrphanDetection() {
        let existingServer = makeServer(name: "myserver")
        let existing: [String: MCPServerDefinition] = ["myserver": existingServer]

        let orphans = JSONMerger.orphanNames(
            existingServers: existing,
            bundleServers: [],
            previouslySyncedNames: ["MyServer"]
        )

        XCTAssertTrue(orphans.contains("myserver"), "Case-insensitive orphan detection must match")
    }

    // MARK: - Edge cases

    func testAllSyncedNoneInBundle() {
        let existing: [String: MCPServerDefinition] = [
            "server-a": makeServer(name: "server-a"),
            "server-b": makeServer(name: "server-b"),
            "server-c": makeServer(name: "server-c")
        ]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: [],
            previouslySyncedNames: ["server-a", "server-b", "server-c"]
        )

        XCTAssertTrue(result.isEmpty, "All synced servers should be removed when bundle is empty")
    }

    func testEmptyPreviouslySyncedPreservesAll() {
        let existing: [String: MCPServerDefinition] = [
            "existing-a": makeServer(name: "existing-a"),
            "existing-b": makeServer(name: "existing-b")
        ]
        let bundle = [
            makeServer(name: "bundle-x")
        ]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: []
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.keys.contains("existing-a"))
        XCTAssertTrue(result.keys.contains("existing-b"))
        XCTAssertTrue(result.keys.contains("bundle-x"))
    }

    func testDuplicateNamesInBundleLastWins() {
        let server1 = makeServer(name: "dup", command: "cmd-1")
        let server2 = makeServer(name: "dup", command: "cmd-2")

        let bundle = [server1, server2]

        let result = JSONMerger.merge(
            existingServers: [:],
            bundleServers: bundle,
            previouslySyncedNames: []
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["dup"]?.command, "cmd-2", "Last duplicate in bundle should win")
    }

    // MARK: - orphanNames tests

    func testOrphanNamesReturnsCorrectOrphans() {
        let existing: [String: MCPServerDefinition] = [
            "server-a": makeServer(name: "server-a"),
            "server-b": makeServer(name: "server-b"),
            "server-c": makeServer(name: "server-c")
        ]
        let bundle = [
            makeServer(name: "server-a"),
            makeServer(name: "server-b")
        ]

        let orphans = JSONMerger.orphanNames(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: ["server-a", "server-b", "server-c"]
        )

        XCTAssertEqual(orphans.count, 1)
        XCTAssertTrue(orphans.contains("server-c"))
    }

    func testOrphanNamesEmptyWhenNoOrphans() {
        let existing: [String: MCPServerDefinition] = [
            "server-a": makeServer(name: "server-a"),
            "server-b": makeServer(name: "server-b")
        ]
        let bundle = [
            makeServer(name: "server-a"),
            makeServer(name: "server-b")
        ]

        let orphans = JSONMerger.orphanNames(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: ["server-a", "server-b"]
        )

        XCTAssertTrue(orphans.isEmpty, "No orphans when all synced servers are still in bundle")
    }

    // MARK: - userAddedNames tests

    func testUserAddedNamesReturnsCorrectSet() {
        let existing: [String: MCPServerDefinition] = [
            "user-a": makeServer(name: "user-a"),
            "user-b": makeServer(name: "user-b"),
            "managed-x": makeServer(name: "managed-x")
        ]

        let userAdded = JSONMerger.userAddedNames(
            existingServers: existing,
            previouslySyncedNames: ["managed-x"]
        )

        XCTAssertEqual(userAdded.count, 2)
        XCTAssertTrue(userAdded.contains("user-a"))
        XCTAssertTrue(userAdded.contains("user-b"))
        XCTAssertFalse(userAdded.contains("managed-x"))
    }

    func testUserAddedNamesEmptyWhenAllManaged() {
        let existing: [String: MCPServerDefinition] = [
            "managed-a": makeServer(name: "managed-a"),
            "managed-b": makeServer(name: "managed-b")
        ]

        let userAdded = JSONMerger.userAddedNames(
            existingServers: existing,
            previouslySyncedNames: ["managed-a", "managed-b"]
        )

        XCTAssertTrue(userAdded.isEmpty, "No user-added servers when all are managed")
    }

    // MARK: - Additional edge cases

    func testMergeWithMixedCasePreviouslySynced() {
        let existing: [String: MCPServerDefinition] = [
            "MyServer": makeServer(name: "MyServer"),
            "AnotherServer": makeServer(name: "AnotherServer")
        ]
        let bundle = [
            makeServer(name: "myserver")
        ]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: ["MYSERVER"]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.keys.contains("myserver"), "Bundle server added with lowercase key")
        XCTAssertTrue(result.keys.contains("AnotherServer"), "Unmanaged server preserved")
        XCTAssertFalse(result.keys.contains("MyServer"), "Case-insensitive match removed MyServer")
    }

    func testOrphanNamesWithMixedCase() {
        let existing: [String: MCPServerDefinition] = [
            "MyServer": makeServer(name: "MyServer"),
            "OtherServer": makeServer(name: "OtherServer")
        ]
        let bundle: [MCPServerDefinition] = []

        let orphans = JSONMerger.orphanNames(
            existingServers: existing,
            bundleServers: bundle,
            previouslySyncedNames: ["myserver"]
        )

        XCTAssertEqual(orphans.count, 1)
        XCTAssertTrue(orphans.contains("MyServer"), "Case-insensitive orphan must be detected")
        XCTAssertFalse(orphans.contains("OtherServer"), "Unmanaged server must not be orphan")
    }

    func testUserAddedNamesWithMixedCase() {
        let existing: [String: MCPServerDefinition] = [
            "MyServer": makeServer(name: "MyServer"),
            "UserServer": makeServer(name: "UserServer")
        ]

        let userAdded = JSONMerger.userAddedNames(
            existingServers: existing,
            previouslySyncedNames: ["myserver"]
        )

        XCTAssertEqual(userAdded.count, 1)
        XCTAssertTrue(userAdded.contains("UserServer"))
        XCTAssertFalse(userAdded.contains("MyServer"), "Case-insensitive match excludes managed server")
    }

    func testMergePreservesOriginalKeyForUserServers() {
        let userServer = makeServer(name: "UserServer")
        let existing: [String: MCPServerDefinition] = ["UserServer": userServer]

        let result = JSONMerger.merge(
            existingServers: existing,
            bundleServers: [],
            previouslySyncedNames: []
        )

        XCTAssertTrue(result.keys.contains("UserServer"), "Original key casing preserved for user servers")
    }

    func testMergeBundleServerUsesLowercaseKey() {
        let bundleServer = makeServer(name: "BundleServer")
        let bundle = [bundleServer]

        let result = JSONMerger.merge(
            existingServers: [:],
            bundleServers: bundle,
            previouslySyncedNames: []
        )

        XCTAssertTrue(result.keys.contains("bundleserver"), "Bundle servers stored with lowercase keys")
    }
}
