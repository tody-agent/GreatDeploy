import SwiftUI

struct SyncStatusView: View {
    @State private var isConnected = false
    @State private var isHosting = false
    @State private var tunnelURL: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Sync Status").font(.title2).fontWeight(.bold)
                StatusCard(title: "Connection", icon: "network", statusText: isConnected ? "Connected" : "Disconnected", statusColor: isConnected ? .green : .red, gradientColors: isConnected ? [.green, .blue] : [.red, .orange])
                if isHosting { InfoCard(icon: "link", title: "Tunnel URL", description: tunnelURL.isEmpty ? "Starting..." : tunnelURL) }
                Spacer()
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .textBackgroundColor))
    }
}

struct PassphraseSetupView: View {
    @State private var passphrase = ""
    @State private var confirmPassword = ""
    var body: some View {
        VStack(spacing: 20) {
            Text("Set Vault Passphrase").font(.headline)
            TextField("Passphrase (16 chars)", text: $passphrase).textFieldStyle(.roundedBorder)
            TextField("Confirm", text: $confirmPassword).textFieldStyle(.roundedBorder)
            Button("Continue") {}.buttonStyle(.borderedProminent).disabled(passphrase.count < 16 || passphrase != confirmPassword)
        }.padding().frame(width: 400)
    }
}

struct AccountsListView: View {
    @EnvironmentObject var accountStore: AccountStore
    @State private var isSwitching = false
    @State private var showingAddSheet = false
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Accounts")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button(action: { showingAddSheet = true }) {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if accountStore.accounts.isEmpty {
                    Text("No accounts yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(accountStore.accounts) { account in
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
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture {
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
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $showingAddSheet) {
            AddEditAccountView(mode: .add)
                .environmentObject(accountStore)
        }
    }
}