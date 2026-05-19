import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showNotificationOnSwitch") private var showNotificationOnSwitch = true
    @State private var isQuitting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                generalSection
                notificationsSection
                aboutSection
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)
            VStack(spacing: 0) {
                Toggle("Show notification on profile switch", isOn: $showNotificationOnSwitch)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Menu Bar")
                .font(.headline)
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch at Login")
                            .font(.body)
                        Text("Start GreatDeploy automatically when you log in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    LaunchAtLoginToggle()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.headline)
            VStack(spacing: 0) {
                HStack {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().padding(.leading, 16)
                HStack {
                    Text("Built with")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("SwiftUI")
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct LaunchAtLoginToggle: View {
    @State private var isEnabled = false

    var body: some View {
        Toggle("", isOn: $isEnabled)
            .toggleStyle(.switch)
            .onAppear { checkStatus() }
            .onChange(of: isEnabled) { newValue in toggleLaunchAtLogin(newValue) }
    }

    private func checkStatus() {
        if #available(macOS 14.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 14.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {}
        }
    }
}