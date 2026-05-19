import SwiftUI

struct SkillCardView: View {
    let skill: DiscoveredSkill
    let status: SkillReviewStatus
    let onImport: () -> Void
    let onSkip: () -> Void
    let onResolve: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            descriptionSection
            actionSection
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(cardOverlay)
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let tool = skill.sourceToolEnum {
                        Label(tool.displayName, systemImage: tool.iconName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(skill.lastModified.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: status.icon)
                .foregroundStyle(statusColor)
        }
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skill.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 2)
            
            if isExpanded {
                Text(skill.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button(isExpanded ? "Show Less" : "Show More") {
                withAnimation { isExpanded.toggle() }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
    }
    
    private var actionSection: some View {
        Group {
            switch status {
            case .pending:
                HStack(spacing: 12) {
                    Button("Import") { onImport() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Skip") { onSkip() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            case .imported:
                Label("Imported", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .skipped:
                Label("Skipped", systemImage: "minus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .conflict:
                Button("Resolve Conflict") { onResolve() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
            case .error(let message):
                Label(message, systemImage: "exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
    
    @ViewBuilder
    private var cardOverlay: some View {
        if status == .conflict {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.5), lineWidth: 2)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .imported: return .green
        case .skipped: return .secondary
        case .conflict: return .orange
        case .error: return .red
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SkillCardView(
            skill: DiscoveredSkill(
                name: "cm-tdd",
                description: "Test-driven development skill for writing tests first",
                content: "# cm-tdd\n\nTest first...",
                sourceTool: .claudeCode,
                sourcePath: URL(fileURLWithPath: "/test"),
                lastModified: Date().addingTimeInterval(-86400)
            ),
            status: .pending,
            onImport: {},
            onSkip: {},
            onResolve: {}
        )
        
        SkillCardView(
            skill: DiscoveredSkill(
                name: "flutter-dev",
                description: "Flutter development skill",
                content: "# flutter-dev\n\nFlutter...",
                sourceTool: .openCode,
                sourcePath: URL(fileURLWithPath: "/test2"),
                lastModified: Date().addingTimeInterval(-172800)
            ),
            status: .conflict,
            onImport: {},
            onSkip: {},
            onResolve: {}
        )
    }
    .padding()
}