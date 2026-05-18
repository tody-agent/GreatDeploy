import SwiftUI

struct WizardStepInfo { let title: String; let icon: String; var isCompleted: Bool = false }

struct WizardContainer<Content: View>: View {
    let steps: [WizardStepInfo]
    @Binding var currentStep: Int
    let onFinish: (() -> Void)?
    let content: Content

    init(steps: [WizardStepInfo], currentStep: Binding<Int>, onFinish: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.steps = steps; self._currentStep = currentStep; self.onFinish = onFinish; self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { index in
                    HStack(spacing: 4) {
                        Circle().fill(index < currentStep ? .green : (index == currentStep ? .blue : .gray.opacity(0.3))).frame(width: 10, height: 10)
                        if index < steps.count - 1 { Rectangle().fill(index < currentStep ? Color.green : Color.gray.opacity(0.3)).frame(width: 30, height: 2) }
                    }
                }
            }.padding(.top, 20).padding(.bottom, 16)
            Divider()
            ScrollView { VStack(spacing: 24) { content }.padding(30).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            HStack {
                if currentStep > 0 { Button(action: { withAnimation { currentStep -= 1 } }) { Label("Back", systemImage: "chevron.left") }.buttonStyle(.bordered) }
                Spacer()
                if currentStep < steps.count - 1 { Button(action: { withAnimation { currentStep += 1 } }) { Label("Next", systemImage: "chevron.right") }.buttonStyle(.borderedProminent) }
                else { Button(action: { onFinish?() }) { Label("Finish", systemImage: "checkmark") }.buttonStyle(.borderedProminent) }
            }.padding()
        }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WizardStepView<Content: View>: View {
    let icon: String; let title: String; let description: String; let content: Content
    init(icon: String, title: String, description: String, @ViewBuilder content: () -> Content) { self.icon = icon; self.title = title; self.description = description; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.blue).frame(width: 44, height: 44).background(Color.blue.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.title2).fontWeight(.bold); Text(description).font(.subheadline).foregroundStyle(.secondary) }
            }
            content
        }
    }
}

struct InfoCard: View {
    let icon: String; let title: String; let description: String; var color: Color = .blue
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 36, height: 36).background(color.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline).fontWeight(.medium); Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(12).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SelectionCard: View {
    let icon: String; let title: String; let description: String; let isSelected: Bool; let color: Color; let action: () -> Void
    init(icon: String, title: String, description: String, isSelected: Bool, color: Color = .blue, action: @escaping () -> Void) { self.icon = icon; self.title = title; self.description = description; self.isSelected = isSelected; self.color = color; self.action = action }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 32)).foregroundStyle(isSelected ? .white : color)
                VStack(spacing: 4) { Text(title).font(.headline).foregroundStyle(isSelected ? .white : .primary); Text(description).font(.caption).foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary).multilineTextAlignment(.center) }
            }.frame(maxWidth: .infinity).padding(20).background(isSelected ? color : Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}
