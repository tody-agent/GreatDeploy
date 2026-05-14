import SwiftUI
import UserNotifications
import ServiceManagement

// MARK: - Main App (macOS Settings Style)

@main
struct GreatDeployApp: App {
    @StateObject private var accountStore = AccountStore()
    @State private var showingAddAccount = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Request notification permissions
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge, .provisional]
            )
        }
    }

    var body: some Scene {
        // Main window — macOS Settings style NavigationSplitView
        // NOTE: Dock icon visibility is managed by AppDelegate via window notifications
        Window("Great Deploy", id: "main") {
            SettingsWindowView()
                .environmentObject(accountStore)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.titleBar)
        .defaultSize(width: 750, height: 520)

        // Menu bar extra
        MenuBarExtra {
            MenuBarContentView(showingAddAccount: $showingAddAccount)
                .environmentObject(accountStore)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            if let activeAccount = accountStore.activeAccount {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "number.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accountStore.profilePairStatus.needsAttention ? .red : .green)

                    if accountStore.profilePairStatus.needsAttention {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                    }
                }

                Text(activeAccount.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "number.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)

                Text("Git Account")
                    .font(.caption)
            }
        }
        .frame(maxWidth: 120)
    }
}

// MARK: - Shared Account Switching Helpers

extension View {
    /// Enhanced account switching with animations and notifications
    @MainActor
    func performAccountSwitch(
        to account: DevProfile,
        accountStore: AccountStore,
        isSwitching: Binding<Bool>,
        showNotification: Bool,
        onError: ((Error) -> Void)? = nil
    ) async {
        guard !account.isActive else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            isSwitching.wrappedValue = true
        }

        defer {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSwitching.wrappedValue = false
            }
        }

        do {
            try await accountStore.switchToAccount(account)

            if showNotification {
                await showSwitchNotification(for: account, cliStatus: accountStore.lastCLISwitchStatus)
            }

            NSApp.dockTile.badgeLabel = nil
        } catch {
            onError?(error)
            NSApp.dockTile.badgeLabel = "!"
        }
    }

    /// Shows notification with account switch info
    @MainActor
    private func showSwitchNotification(
        for account: DevProfile,
        cliStatus: AccountStore.CLISwitchStatus = .none
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "Git Account Switched"
        content.subtitle = "Now using: \(account.displayName)"

        var body = "GitHub: @\(account.githubUsername)\nEmail: \(account.gitUserEmail)"

        if !account.cloudflareAccountId.isEmpty {
            body += "\nCloudflare: \(account.cloudflareAccountId)"
        }

        switch cliStatus {
        case .success:
            body += "\nGitHub CLI: Switched"
        case .accountNotInCLI:
            body += "\nGitHub CLI: Not authenticated (run 'gh auth login')"
        case .notLoggedIn:
            body += "\nGitHub CLI: Not logged in"
        case .failed(let message):
            body += "\nGitHub CLI: Switch failed - \(message)"
        case .notInstalled, .none:
            break
        }

        content.body = body
        content.sound = .default
        content.categoryIdentifier = "ACCOUNT_SWITCH"
        content.userInfo = ["accountId": account.id.uuidString]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Menu Bar Content (Simplified)

struct MenuBarContentView: View {
    @EnvironmentObject var accountStore: AccountStore
    @Binding var showingAddAccount: Bool
    @State private var isSwitching = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        VStack(spacing: 0) {
            // Current account header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT ACCOUNT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)

                    if let active = accountStore.activeAccount {
                        Text(active.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    } else {
                        Text("None")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Circle()
                    .fill(statusDotColor)
                    .frame(width: 10, height: 10)
            }
            .padding()

            Divider()

            if !accountStore.accounts.isEmpty {
                // Quick switch list
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(accountStore.accounts) { account in
                            QuickSwitchRow(
                                account: account,
                                isSwitching: isSwitching
                            ) {
                                await switchToAccount(account)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: min(CGFloat(accountStore.accounts.count) * 40 + 16, 220))

                Divider()
            }

            // Actions bar
            HStack(spacing: 16) {
                Button(action: { showingAddAccount = true }) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { openMainWindow() }) {
                    Label("Settings", systemImage: "gear")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { NSApp.terminate(nil) }) {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(width: 260)
        .sheet(isPresented: $showingAddAccount) {
            AddEditAccountView(mode: .add)
                .environmentObject(accountStore)
        }
    }

    private var statusDotColor: Color {
        if accountStore.profilePairStatus.needsAttention {
            return .red
        }
        return accountStore.activeAccount != nil ? .green : .gray
    }

    private func switchToAccount(_ account: DevProfile) async {
        await performAccountSwitch(
            to: account,
            accountStore: accountStore,
            isSwitching: $isSwitching,
            showNotification: showNotificationOnSwitch,
            onError: nil
        )
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "main" || $0.title == "Great Deploy"
        }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSWindowController.showWindow(_:)), to: nil, from: nil)
        }
    }
}

