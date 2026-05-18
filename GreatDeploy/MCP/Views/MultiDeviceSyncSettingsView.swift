import SwiftUI

struct MultiDeviceSyncSettingsView: View {
    @EnvironmentObject var bundleStore: MCPBundleStore
    @State private var kvsProvider: ICloudKVSSyncProvider?
    @State private var cloudKitProvider: ICloudCloudKitProvider?
    @State private var isSyncing = false
    @State private var lastSyncInfo = "Never synced"
    @State private var showingResetConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Multi-Device Sync") {
                Toggle("Enable Multi-Device Sync", isOn: Binding(
                    get: { kvsProvider?.isEnabled ?? false },
                    set: { kvsProvider?.setEnabled($0) }
                ))

                if let kvs = kvsProvider, kvs.isAvailable {
                    Label("iCloud Connected", systemImage: "icloud.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("iCloud Not Available", systemImage: "icloud.slash")
                        .foregroundStyle(.red)
                    Text("Sign in to iCloud to enable multi-device sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Status") {
                LabeledContent("Last Sync", value: lastSyncInfo)
                LabeledContent("Bundles", value: "\(bundleStore.bundles.count)")
            }

            Section("Actions") {
                Button(action: { Task { await forceSync() } }) {
                    Label("Force Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(kvsProvider?.isAvailable == false || isSyncing)

                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset and Re-pull from iCloud", systemImage: "trash")
                }
                .disabled(kvsProvider?.isAvailable == false)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Multi-Device Sync")
        .task {
            kvsProvider = ICloudKVSSyncProvider(bundleStore: bundleStore)
            cloudKitProvider = ICloudCloudKitProvider(bundleStore: bundleStore)
        }
        .alert("Reset Sync", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                Task { await resetAndRepull() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear local sync state and re-pull all bundles from iCloud. Continue?")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func forceSync() async {
        guard let kvs = kvsProvider, kvs.isAvailable else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await kvs.push(bundleStore.bundles)
            lastSyncInfo = "Last sync: just now"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetAndRepull() async {
        guard let kvs = kvsProvider, kvs.isAvailable else { return }

        do {
            let bundles = try await kvs.pull()
            let result = ConflictResolver.merge(local: bundleStore.bundles, remote: bundles)
            bundleStore.applyMergedBundles(result.mergedBundles)
            lastSyncInfo = "Last sync: reset and repulled"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
