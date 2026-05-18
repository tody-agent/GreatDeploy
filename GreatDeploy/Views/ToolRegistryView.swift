import SwiftUI

struct ToolRegistryView: View {
    @State private var discoveryResults: [ToolDiscoveryService.DiscoveryResult] = []
    @State private var masterSkills: [RegisteredSkill] = []
    @State private var masterMCPServers: [RegisteredMCPServer] = []
    @State private var isSyncing = false
    @State private var selectedTab: RegistryTab = .skills
    @State private var showingImportSheet = false
    @State private var importTool: AITool?

    enum RegistryTab: String, CaseIterable { case skills = "Skills"; case mcp = "MCP Servers" }

    private let discovery = ToolDiscoveryService.shared
    private let skillRegistry = SkillRegistry.shared
    private let mcpRegistry = MCPRegistry.shared
    private let syncService = ToolSyncService.shared
    private let mcpSyncService = MCPSyncService.shared

    var installedTools: [ToolDiscoveryService.DiscoveryResult] { discoveryResults.filter { $0.isInstalled } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tool Registry").font(.title2).fontWeight(.bold)
                    Text("Manage skills & MCP across all AI tools").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: syncAllTools) {
                    HStack(spacing: 6) { if isSyncing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.triangle.2.circlepath") }; Text("Sync All") }
                }.buttonStyle(.borderedProminent).disabled(isSyncing)
            }.padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    toolsSection
                    Divider()
                    Picker("Tab", selection: $selectedTab) { ForEach(RegistryTab.allCases, id: \.self) { tab in Text(tab.rawValue).tag(tab) } }.pickerStyle(.segmented)
                    switch selectedTab {
                    case .skills: masterSkillsSection
                    case .mcp: masterMCPServersSection
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.onAppear(perform: loadData)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Tools").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)], spacing: 12) {
                ForEach(installedTools, id: \.tool.id) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: result.tool.iconName).font(.system(size: 16)).foregroundStyle(.blue)
                            Text(result.tool.displayName).font(.subheadline).fontWeight(.medium)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 14))
                        }
                        if result.tool.supportsSkills {
                            let synced = masterSkills.filter { $0.syncStatus(for: result.tool) == .synced }.count
                            HStack(spacing: 8) { Text("\(synced)/\(masterSkills.count) synced").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.padding(12).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var masterSkillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Master Skills (\(masterSkills.count))").font(.headline); Spacer() }
            if masterSkills.isEmpty {
                VStack(spacing: 12) { Image(systemName: "sparkles").font(.system(size: 32)).foregroundStyle(.tertiary); Text("No skills in master registry").font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(masterSkills) { skill in
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(.purple).frame(width: 36, height: 36).background(Color.purple.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) { Text(skill.name).font(.subheadline).fontWeight(.medium); Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                            HStack(spacing: 8) { ForEach(installedTools.map { $0.tool }.filter { $0.supportsSkills }, id: \.id) { tool in ToolSyncBadge(tool: tool, status: skill.syncStatus(for: tool)) } }
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                        if skill.id != masterSkills.last?.id { Divider().padding(.leading, 52) }
                    }
                }.background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var masterMCPServersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Master MCP Servers (\(masterMCPServers.count))").font(.headline); Spacer() }
            if masterMCPServers.isEmpty {
                VStack(spacing: 12) { Image(systemName: "server.rack").font(.system(size: 32)).foregroundStyle(.tertiary); Text("No MCP servers in master registry").font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(masterMCPServers) { server in
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack").font(.system(size: 14)).foregroundStyle(.orange).frame(width: 36, height: 36).background(Color.orange.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) { Text(server.name).font(.subheadline).fontWeight(.medium); Text(server.config.command).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                            HStack(spacing: 8) { ForEach(installedTools.map { $0.tool }.filter { $0.supportsMCP }, id: \.id) { tool in ToolSyncBadge(tool: tool, status: server.syncStatus(for: tool)) } }
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                        if server.id != masterMCPServers.last?.id { Divider().padding(.leading, 52) }
                    }
                }.background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    struct ToolSyncBadge: View {
        let tool: AITool; let status: SyncStatus
        var statusColor: Color { switch status { case .synced: return .green; case .pending: return .orange; case .conflict, .error: return .red; default: return .gray } }
        var body: some View {
            HStack(spacing: 3) { Image(systemName: tool.iconName).font(.system(size: 9)).foregroundStyle(statusColor); Image(systemName: status.systemImage).font(.system(size: 8)).foregroundStyle(statusColor) }.help("\(tool.displayName): \(status.displayLabel)")
        }
    }

    private func loadData() {
        discoveryResults = discovery.discoverInstalledTools()
        masterSkills = (try? skillRegistry.listMasterSkills()) ?? []
        masterMCPServers = (try? mcpRegistry.listMasterServers()) ?? []
    }

    private func syncAllTools() {
        isSyncing = true
        Task.detached {
            _ = syncService.syncAllSkillsToAllTools()
            _ = mcpSyncService.syncAllServersToAllTools()
            await MainActor.run { isSyncing = false; loadData() }
        }
    }
}
