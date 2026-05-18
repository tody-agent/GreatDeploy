import SwiftUI

struct SyncWizardView: View {
    @State private var currentStep = 0
    @State private var selectedRole: SyncRole = .none
    @State private var steps: [WizardStepInfo] = [
        WizardStepInfo(title: "Welcome", icon: "hand.wave", isCompleted: true),
        WizardStepInfo(title: "Choose Role", icon: "arrow.triangle.2.circlepath", isCompleted: false),
        WizardStepInfo(title: "Setup", icon: "gearshape", isCompleted: false),
        WizardStepInfo(title: "Complete", icon: "checkmark.circle", isCompleted: false)
    ]

    enum SyncRole { case none, host, client }

    var body: some View {
        VStack(spacing: 0) {
            headerView; Divider()
            WizardContainer(steps: steps, currentStep: $currentStep, onFinish: {}) {
                switch currentStep {
                case 0: welcomeStep
                case 1: chooseRoleStep
                case 2: setupStep
                case 3: completeStep
                default: EmptyView()
                }
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text("Sync").font(.title2).fontWeight(.bold); Text("Đồng bộ giữa các máy").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
        }.padding()
    }

    private var welcomeStep: some View {
        WizardStepView(icon: "arrow.triangle.2.circlepath", title: "Sync là gì?", description: "Đồng bộ dữ liệu giữa các máy") {
            VStack(spacing: 16) {
                InfoCard(icon: "lock.fill", title: "Mã hóa E2E", description: "Dữ liệu được mã hóa trước khi gửi qua mạng.")
                InfoCard(icon: "server.rack", title: "Cloudflare Tunnel", description: "Kết nối qua Cloudflare Quick Tunnel, không cần mở port.")
            }
        }
    }

    private var chooseRoleStep: some View {
        WizardStepView(icon: "arrow.triangle.2.circlepath", title: "Chọn vai trò", description: "Host hoặc Client?") {
            HStack(spacing: 16) {
                SelectionCard(icon: "server.rack", title: "Host", description: "Chia sẻ vault từ máy này", isSelected: selectedRole == .host, color: .blue) { selectedRole = .host; updateStepCompletion() }
                SelectionCard(icon: "laptopcomputer", title: "Client", description: "Kết nối đến máy Host", isSelected: selectedRole == .client, color: .green) { selectedRole = .client; updateStepCompletion() }
            }
        }
    }

    private var setupStep: some View {
        WizardStepView(icon: "gearshape", title: "Cấu hình", description: selectedRole == .host ? "Thiết lập server" : "Kết nối đến server") {
            switch selectedRole {
            case .host: hostSetupView
            case .client: clientSetupView
            case .none: Text("Vui lòng quay lại chọn vai trò")
            }
        }
    }

    private var hostSetupView: some View {
        VStack(spacing: 16) {
            InfoCard(icon: "1.circle", title: "Bước 1: Start Server", description: "Khởi động server trên máy này.")
            InfoCard(icon: "2.circle", title: "Bước 2: Cloudflare Tunnel", description: "Tạo tunnel để expose server.")
            InfoCard(icon: "3.circle", title: "Bước 3: Share URL", description: "Client sẽ kết nối qua URL này.")
        }
    }

    private var clientSetupView: some View {
        VStack(spacing: 16) {
            InfoCard(icon: "1.circle", title: "Bước 1: Nhập URL", description: "Nhập URL tunnel từ máy Host.")
            InfoCard(icon: "2.circle", title: "Bước 2: Nhập Passphrase", description: "Nhập passphrase để giải mã.")
            InfoCard(icon: "3.circle", title: "Bước 3: Connect", description: "Kết nối và đồng bộ.")
        }
    }

    private var completeStep: some View {
        WizardStepView(icon: "checkmark.circle", title: "Hoàn tất", description: "Sync đã được cấu hình") {
            InfoCard(icon: "checkmark.circle.fill", title: "Sync Active", description: "Dữ liệu sẽ được đồng bộ tự động.", color: .green)
        }
    }

    private func updateStepCompletion() {
        switch currentStep {
        case 1: steps[1].isCompleted = selectedRole != .none
        case 2: steps[2].isCompleted = true
        case 3: steps[3].isCompleted = true
        default: break
        }
    }
}
