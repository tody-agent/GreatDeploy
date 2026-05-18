import Foundation

/// Protocol for multi-device sync providers.
@MainActor
protocol DeviceSyncProvider: AnyObject {
    /// Push all bundles to the cloud.
    func push(_ bundles: [MCPBundle]) async throws

    /// Pull all bundles from the cloud.
    func pull() async throws -> [MCPBundle]

    /// Subscribe to changes from other devices.
    func subscribe(onChange: @escaping @Sendable ([MCPBundle]) -> Void)

    /// Whether sync is currently enabled/available.
    var isAvailable: Bool { get }

    /// Whether multi-device sync is enabled by user.
    var isEnabled: Bool { get }

    /// Enable/disable multi-device sync.
    func setEnabled(_ enabled: Bool)
}
