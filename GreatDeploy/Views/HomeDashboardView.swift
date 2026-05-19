import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject var accountStore: AccountStore
    @State private var isSwitching = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                if accountStore.accounts.isEmpty {
                    emptyStateView
                } else {
                    statusSection
                    quickSwitchSection
                    quickActionsSection
                }
            }
            .padding(30)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
            HStack(spacing: 16) {
                StatusCard(
                    title: "Active Profile",
                    icon: "person.crop.circle.fill",
                    statusText: accountStore.activeAccount?.displayName ?? "None",
                    statusColor: accountStore.activeAccount != nil ? .green : .orange,
                    gradientColors: [.green, .blue]
                )
                StatusCard(
                    title: "GitHub CLI",
                    icon: "terminal",
                    statusText: GitHubCLIService.shared.isInstalled ? "Installed" : "Not installed",
                    statusColor: GitHubCLIService.shared.isInstalled ? .green : .orange,
                    gradientColors: [.blue, .purple]
                )
                StatusCard(
                    title: "Accounts",
                    icon: "person.2.fill",
                    statusText: "\(accountStore.accounts.count)",
                    statusColor: .blue,
                    gradientColors: [.blue, .cyan]
                )
            }
        }
    }

    private var quickSwitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Profiles")
                    .font(.headline)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(accountStore.accounts) { account in
                    ProfileRowView(
                        account: account,
                        isSwitching: $isSwitching,
                        onSwitch: {
                            if !account.isActive {
                                Task {
                                    await performAccountSwitch(
                                        to: account,
                                        accountStore: accountStore,
                                        isSwitching: $isSwitching,
                                        showNotification: showNotificationOnSwitch
                                    )
                                }
                            }
                        }
                    )
                    if account.id != accountStore.accounts.last?.id {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            HStack(spacing: 16) {
                QuickActionCard(
                    icon: "person.badge.plus",
                    title: "Add Profile",
                    description: "New account",
                    color: .blue
                ) {
                    // Add profile action
                }
                QuickActionCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Sync",
                    description: "Sync skills & MCP",
                    color: .green
                ) {
                    // Sync action
                }
                QuickActionCard(
                    icon: "sparkles",
                    title: "Skills",
                    description: "Manage AI skills",
                    color: .purple
                ) {
                    // Skills action
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.15), .purple.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(spacing: 8) {
                Text("Welcome to GreatDeploy")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Manage GitHub accounts, Cloudflare, and AI skills in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                featureRow(icon: "arrow.triangle.2.circlepath", text: "One-click profile switching")
                featureRow(icon: "key.fill", text: "Secure Keychain storage")
                featureRow(icon: "terminal", text: "Auto-update git config")
                featureRow(icon: "sparkles", text: "Global AI skills across tools")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct ProfileRowView: View {
    let account: DevProfile
    @Binding var isSwitching: Bool
    let onSwitch: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(account.isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)
                Text(String(account.displayName.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(account.isActive ? .green : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(account.displayName)
                        .font(.headline)
                    if account.isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }
                Text("@\(account.githubUsername)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                if isSwitching && !account.isActive {
                    ProgressView()
                        .controlSize(.small)
                } else if !account.isActive {
                    Button(action: onSwitch) {
                        Text("Switch")
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

struct StatusCard: View {
    let title: String
    let icon: String
    let statusText: String
    let statusColor: Color
    let gradientColors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: gradientColors.map { $0.opacity(0.2) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(isHovering ? color.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}