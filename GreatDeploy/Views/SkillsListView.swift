import SwiftUI

struct SkillsListView: View {
    @State private var skills: [SkillItem] = []
    @State private var searchText = ""
    @State private var selectedSkill: SkillItem?
    @State private var showingCreateSheet = false
    @State private var newSkillName = ""
    @State private var isLoading = true

    private let skillService = SkillsService.shared

    var filteredSkills: [SkillItem] {
        if searchText.isEmpty { return skills }
        return skills.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if isLoading {
                loadingView
            } else if skills.isEmpty {
                emptyStateView
            } else {
                skillsListView
            }
        }
        .onAppear(perform: loadSkills)
        .sheet(isPresented: $showingCreateSheet) { createSkillSheet }
        .sheet(item: $selectedSkill) { skill in SimplifiedSkillDetailView(skill: skill, onSave: { saveSkill($0) }) }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skills")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("\(skills.count) skills installed globally")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button(action: { showingCreateSheet = true }) {
                    Label("New Skill", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Text("Loading skills...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Global Skills")
                .font(.title3)
                .fontWeight(.medium)
            Text("Skills help AI understand your project structure,\ncoding style, and business logic.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: { showingCreateSheet = true }) {
                Label("Create First Skill", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var skillsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSkills) { skill in
                    SimplifiedSkillRow(skill: skill, onSelect: { selectedSkill = skill }, onDelete: { deleteSkill(skill) })
                    if skill.id != filteredSkills.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var createSkillSheet: some View {
        VStack(spacing: 20) {
            Text("Create Skill")
                .font(.headline)
            TextField("e.g., flutter-expert, react-patterns", text: $newSkillName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showingCreateSheet = false; newSkillName = "" }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create") { createSkill() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSkillName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func loadSkills() {
        isLoading = true
        skills = (try? skillService.scanGlobalSkillItems()) ?? []
        isLoading = false
    }

    private func deleteSkill(_ skill: SkillItem) {
        do {
            try skillService.deleteSkill(at: skill.path)
            skills.removeAll { $0.id == skill.id }
        } catch {}
    }

    private func saveSkill(_ skill: SkillItem) {
        do {
            try skillService.writeSkill(skill.content, at: skill.path)
            loadSkills()
        } catch {}
    }

    private func createSkill() {
        guard !newSkillName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let skill = try skillService.createSkill(name: newSkillName, in: skillService.globalSkillsDirectory)
            skills.append(skill)
            newSkillName = ""
            showingCreateSheet = false
            selectedSkill = skill
        } catch {}
    }
}

struct SimplifiedSkillRow: View {
    let skill: SkillItem; let onSelect: () -> Void; let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(skill.description.isEmpty ? "No description" : skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onSelect) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .onTapGesture { onSelect() }
    }
}

struct SimplifiedSkillDetailView: View {
    let skill: SkillItem; let onSave: (SkillItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String

    init(skill: SkillItem, onSave: @escaping (SkillItem) -> Void) {
        self.skill = skill
        self.onSave = onSave
        self._content = State(initialValue: skill.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(skill.name)
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    var updated = skill
                    updated = SkillItem(name: skill.name, path: skill.path, description: skill.description, content: content)
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()
            TextEditor(text: $content)
                .font(.system(size: 13, design: .monospaced))
                .padding(8)
        }
        .frame(width: 700, height: 500)
    }
}