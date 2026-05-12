import SwiftUI

// MARK: - Sidebar Navigation Items

/// Represents a selectable item in the sidebar
enum SidebarItem: Hashable, Identifiable {
    case home
    case account(DevProfile)
    case addAccount
    case about

    var id: String {
        switch self {
        case .home: return "home"
        case .account(let profile): return "account-\(profile.id.uuidString)"
        case .addAccount: return "add-account"
        case .about: return "about"
        }
    }
}

// MARK: - Main Settings Window (macOS System Settings Style)

struct SettingsWindowView: View {
    @EnvironmentObject var accountStore: AccountStore
    @State private var selectedItem: SidebarItem? = .home
    @State private var isSwitching = false
    @State private var showingWelcome = false
    @State private var showingCLISetup = false
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("hasCompletedCLISetup") private var hasCompletedCLISetup = false
    @AppStorage("skipCLISetup") private var skipCLISetup = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationTitle("Great Deploy")
        .frame(minWidth: 680, minHeight: 460)
        .frame(idealWidth: 750, idealHeight: 520)
        .sheet(isPresented: $showingWelcome) {
            WelcomeView()
                .environmentObject(accountStore)
        }
        .sheet(isPresented: $showingCLISetup) {
            GitHubCLISetupView()
        }
        .onAppear {
            if accountStore.accounts.isEmpty {
                hasCompletedWelcome = false
            }
            if !hasCompletedWelcome {
                showingWelcome = true
            }
        }
        .onChange(of: accountStore.accounts.isEmpty) { isEmpty in
            if isEmpty {
                hasCompletedWelcome = false
                showingWelcome = true
            }
        }
        .onChange(of: selectedItem) { newValue in
            if case .account(let profile) = newValue {
                if !profile.isActive {
                    Task {
                        await performAccountSwitch(
                            to: profile,
                            accountStore: accountStore,
                            isSwitching: $isSwitching,
                            showNotification: showNotificationOnSwitch
                        )
                    }
                }
            }
        }
        .onChange(of: showingWelcome) { newValue in
            if !newValue && hasCompletedWelcome && !hasCompletedCLISetup && !skipCLISetup {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingCLISetup = true
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedItem) {
            Label("Home", systemImage: "house")
                .tag(SidebarItem.home)
                
            Label("Settings", systemImage: "gearshape")
                .tag(SidebarItem.about)
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailContent: some View {
        switch selectedItem {
        case .home:
            HomeDashboardView(selectedItem: $selectedItem)
                .environmentObject(accountStore)

        case .account(let profile):
            if let liveAccount = accountStore.accounts.first(where: { $0.id == profile.id }) {
                AccountDetailView(account: liveAccount)
                    .environmentObject(accountStore)
                    .id(liveAccount.id) // Force refresh when account changes
            } else {
                noSelectionView
            }

        case .about:
            AboutSettingsDetailView()
            
        case .addAccount:
            AddEditAccountView(mode: .add)
                .environmentObject(accountStore)

        case .none:
            noSelectionView
        }
    }

    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Select an account or setting")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers
}

// MARK: - Sidebar Account Row

struct SidebarAccountRow: View {
    let account: DevProfile

    var body: some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(account.isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 32, height: 32)

                Text(String(account.displayName.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(account.isActive ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName)
                    .font(.system(size: 13, weight: account.isActive ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Text("@\(account.githubUsername)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if account.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    SettingsWindowView()
        .environmentObject(AccountStore())
}
