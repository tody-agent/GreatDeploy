import SwiftUI
import ServiceManagement

// MARK: - General & About Settings Detail View

struct AboutSettingsDetailView: View {
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true
    @AppStorage("enableVisualEffects") private var enableVisualEffects = true
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("General & About")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                VStack(spacing: 24) {
                    // General Settings section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preferences")
                            .font(.headline)
                            .padding(.horizontal, 40)

                        settingsGroup {
                            Toggle("Show notification on account switch", isOn: $showNotificationOnSwitch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                            Divider()
                                .padding(.leading, 16)

                            Toggle("Enable visual effects", isOn: $enableVisualEffects)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                            Divider()
                                .padding(.leading, 16)

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Launch at login", isOn: Binding(
                                    get: { launchAtLogin },
                                    set: { setLaunchAtLogin($0) }
                                ))
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if let error = launchAtLoginError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }

                    // About section
                    VStack(alignment: .center, spacing: 16) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                            .padding(.top, 20)

                        Text("Great Deploy")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Quickly switch between profiles with Keychain and git config management.")
                            .multilineTextAlignment(.center)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 40)
                            
                        HStack(spacing: 24) {
                            Link(destination: URL(string: "https://github.com/MinhOmega/GreatDeploy")!) {
                                Label("View on GitHub", systemImage: "link")
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#Preview {
    AboutSettingsDetailView()
        .frame(width: 500, height: 600)
}