// MARK: - Quick Switch Row (Menu Bar)

struct QuickSwitchRow: View {
    let account: DevProfile
    let isSwitching: Bool
    let onSwitch: () async -> Void

    var body: some View {
        Button(action: { Task { await onSwitch() } }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(account.isActive ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)

                Text(account.displayName)
                    .font(.system(size: 13, weight: account.isActive ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer()

                if account.isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(account.isActive || isSwitching)
    }
}

// Removed duplicate CLILoginReminderModifier

// MARK: - App Delegate for Dock Icon Control

final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let mainWindowTitle = "Great Deploy"

    /// Controls dock icon visibility dynamically
    /// - Parameter visible: true to show dock icon, false to hide (menu bar only mode)
    static func setDockIconVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            if visible {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Checks if a window is the main app window (not menu bar extra, sheets, or system windows)
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        // Exclude sheets and modal windows
        guard window.sheetParent == nil else { return false }

        // Exclude non-normal level windows (menu bar extras, panels, etc.)
        guard window.level == .normal else { return false }

        // Exclude windows without standard chrome
        guard window.styleMask.contains(.titled) else { return false }

        // Check by exact title match
        if window.title == mainWindowTitle { return true }

        // Check by window identifier patterns
        if let identifier = window.identifier?.rawValue {
            if identifier == "main" ||
               identifier.hasSuffix("-main") ||
               identifier.contains("-main-") ||
               identifier.contains("AppWindow") {
                return true
            }
        }

        // Settings window
        if window.title == "Settings" || window.title.contains("Preferences") {
            return true
        }

        // Bundle identifier prefix match
        if let identifier = window.identifier?.rawValue,
           let bundleId = Bundle.main.bundleIdentifier,
           identifier.hasPrefix(bundleId) {
            return true
        }

        return false
    }

    /// Checks if any main windows are currently visible
    private static func hasVisibleMainWindows() -> Bool {
        let visibleWindows = NSApp.windows.filter { $0.isVisible }
        let mainWindows = visibleWindows.filter { isMainWindow($0) }
        return !mainWindows.isEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as menu bar only (accessory mode)
        NSApp.setActivationPolicy(.accessory)

        // Observe window visibility changes
        let windowNotifications: [(Notification.Name, Selector)] = [
            (NSWindow.didBecomeMainNotification, #selector(windowDidBecomeVisible(_:))),
            (NSWindow.didBecomeKeyNotification, #selector(windowDidBecomeVisible(_:))),
            (NSWindow.willCloseNotification, #selector(windowWillClose(_:))),
            (NSWindow.didMiniaturizeNotification, #selector(windowDidMiniaturize(_:)))
        ]

        for (name, selector) in windowNotifications {
            NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
        }
    }

    @objc private func windowDidBecomeVisible(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              AppDelegate.isMainWindow(window) else { return }

        AppDelegate.setDockIconVisible(true)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              AppDelegate.isMainWindow(window) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !AppDelegate.hasVisibleMainWindows() {
                AppDelegate.setDockIconVisible(false)
            }
        }
    }

    @objc private func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              AppDelegate.isMainWindow(window) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !AppDelegate.hasVisibleMainWindows() {
                AppDelegate.setDockIconVisible(false)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running in menu bar
    }

    /// SECURITY (SEC-02): Clear Cloudflare environment variables on app termination
    /// to prevent tokens from persisting in the GUI session environment after quit.
    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort async cleanup — fire and forget since the app is terminating
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            try? await CloudflareAdapter.shared.clearCredentials()
            semaphore.signal()
        }
        // Wait briefly to allow cleanup to complete
        _ = semaphore.wait(timeout: .now() + 2.0)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppDelegate.setDockIconVisible(true)
        if !flag {
            if let window = NSApp.windows.first(where: { AppDelegate.isMainWindow($0) }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if AppDelegate.hasVisibleMainWindows() {
            AppDelegate.setDockIconVisible(true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
