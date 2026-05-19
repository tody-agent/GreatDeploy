import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var accountStore: AccountStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false

    @State private var discoveredCredential: (username: String, token: String)?
    @State private var isDiscovering = false
    @State private var discoveryError: String?
    @State private var showingImportConfirmation = false
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    if let credential = discoveredCredential {
                        credentialFoundView(credential)
                    } else {
                        mainContentView
                    }
                }
                .padding(30)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            footerActions
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 480, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear { startAutoDiscovery() }
    }

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.green.opacity(0.2), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
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
        }
    }

    private var mainContentView: some View {
        VStack(spacing: 20) {
            if isDiscovering {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Looking for existing credentials...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error = discoveryError {
                errorView(error)
            } else {
                featuresList
            }
        }
    }

    private func credentialFoundView(_ credential: (username: String, token: String)) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Existing Credential Found")
                .font(.headline)

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                    Text("GitHub @\(credential.username)")
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.3), lineWidth: 1))
            )

            Button(action: { showingImportConfirmation = true }) {
                HStack {
                    if isImporting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(isImporting ? "Importing..." : "Import & Get Started")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isImporting)
            .confirmationDialog("Import Credential", isPresented: $showingImportConfirmation) {
                Button("Import as New Account") { importCredential(credential) }
                Button("Skip", role: .cancel) { completeWelcome() }
            } message: {
                Text("This will create a new account using the GitHub credential from your Keychain.")
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Keychain Access Issue")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            featuresList
        }
    }

    private var featuresList: some View {
        VStack(spacing: 12) {
            featureRow(icon: "arrow.triangle.2.circlepath", text: "One-click profile switching")
            featureRow(icon: "key.fill", text: "Secure Keychain storage")
            featureRow(icon: "terminal", text: "Auto-update git config")
            featureRow(icon: "sparkles", text: "Global AI skills across tools")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.05))
        )
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

    private var footerActions: some View {
        HStack {
            Button("Skip") { completeWelcome() }
                .buttonStyle(.borderless)

            Spacer()

            Button(action: { completeWelcome() }) {
                Text("Get Started")
                    .frame(width: 100)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func startAutoDiscovery() {
        isDiscovering = true

        Task {
            do {
                let credential = try await KeychainService.shared.readGitHubCredentialWithAuth(
                    reason: "Access GitHub credentials stored in Keychain"
                )

                await MainActor.run {
                    discoveredCredential = credential
                    isDiscovering = false
                }
            } catch {
                await MainActor.run {
                    if let keychainError = error as? KeychainService.KeychainError {
                        switch keychainError {
                        case .biometricAuthFailed(let message):
                            if message.lowercased().contains("cancel") {
                                discoveryError = "Authentication was cancelled. You can still add accounts manually."
                            } else {
                                discoveryError = "Authentication failed: \(message)"
                            }
                        default:
                            discoveryError = nil
                        }
                    }
                    isDiscovering = false
                }
            }
        }
    }

    private func importCredential(_ credential: (username: String, token: String)) {
        isImporting = true

        Task {
            defer {
                Task { @MainActor in isImporting = false }
            }

            let gitConfig = try? await GitConfigService.shared.getCurrentConfigAsync()

            let account = DevProfile(
                displayName: credential.username,
                githubUsername: credential.username,
                personalAccessToken: credential.token,
                gitUserName: gitConfig?.name ?? credential.username,
                gitUserEmail: gitConfig?.email ?? "\(credential.username)@users.noreply.github.com",
                cloudflareAccountId: "",
                cloudflareApiToken: "",
                isActive: true
            )

            do {
                try accountStore.addAccount(account)
                await MainActor.run { completeWelcome() }
            } catch {
                await MainActor.run {
                    discoveryError = "Failed to import: \(error.localizedDescription)"
                }
            }
        }
    }

    private func completeWelcome() {
        hasCompletedWelcome = true
        dismiss()
    }
}