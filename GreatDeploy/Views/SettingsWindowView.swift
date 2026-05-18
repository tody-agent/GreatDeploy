import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case home, accounts, account(DevProfile), addAccount, sync, toolRegistry, skills, mcp, settings, about
    var id: String {
        switch self {
        case .home: return "home"
        case .accounts: return "accounts"
        case .account(let p): return "account-\(p.id.uuidString)"
        case .addAccount: return "add-account"
        case .sync: return "sync"
        case .toolRegistry: return "tool-registry"
        case .skills: return "skills"
        case .mcp: return "mcp"
        case .settings: return "settings"
        case .about: return "about"
        }
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject var accountStore: AccountStore
    @State private var selectedItem: SidebarItem? = .home
    @State private var isSwitching = false
    @State private var showingWelcome = false
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        NavigationSplitView { sidebarContent } detail: { detailContent }
            .navigationTitle("Great Deploy").frame(minWidth: 680, minHeight: 460)
            .sheet(isPresented: $showingWelcome) { WelcomeView().environmentObject(accountStore) }
            .onAppear { if accountStore.accounts.isEmpty { hasCompletedWelcome = false }; if !hasCompletedWelcome { showingWelcome = true } }
            .onChange(of: selectedItem) { newValue in if case .account(let p) = newValue, !p.isActive { Task { await performAccountSwitch(to: p, accountStore: accountStore, isSwitching: $isSwitching, showNotification: showNotificationOnSwitch) } } }
    }

    private var sidebarContent: some View {
        List(selection: $selectedItem) {
            Section { Label("Home", systemImage: "house").tag(SidebarItem.home); Label("Accounts", systemImage: "person.2.fill").tag(SidebarItem.accounts) } header: { Text("MAIN").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
            Section { Label("Sync", systemImage: "arrow.triangle.2.circlepath").tag(SidebarItem.sync); Label("Tool Registry", systemImage: "square.stack.3d.up").tag(SidebarItem.toolRegistry); Label("Skills", systemImage: "sparkles").tag(SidebarItem.skills); Label("MCP Servers", systemImage: "server.rack").tag(SidebarItem.mcp) } header: { Text("SYNC").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
            Section { Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings); Label("About", systemImage: "info.circle").tag(SidebarItem.about) } header: { Text("SYSTEM").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
        }.listStyle(.sidebar)
    }

    @ViewBuilder private var detailContent: some View {
        switch selectedItem {
        case .home, .none: HomeDashboardView(selectedItem: $selectedItem).environmentObject(accountStore)
        case .accounts: AccountsListView(selectedItem: $selectedItem).environmentObject(accountStore)
        case .account(let p): if let a = accountStore.accounts.first(where: { $0.id == p.id }) { AccountDetailView(account: a).environmentObject(accountStore).id(a.id) } else { noSelectionView }
        case .addAccount: AddEditAccountView(mode: .add).environmentObject(accountStore)
        case .sync: SyncWizardView()
        case .toolRegistry: ToolRegistryView()
        case .skills: SkillsWizardView()
        case .mcp: MCPWizardView()
        case .settings: AppSettingsView()
        case .about: AboutSettingsDetailView()
        }
    }

    private var noSelectionView: some View { VStack(spacing: 16) { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 48)).foregroundStyle(.tertiary); Text("Select an account").font(.title3).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
}
