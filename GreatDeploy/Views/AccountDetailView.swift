import SwiftUI

// MARK: - Account Detail View (macOS Settings Style)

/// Displays account details in the detail pane with inline editing,
/// modeled after macOS System Settings > Users & Groups
struct AccountDetailView: View {
    @EnvironmentObject var accountStore: AccountStore
    let account: DevProfile

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isSwitching = false
    @State private var switchError: Error?
    @State private var showingError = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Account header
                accountHeader
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                Divider()
                    .padding(.horizontal, 20)

                // Detail sections
                VStack(spacing: 0) {
                    githubSection
                    cloudflareSection
                    gitConfigSection
                    actionsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingEditSheet) {
            AddEditAccountView(mode: .edit(account))
                .environmentObject(accountStore)
        }
        .confirmationDialog(
            "Delete \(account.displayName)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                withAnimation {
                    try? accountStore.removeAccount(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the account and its credentials from Keychain. This action cannot be undone.")
        }
        .alert("Switch Failed", isPresented: $showingError, presenting: switchError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    // MARK: - Account Header

    private var accountHeader: some View {
        HStack(spacing: 16) {
            // Large avatar (like Users & Groups)
            ZStack {
                Circle()
                    .fill(
                        account.isActive
                            ? Color.green.opacity(0.12)
                            : Color.secondary.opacity(0.08)
                    )
                    .frame(width: 64, height: 64)

                Text(String(account.displayName.prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(account.isActive ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 6) {
                    if account.isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("Inactive")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                if !account.isActive {
                    Button("Switch to This Account") {
                        Task {
                            await switchToAccount()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isSwitching)
                }

                Button(action: { showingEditSheet = true }) {
                    Text("Edit…")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - GitHub Section

    private var githubSection: some View {
        SettingsSection(title: "GitHub") {
            SettingsRow(label: "Username", value: "@\(account.githubUsername)")
            SettingsRow(label: "Personal Access Token", value: "••••••••••••", isSecure: true)
        }
    }

    // MARK: - Cloudflare Section

    @ViewBuilder
    private var cloudflareSection: some View {
        if !account.cloudflareAccountId.isEmpty {
            SettingsSection(title: "Cloudflare") {
                SettingsRow(label: "Account ID", value: account.cloudflareAccountId)
                SettingsRow(label: "API Token", value: "••••••••••••", isSecure: true)
            }
        }
    }

    // MARK: - Git Config Section

    private var gitConfigSection: some View {
        SettingsSection(title: "Git Config") {
            SettingsRow(label: "user.name", value: account.gitUserName)
            SettingsRow(label: "user.email", value: account.gitUserEmail)

            if let lastUsed = account.lastUsedAt {
                SettingsRow(
                    label: "Last used",
                    value: lastUsed.formatted(.relative(presentation: .named))
                )
            }

            SettingsRow(
                label: "Created",
                value: account.createdAt.formatted(date: .abbreviated, time: .shortened)
            )
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.vertical, 12)

            HStack {
                Button("Delete Account…", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)

                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Switch Action

    private func switchToAccount() async {
        await performAccountSwitch(
            to: account,
            accountStore: accountStore,
            isSwitching: $isSwitching,
            showNotification: showNotificationOnSwitch
        ) { error in
            switchError = error
            showingError = true
        }
    }
}

// MARK: - Reusable Settings Section (macOS-native grouped look)

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Reusable Settings Row

struct SettingsRow: View {
    let label: String
    let value: String
    var isSecure: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)

            if isSecure {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        Divider()
            .padding(.leading, 156)
    }
}

// MARK: - Preview

#Preview("Active Account") {
    AccountDetailView(account: .preview)
        .environmentObject(AccountStore())
        .frame(width: 500, height: 600)
}

#Preview("Inactive Account") {
    AccountDetailView(account: .previewWork)
        .environmentObject(AccountStore())
        .frame(width: 500, height: 600)
}
