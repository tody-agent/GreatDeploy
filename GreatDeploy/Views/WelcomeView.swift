import SwiftUI

// MARK: - Welcome View for First Launch

struct WelcomeView: View {
    @EnvironmentObject var accountStore: AccountStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false

    @State private var discoveredCredential: (username: String, token: String)?
    @State private var isDiscovering = false
    @State private var isWaitingForAuth = false
    @State private var discoveryError: String?
    @State private var showingImportConfirmation = false
    @State private var isImporting = false
    @State private var authMethod: KeychainService.AuthMethod = .none

    var body: some View {
        VStack(spacing: 0) {
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    if isWaitingForAuth {
                        authPromptView
                    } else if isDiscovering {
                        discoveringView
                    } else if let credential = discoveredCredential {
                        credentialFoundView(credential)
                    } else {
                        noCredentialView
                    }
                }
                .padding(30)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            // Footer actions
            footerActions
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 480, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            // Check available auth method
            authMethod = KeychainService.shared.availableAuthMethod()
            isWaitingForAuth = true
        }
    }

    // MARK: - Auth Prompt View

    private var authPromptView: some View {
        VStack(spacing: 24) {
            // Animated logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.2), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)

                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Welcome to Great Deploy")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Manage and switch Git, Cloudflare profiles at lightning speed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                stepRow(icon: "1.circle.fill", title: "Authenticate", description: "Grant Keychain access for the app to verify.")
                stepRow(icon: "2.circle.fill", title: "Scan Token", description: "The system automatically searches for existing GitHub Tokens.")
                stepRow(icon: "3.circle.fill", title: "Start", description: "Import token and get ready to use Great Deploy.")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            // Authenticate button
            Button(action: { startCredentialDiscovery() }) {
                HStack(spacing: 8) {
                    Image(systemName: authIconName)
                        .font(.system(size: 16))
                    Text("Authenticate with \(authMethod.displayName)")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Text("This is only used to read GitHub credentials from Keychain")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func stepRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24, alignment: .center)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var authIconName: String {
        switch authMethod {
        case .touchID:
            return "touchid"
        case .faceID:
            return "faceid"
        case .opticID:
            return "opticid"
        case .password:
            return "lock.fill"
        case .none:
            return "lock.slash.fill"
        }
    }

    private var authDescription: String {
        switch authMethod {
        case .touchID:
            return "Use Touch ID to securely access your Keychain credentials"
        case .faceID:
            return "Use Face ID to securely access your Keychain credentials"
        case .opticID:
            return "Use Optic ID to securely access your Keychain credentials"
        case .password:
            return "Enter your Mac password to access Keychain credentials"
        case .none:
            return "Authentication is not available on this device"
        }
    }

    // MARK: - Discovering View

    private var discoveringView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Reading GitHub credentials...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Credential Found View

    private func credentialFoundView(_ credential: (username: String, token: String)) -> some View {
        VStack(spacing: 20) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Existing Credential Found!")
                .font(.headline)

            // Credential card
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                    Text("GitHub Username")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("@\(credential.username)")
                        .fontWeight(.medium)
                }

                Divider()

                HStack {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                    Text("Access Token")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(maskToken(credential.token))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )

            Text("Would you like to import this credential into the app?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Import button
            Button(action: { showingImportConfirmation = true }) {
                HStack {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(isImporting ? "Importing..." : "Import Credential")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isImporting)
            .confirmationDialog("Import Credential", isPresented: $showingImportConfirmation) {
                Button("Import as New Account") {
                    importCredential(credential)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will create a new account using the GitHub credential from your Keychain.")
            }
        }
    }

    // MARK: - No Credential View

    private var noCredentialView: some View {
        VStack(spacing: 20) {
            if let error = discoveryError {
                // Error state
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Keychain Access Issue")
                    .font(.headline)

                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("You can still add accounts manually.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                // No credentials found
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("No Existing Credentials Found")
                    .font(.headline)

                Text("No GitHub credentials were found in your Keychain.\nYou can add your first account to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Features list
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "arrow.triangle.2.circlepath", text: "Switch accounts instantly")
                featureRow(icon: "key.fill", text: "Secure Keychain storage")
                featureRow(icon: "terminal", text: "Auto-update git config")
                featureRow(icon: "bell.fill", text: "Switch notifications")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.05))
            )
        }
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

    // MARK: - Footer Actions

    private var footerActions: some View {
        HStack {
            Button("Skip") {
                completeWelcome()
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(action: { completeWelcome() }) {
                Text("Get Started")
                    .frame(width: 100)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    /// Starts the credential discovery process with biometric authentication
    private func startCredentialDiscovery() {
        isWaitingForAuth = false
        isDiscovering = true

        Task {
            do {
                // Use biometric-protected credential access
                let credential = try await KeychainService.shared.readGitHubCredentialWithAuth(
                    reason: "Access GitHub credentials stored in Keychain"
                )

                await MainActor.run {
                    discoveredCredential = credential
                    isDiscovering = false
                }
            } catch KeychainService.KeychainError.biometricAuthFailed(let message) {
                await MainActor.run {
                    // User cancelled or auth failed - show appropriate message
                    if message.contains("cancel") || message.contains("Cancel") {
                        discoveryError = "Authentication was cancelled. You can still add accounts manually."
                    } else {
                        discoveryError = "Authentication failed: \(message)"
                    }
                    isDiscovering = false
                }
            } catch KeychainService.KeychainError.unexpectedStatus(let status) {
                await MainActor.run {
                    if status == -25293 { // errSecAuthFailed
                        discoveryError = "Keychain access was denied."
                    } else {
                        discoveryError = "Unable to access Keychain (error: \(status))"
                    }
                    isDiscovering = false
                }
            } catch {
                await MainActor.run {
                    // No credential found is not an error
                    discoveredCredential = nil
                    isDiscovering = false
                }
            }
        }
    }

    private func importCredential(_ credential: (username: String, token: String)) {
        isImporting = true

        Task {
            defer {
                Task { @MainActor in
                    isImporting = false
                }
            }

            // Get current git config for name/email
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
                await MainActor.run {
                    completeWelcome()
                }
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

    private func maskToken(_ token: String) -> String {
        guard token.count > 8 else { return "••••••••" }
        let prefix = String(token.prefix(4))
        let suffix = String(token.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }
}

// MARK: - Preview

#Preview("Welcome - Discovering") {
    WelcomeView()
        .environmentObject(AccountStore())
}
