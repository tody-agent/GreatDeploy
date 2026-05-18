import SwiftUI

struct MCPWizardView: View {
    @State private var currentStep = 0
    @State private var selectedConfig: MCPConfigScope = .none
    @State private var servers: [MCPServerConfig] = []
    @State private var searchText = ""
    @State private var selectedServer: MCPServerConfig?
    @State private var showingAddServer = false
    @State private var newServerName = ""
    @State private var newServerCommand = ""
    @State private var newServerArgs = ""
    @State private var steps: [WizardStepInfo] = [
        WizardStepInfo(title: "Welcome", icon: "hand.wave", isCompleted: true),
        WizardStepInfo(title: "Choose Config", icon: "server.rack", isCompleted: false),
        WizardStepInfo(title: "Manage", icon: "gearshape", isCompleted: false)
    ]

    enum MCPConfigScope { case none, claudeDesktop, project }

    var filteredServers: [MCPServerConfig] { searchText.isEmpty ? servers : servers.filter { $0.name.localizedCaseInsensitiveContains(searchText) } }

    var body: some View {
        VStack(spacing: 0) {
            headerView; Divider()
            WizardContainer(steps: steps, currentStep: $currentStep, onFinish: {}) {
                switch currentStep {
                case 0: welcomeStep
                case 1: chooseConfigStep
                case 2: manageStep
                default: EmptyView()
                }
            }
        }.onAppear(perform: loadData).sheet(isPresented: $showingAddServer) { addServerSheet }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text("MCP Servers").font(.title2).fontWeight(.bold); Text("Manage MCP server configurations").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
            if currentStep == 2 { Button(action: { showingAddServer = true }) { Label("Add Server", systemImage: "plus") }.buttonStyle(.borderedProminent) }
        }.padding()
    }

    private var welcomeStep: some View {
        WizardStepView(icon: "server.rack", title: "MCP Servers", description: "Model Context Protocol") {
            VStack(spacing: 16) {
                InfoCard(icon: "brain", title: "MCP = Kết nối AI với công cụ", description: "MCP cho phép AI kết nối với các dịch vụ bên ngoài như database, API, file system.")
                InfoCard(icon: "globe", title: "Claude Desktop Config", description: "Cấu hình global cho Claude Desktop app.")
                InfoCard(icon: "folder", title: "Project Config (.mcp.json)", description: "Cấu hình per-project cho Claude Code.")
            }
        }
    }

    private var chooseConfigStep: some View {
        WizardStepView(icon: "server.rack", title: "Chọn cấu hình", description: "Quản lý MCP ở đâu?") {
            HStack(spacing: 16) {
                SelectionCard(icon: "desktopcomputer", title: "Claude Desktop", description: "Global config", isSelected: selectedConfig == .claudeDesktop, color: .orange) { selectedConfig = .claudeDesktop; updateStepCompletion() }
                SelectionCard(icon: "folder.badge.gearshape", title: "Project", description: "Per-project config", isSelected: selectedConfig == .project, color: .blue) { selectedConfig = .project; updateStepCompletion() }
            }
        }
    }

    private var manageStep: some View {
        VStack(spacing: 16) {
            if selectedConfig == .claudeDesktop { serversList }
            else if selectedConfig == .project { Text("Project MCP config") }
            else { Text("Vui lòng quay lại chọn cấu hình") }
        }
    }

    private var serversList: some View {
        Group {
            if filteredServers.isEmpty { VStack(spacing: 12) { Image(systemName: "server.rack").font(.system(size: 40)).foregroundStyle(.tertiary); Text("No MCP servers configured").font(.headline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding() }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(filteredServers) { server in serverRow(server); if server.id != filteredServers.last?.id { Divider().padding(.leading, 60) } }.padding(.vertical, 8) } } }
        }
    }

    private func serverRow(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 16) {
            ZStack { RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)).frame(width: 36, height: 36); Image(systemName: "server.rack").font(.system(size: 16)).foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 4) { Text(server.name).font(.subheadline).fontWeight(.medium); Text(server.command).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            Button(action: { deleteServer(server) }) { Image(systemName: "trash").foregroundStyle(.red) }.buttonStyle(.plain)
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var addServerSheet: some View {
        VStack(spacing: 20) {
            Text("Add MCP Server").font(.headline)
            VStack(alignment: .leading, spacing: 8) { Text("Name"); TextField("server-name", text: $newServerName).textFieldStyle(.roundedBorder) }
            VStack(alignment: .leading, spacing: 8) { Text("Command"); TextField("npx", text: $newServerCommand).textFieldStyle(.roundedBorder) }
            VStack(alignment: .leading, spacing: 8) { Text("Args (space-separated)"); TextField("-y @modelcontextprotocol/server", text: $newServerArgs).textFieldStyle(.roundedBorder) }
            HStack {
                Button("Cancel") { showingAddServer = false }.buttonStyle(.bordered)
                Spacer()
                Button("Add") { addServer() }.buttonStyle(.borderedProminent).disabled(newServerName.isEmpty || newServerCommand.isEmpty)
            }
        }.padding().frame(width: 400)
    }

    private func updateStepCompletion() { if currentStep == 1 { steps[1].isCompleted = selectedConfig != .none } }
    private func loadData() { if selectedConfig == .claudeDesktop { servers = (try? MCPConfigService.shared.getMCPServers()) ?? [] } }
    private func addServer() { let server = MCPServerConfig(name: newServerName, command: newServerCommand, args: newServerArgs.split(separator: " ").map(String.init), env: [:]); do { try MCPConfigService.shared.setMCPServer(server); servers.append(server); newServerName = ""; newServerCommand = ""; newServerArgs = ""; showingAddServer = false } catch {} }
    private func deleteServer(_ server: MCPServerConfig) { do { try MCPConfigService.shared.removeMCPServer(named: server.name); servers.removeAll { $0.id == server.id } } catch {} }
}
