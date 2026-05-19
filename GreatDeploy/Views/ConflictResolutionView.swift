import SwiftUI

struct ConflictResolutionView: View {
    let existingSkill: RegisteredSkill
    let newSkill: DiscoveredSkill
    let onResolve: (ConflictResolution) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            comparisonView
            Divider()
            optionsView
        }
        .frame(width: 650, height: 500)
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resolve Conflict")
                .font(.title2.bold())
            Text("The skill \"\(newSkill.name)\" already exists. Choose how to resolve:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    
    private var comparisonView: some View {
        HStack(spacing: 16) {
            skillVersionCard(
                title: "Current (Master)",
                source: existingSkill.masterPath.lastPathComponent,
                lastModified: existingSkill.lastModified,
                content: existingSkill.content,
                color: .blue
            )
            
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            skillVersionCard(
                title: "Discovered (\(newSkill.sourceToolEnum?.displayName ?? "Unknown"))",
                source: newSkill.sourcePath,
                lastModified: newSkill.lastModified,
                content: newSkill.content,
                color: .green
            )
        }
        .padding()
    }
    
    private func skillVersionCard(title: String, source: String, lastModified: Date, content: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                HStack {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastModified.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .offset(x: -16)
            }
            
            ScrollView {
                Text(content)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var optionsView: some View {
        VStack(spacing: 12) {
            optionButton(
                title: "Keep Existing",
                description: "Keep the current master version, discard the discovered version",
                icon: "checkmark.circle",
                color: .blue
            ) { onResolve(.keepExisting) }
            
            optionButton(
                title: "Replace with New",
                description: "Update master with the discovered version from \(newSkill.sourceToolEnum?.displayName ?? "unknown tool")",
                icon: "arrow.triangle.2.circlepath",
                color: .green
            ) { onResolve(.replaceWithNew) }
            
            optionButton(
                title: "Keep Both",
                description: "Keep existing skill and add the discovered version with a new name",
                icon: "doc.on.doc",
                color: .orange
            ) { onResolve(.keepBoth) }
        }
        .padding()
    }
    
    private func optionButton(title: String, description: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ConflictResolutionView(
        existingSkill: RegisteredSkill(
            name: "flutter-dev",
            masterPath: URL(fileURLWithPath: "/Users/test/.greatdeploy/skills/flutter-dev"),
            description: "Flutter development skill",
            content: "# flutter-dev\n\n## Description\nFlutter development...",
            lastModified: Date().addingTimeInterval(-86400 * 5),
            syncRecords: [:]
        ),
        newSkill: DiscoveredSkill(
            name: "flutter-dev",
            description: "Flutter skill",
            content: "# flutter-dev\n\n## Description\nUpdated Flutter skill...",
            sourceTool: .cursor,
            sourcePath: URL(fileURLWithPath: "/Users/test/.cursor/rules/flutter-dev.md"),
            lastModified: Date().addingTimeInterval(-86400 * 2)
        ),
        onResolve: { _ in }
    )
}