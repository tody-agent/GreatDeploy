import SwiftUI

/// View for adding or editing a GitHub account
struct AddEditAccountView: View {

    enum Mode: Identifiable {
        case add
        case edit(DevProfile)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let account): return account.id.uuidString
            }
        }

        var title: String {
            switch self {
            case .add: return "Add Account"
            case .edit: return "Edit Account"
            }
        }

        var buttonTitle: String {
            switch self {
            case .add: return "Add"
            case .edit: return "Save"
            }
        }

        var account: DevProfile? {
            switch self {
            case .add: return nil
            case .edit(let account): return account
            }
        }
    }

    // MARK: - Validation Error

    enum ValidationError: LocalizedError {
        case invalidCharacters(String)
        case inputTooLong(String)
        case invalidEmail
        case invalidGitHubUsername
        case invalidToken

        var errorDescription: String? {
            switch self {
            case .invalidCharacters(let field):
                return "\(field) contains invalid control characters"
            case .inputTooLong(let field):
                return "\(field) exceeds maximum length"
            case .invalidEmail:
                return "Invalid email format"
            case .invalidGitHubUsername:
                return "Invalid GitHub username format (alphanumeric, hyphens only, max 39 chars, or valid email)"
            case .invalidToken:
                return "Invalid Personal Access Token format"
            }
        }
    }

    @EnvironmentObject var accountStore: AccountStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    // Form fields
    @State private var displayName = ""
    @State private var githubUsername = ""
    @State private var personalAccessToken = ""
    @State private var gitUserName = ""
    @State private var gitUserEmail = ""
    @State private var cloudflareAccountId = ""
    @State private var cloudflareApiToken = ""

    // State
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var showingError = false
    @State private var showingTokenHelp = false
    @State private var originalToken = "" // Track original token for edit mode
    @State private var originalCloudflareToken = ""
    @State private var showingCLIReminder = false
    @State private var savedAccountName = ""

    // CLI auth validation
    @State private var cliAuthStatus: CLIAuthCheckStatus = .unchecked
    @State private var cliCheckTask: Task<Void, Never>?

    enum CLIAuthCheckStatus: Equatable {
        case unchecked
        case checking
        case authenticated
        case notAuthenticated
        case cliNotAvailable
    }

    // MARK: - Token Validation Helper

    /// Checks if token is valid, considering edit mode where unchanged tokens are accepted
    private var isTokenValidForSave: Bool {
        let trimmedToken = personalAccessToken.trimmingCharacters(in: .whitespaces)

        // In edit mode, accept unchanged non-empty token without format validation
        if case .edit = mode, trimmedToken == originalToken, !trimmedToken.isEmpty {
            return true
        }

        // Otherwise, validate token format
        return isValidGitHubToken(trimmedToken)
    }

    // MARK: - Form Validation

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !githubUsername.trimmingCharacters(in: .whitespaces).isEmpty &&
        isTokenValidForSave &&
        !gitUserName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !gitUserEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(gitUserEmail.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Form
            Form {
                displaySection
                credentialsSection
                cloudflareSection
                gitConfigSection
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            actionsView
        }
        .frame(width: 460, height: 700)
        .onAppear(perform: loadExistingAccount)
        .onDisappear {
            // Cancel any in-flight CLI check
            cliCheckTask?.cancel()
            // SECURITY: Securely zero token from memory when view closes
            ValidationUtilities.secureZeroString(&personalAccessToken)
            ValidationUtilities.secureZeroString(&cloudflareApiToken)
        }
        .alert("Error", isPresented: $showingError, presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .sheet(isPresented: $showingTokenHelp) {
            TokenHelpView()
        }
        .cliLoginReminder(isPresented: $showingCLIReminder, accountName: savedAccountName)
        .onChange(of: showingCLIReminder) { newValue in
            // Dismiss the view after CLI reminder alert is closed
            if !newValue && !savedAccountName.isEmpty {
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(mode.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Form Sections

    private var displaySection: some View {
        Section {
            TextField("Display Name", text: $displayName)
                .textFieldStyle(.roundedBorder)
        } header: {
            Text("Display")
        } footer: {
            Text("A friendly name to identify this account (e.g., \"Personal\", \"Work\")")
        }
    }

    private var credentialsSection: some View {
        Section {
            TextField("GitHub Username", text: $githubUsername)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: githubUsername) { newValue in
                    cliCheckTask?.cancel()
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, ValidationUtilities.isValidGitHubUsername(trimmed) else {
                        cliAuthStatus = .unchecked
                        return
                    }
                    cliCheckTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        await checkCLIAuthStatus(for: trimmed)
                    }
                }

            // CLI auth status indicator
            if cliAuthStatus != .unchecked {
                HStack(spacing: 6) {
                    switch cliAuthStatus {
                    case .checking:
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Checking GitHub CLI...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .authenticated:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Authenticated in GitHub CLI")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .notAuthenticated:
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Not in GitHub CLI — run 'gh auth login' for CLI switching")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    case .cliNotAvailable:
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("GitHub CLI not available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .unchecked:
                        EmptyView()
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }

            HStack {
                SecureField("Personal Access Token", text: $personalAccessToken)
                    .textFieldStyle(.roundedBorder)

                Button(action: { showingTokenHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("How to create a Personal Access Token")
            }
        } header: {
            Text("GitHub Credentials")
        } footer: {
            Text("Your GitHub username and Personal Access Token (PAT)")
        }
    }

    private var cloudflareSection: some View {
        Section {
            HStack {
                TextField("Account ID", text: $cloudflareAccountId)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .help("Found in the right sidebar of your Cloudflare Dashboard overview page.")
            }

            HStack {
                SecureField("API Token", text: $cloudflareApiToken)
                    .textFieldStyle(.roundedBorder)
                
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .help("Requires 'Workers Scripts: Edit' and 'Workers Tail: Read' permissions to deploy applications.")
            }
        } header: {
            Text("Cloudflare Credentials")
        } footer: {
            Text("Optional. Needed if you want to deploy Cloudflare Workers or Pages from this profile.")
        }
    }

    private var gitConfigSection: some View {
        Section {
            HStack {
                TextField("Author Name", text: $gitUserName)
                    .textFieldStyle(.roundedBorder)
                
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .help("The name that will appear on your Git commits (e.g., John Doe).")
            }

            HStack {
                TextField("Author Email", text: $gitUserEmail)
                    .textFieldStyle(.roundedBorder)
                
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .help("The email associated with this GitHub account. Crucial for GitHub to link your commits to your profile.")
            }
        } header: {
            Text("Git Commit Identity")
        } footer: {
            Text("Required. When you switch to this profile, your local Git config will be updated so that your work and personal commits are correctly attributed and not mixed up.")
        }
    }

    // MARK: - Actions

    private var actionsView: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(action: save) {
                if isSaving {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Saving...")
                    }
                    .frame(width: 90)
                } else {
                    Text(mode.buttonTitle)
                        .frame(width: 90)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!isValid || isSaving)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Validation Helpers

    /// Validates comprehensive input before saving
    private func validateInputs() throws {
        // Validate no control characters in any field
        let inputs: [(String, String)] = [
            (displayName, "Display name"),
            (githubUsername, "GitHub username"),
            (gitUserName, "Name"),
            (gitUserEmail, "Email")
        ]

        for (input, fieldName) in inputs {
            guard !ValidationUtilities.containsControlCharacters(input) else {
                throw ValidationError.invalidCharacters(fieldName)
            }
        }

        // Validate lengths
        guard displayName.count <= 100 else {
            throw ValidationError.inputTooLong("Display name")
        }
        guard githubUsername.count <= 254 else {  // GitHub's max username length or Email length
            throw ValidationError.inputTooLong("GitHub username")
        }
        guard gitUserName.count <= 200 else {
            throw ValidationError.inputTooLong("Name")
        }
        guard gitUserEmail.count <= 254 else {  // RFC 5321 max email length
            throw ValidationError.inputTooLong("Email")
        }

        // Validate GitHub username format
        guard ValidationUtilities.isValidGitHubUsername(githubUsername) else {
            throw ValidationError.invalidGitHubUsername
        }

        // Validate email format
        guard isValidEmail(gitUserEmail) else {
            throw ValidationError.invalidEmail
        }

        // Validate token format (reuses isTokenValidForSave logic)
        guard isTokenValidForSave else {
            throw ValidationError.invalidToken
        }
    }

    /// Validates email format
    private func isValidEmail(_ email: String) -> Bool {
        return ValidationUtilities.isValidEmail(email)
    }

    /// Validates GitHub Personal Access Token format
    private func isValidGitHubToken(_ token: String) -> Bool {
        return ValidationUtilities.isValidGitHubToken(token)
    }

    // MARK: - Actions

    /// Checks if the entered username exists in gh auth status (non-blocking, informational)
    private func checkCLIAuthStatus(for username: String) async {
        guard GitHubCLIService.shared.isInstalled else {
            await MainActor.run { cliAuthStatus = .cliNotAvailable }
            return
        }

        await MainActor.run { cliAuthStatus = .checking }

        do {
            let accounts = try await GitHubCLIService.shared.getAuthenticatedAccounts()
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if accounts.contains(where: { $0.lowercased() == username.lowercased() }) {
                    cliAuthStatus = .authenticated
                } else {
                    cliAuthStatus = .notAuthenticated
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run { cliAuthStatus = .cliNotAvailable }
        }
    }

    private func loadExistingAccount() {
        guard case .edit(let account) = mode else { return }

        displayName = account.displayName
        githubUsername = account.githubUsername
        gitUserName = account.gitUserName
        gitUserEmail = account.gitUserEmail
        cloudflareAccountId = account.cloudflareAccountId
        // SECURITY: Load token from Keychain (never from model or UserDefaults)
        let storedToken = KeychainService.shared.readAccountToken(accountId: account.id) ?? ""
        personalAccessToken = storedToken
        // Save original token to allow unchanged token in validation
        originalToken = storedToken

        let storedCfToken = KeychainService.shared.readCloudflareToken(accountId: account.id) ?? ""
        cloudflareApiToken = storedCfToken
        originalCloudflareToken = storedCfToken
    }

    private func save() {
        isSaving = true

        Task {
            defer {
                Task { @MainActor in
                    isSaving = false
                    // SECURITY: Securely zero token from memory after save attempt
                    ValidationUtilities.secureZeroString(&personalAccessToken)
                    ValidationUtilities.secureZeroString(&cloudflareApiToken)
                }
            }

            do {
                // SECURITY: Validate all inputs before processing
                try validateInputs()

                // Create account with trimmed values
                let account = DevProfile(
                    id: mode.account?.id ?? UUID(),
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    githubUsername: githubUsername.trimmingCharacters(in: .whitespaces),
                    personalAccessToken: personalAccessToken.trimmingCharacters(in: .whitespaces),
                    gitUserName: gitUserName.trimmingCharacters(in: .whitespaces),
                    gitUserEmail: gitUserEmail.trimmingCharacters(in: .whitespaces),
                    cloudflareAccountId: cloudflareAccountId.trimmingCharacters(in: .whitespaces),
                    cloudflareApiToken: cloudflareApiToken.trimmingCharacters(in: .whitespaces),
                    isActive: mode.account?.isActive ?? false,
                    createdAt: mode.account?.createdAt ?? Date(),
                    lastUsedAt: mode.account?.lastUsedAt
                )

                switch mode {
                case .add:
                    try accountStore.addAccount(account)
                    // Show CLI login reminder for new accounts if CLI is installed
                    await MainActor.run {
                        if GitHubCLIService.shared.isInstalled {
                            savedAccountName = account.displayName
                            showingCLIReminder = true
                        } else {
                            dismiss()
                        }
                    }
                    return // Don't dismiss yet if showing reminder
                case .edit:
                    try accountStore.updateAccount(account)
                }

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    saveError = error
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Token Help View

struct TokenHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Personal Access Token")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Text("A Personal Access Token (PAT) is required to authenticate with GitHub.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("How to create a PAT:")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("1. Go to GitHub Settings > Developer settings > Personal access tokens")
                Text("2. Click \"Generate new token (classic)\"")
                Text("3. Give it a name and select the required scopes:")

                VStack(alignment: .leading, spacing: 2) {
                    Text("  \u{2022} repo (for private repositories)")
                    Text("  \u{2022} read:user")
                    Text("  \u{2022} user:email")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

                Text("4. Click \"Generate token\" and copy it")
            }
            .font(.callout)

            Spacer()

            HStack {
                Spacer()
                Link("Open GitHub Settings", destination: URL(string: "https://github.com/settings/tokens")!)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding()
        .frame(width: 420, height: 370)
    }
}

// MARK: - Preview

#Preview("Add Account") {
    AddEditAccountView(mode: .add)
        .environmentObject(AccountStore())
}

#Preview("Edit Account") {
    AddEditAccountView(mode: .edit(.preview))
        .environmentObject(AccountStore())
}
