import Foundation

/// In-memory sync provider for testing.
@MainActor
final class InMemorySyncProvider: DeviceSyncProvider {

    var isAvailable: Bool = true
    var isEnabled: Bool = true
    private var storedBundles: [MCPBundle] = []
    private var onChange: (([MCPBundle]) -> Void)?

    func push(_ bundles: [MCPBundle]) async throws {
        storedBundles = bundles
    }

    func pull() async throws -> [MCPBundle] {
        storedBundles
    }

    func subscribe(onChange: @escaping @Sendable ([MCPBundle]) -> Void) {
        self.onChange = onChange
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func simulateExternalChange(_ bundles: [MCPBundle]) {
        storedBundles = bundles
        onChange?(bundles)
    }

    func reset() {
        storedBundles = []
    }
}
