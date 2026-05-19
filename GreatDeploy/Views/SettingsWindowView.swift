import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case home, skills, mcp, settings
    var id: String {
        switch self {
        case .home: return "home"
        case .skills: return "skills"
        case .mcp: return "mcp"
        case .settings: return "settings"
        }
    }
    var label: String {
        switch self {
        case .home: return "Home"
        case .skills: return "Skills"
        case .mcp: return "MCP"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .skills: return "sparkles"
        case .mcp: return "server.rack"
        case .settings: return "gearshape.fill"
        }
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject var accountStore: AccountStore
    @State private var selectedItem: SidebarItem? = .home
    @State private var isSwitching = false
    @State private var showingWelcome = false
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false

    var body: some View {
        NavigationSplitView { sidebarContent } detail: { detailContent }
            .navigationTitle("GreatDeploy")
            .frame(minWidth: 680, minHeight: 460)
            .sheet(isPresented: $showingWelcome) { WelcomeView().environmentObject(accountStore) }
            .onAppear { if accountStore.accounts.isEmpty { hasCompletedWelcome = false }; if !hasCompletedWelcome { showingWelcome = true } }
    }

    private var sidebarContent: some View {
        List(selection: $selectedItem) {
            Section { Label("Home", systemImage: "house.fill").tag(SidebarItem.home) } header: { Text("DASHBOARD").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
            Section { Label("Skills", systemImage: "sparkles").tag(SidebarItem.skills); Label("MCP", systemImage: "server.rack").tag(SidebarItem.mcp) } header: { Text("GLOBAL").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
            Section { Label("Settings", systemImage: "gearshape.fill").tag(SidebarItem.settings) } header: { Text("SYSTEM").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary) }
        }.listStyle(.sidebar)
    }

    @ViewBuilder private var detailContent: some View {
        switch selectedItem {
        case .home, .none: HomeDashboardView().environmentObject(accountStore)
        case .skills: SkillsListView()
        case .mcp: MCPListView()
        case .settings: SettingsView()
        }
    }
}
