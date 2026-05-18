import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject var accountStore: AccountStore
    @Binding var selectedItem: SidebarItem?
    @State private var isSwitching = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if accountStore.accounts.isEmpty {
                    VStack(alignment: .center, spacing: 16) {
                        Image(systemName: "person.3.sequence.fill").font(.system(size: 64)).foregroundStyle(.blue.gradient)
                        Text("Welcome to GreatDeploy").font(.largeTitle).fontWeight(.bold).multilineTextAlignment(.center)
                        Text("Manage and switch Git, Cloudflare profiles at lightning speed.").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button(action: { selectedItem = .addAccount }) { Label("Add new profile", systemImage: "plus.circle.fill").font(.headline).foregroundStyle(.white).padding(.horizontal, 24).padding(.vertical, 14).background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                    }.frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connection Status").font(.headline)
                        HStack(spacing: 16) {
                            StatusCard(title: "GitHub CLI", icon: "terminal", statusText: "Installed", statusColor: .green, gradientColors: [.blue, .purple])
                            StatusCard(title: "Active Profile", icon: "person.crop.circle.fill", statusText: accountStore.activeAccount?.displayName ?? "Not selected", statusColor: accountStore.activeAccount != nil ? .green : .orange, gradientColors: [.green, .blue])
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Actions").font(.headline)
                        HStack(spacing: 16) {
                            QuickActionCard(icon: "arrow.triangle.2.circlepath", title: "Sync", description: "Đồng bộ dữ liệu", color: .blue) { selectedItem = .sync }
                            QuickActionCard(icon: "square.stack.3d.up", title: "Tool Registry", description: "Multi-tool sync", color: .green) { selectedItem = .toolRegistry }
                            QuickActionCard(icon: "sparkles", title: "Skills", description: "Quản lý AI skills", color: .purple) { selectedItem = .skills }
                            QuickActionCard(icon: "server.rack", title: "MCP", description: "Quản lý MCP servers", color: .orange) { selectedItem = .mcp }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Text("Profile List").font(.headline); Spacer(); Button(action: { selectedItem = .addAccount }) { Label("Add Profile", systemImage: "plus").font(.subheadline).fontWeight(.medium) }.buttonStyle(.link) }
                        VStack(spacing: 0) {
                            ForEach(accountStore.accounts) { account in
                                ProfileRowView(account: account, isSwitching: $isSwitching, onSwitch: { if !account.isActive { Task { await performAccountSwitch(to: account, accountStore: accountStore, isSwitching: $isSwitching, showNotification: showNotificationOnSwitch) } } }, onEdit: { selectedItem = .account(account) })
                                if account.id != accountStore.accounts.last?.id { Divider().padding(.leading, 72) }
                            }
                        }.background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Spacer()
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .textBackgroundColor))
    }
}

struct ProfileRowView: View {
    let account: DevProfile; @Binding var isSwitching: Bool; let onSwitch: () -> Void; let onEdit: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            ZStack { Circle().fill(account.isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1)).frame(width: 40, height: 40); Text(String(account.displayName.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(account.isActive ? .green : .secondary) }
            VStack(alignment: .leading, spacing: 4) { HStack(spacing: 8) { Text(account.displayName).font(.headline); if account.isActive { Text("Active").font(.caption2).fontWeight(.bold).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.green).clipShape(Capsule()) } }; Text("@\(account.githubUsername)").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
            HStack(spacing: 16) {
                Button(action: onEdit) { Image(systemName: "pencil.circle").font(.title2).foregroundStyle(.blue) }.buttonStyle(.plain)
                Button(action: onSwitch) { HStack(spacing: 6) { if isSwitching && account.isActive { ProgressView().controlSize(.small) } else { Text(account.isActive ? "Active" : "Switch") } }.frame(minWidth: 80).fontWeight(.medium).padding(.horizontal, 16).padding(.vertical, 8).background(account.isActive ? Color.green.opacity(0.1) : Color.blue.opacity(0.1)).foregroundStyle(account.isActive ? .green : .blue).clipShape(Capsule()) }.buttonStyle(.plain).disabled(account.isActive || isSwitching)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle()).onTapGesture { onSwitch() }
    }
}

struct StatusCard: View {
    let title: String; let icon: String; let statusText: String; let statusColor: Color; let gradientColors: [Color]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { ZStack { Circle().fill(LinearGradient(colors: gradientColors.map { $0.opacity(0.2) }, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 40, height: 40); Image(systemName: icon).font(.system(size: 20)).foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)) }; Spacer() }
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline).foregroundStyle(.secondary); HStack(spacing: 6) { Circle().fill(statusColor).frame(width: 8, height: 8); Text(statusText).font(.headline).foregroundStyle(.primary).lineLimit(1) } }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct QuickActionCard: View {
    let icon: String; let title: String; let description: String; let color: Color; let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 28)).foregroundStyle(color); VStack(spacing: 4) { Text(title).font(.headline); Text(description).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) } }.frame(maxWidth: .infinity).padding(16).background(isHovering ? color.opacity(0.1) : Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
