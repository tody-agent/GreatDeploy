import SwiftUI

struct SkillsWizardView: View {
    @State private var currentStep = 0
    @State private var selectedScope: SkillScope = .none
    @State private var globalSkills: [SkillItem] = []
    @State private var projectSkills: [SkillItem] = []
    @State private var selectedProject: URL?
    @State private var searchText = ""
    @State private var selectedSkill: SkillItem?
    @State private var showingCreateSkill = false
    @State private var newSkillName = ""
    @State private var steps: [WizardStepInfo] = [
        WizardStepInfo(title: "Welcome", icon: "hand.wave", isCompleted: true),
        WizardStepInfo(title: "Choose Scope", icon: "folder", isCompleted: false),
        WizardStepInfo(title: "Manage", icon: "sparkles", isCompleted: false)
    ]

    enum SkillScope { case none, global, project }

    var filteredGlobalSkills: [SkillItem] { searchText.isEmpty ? globalSkills : globalSkills.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) } }

    var body: some View {
        VStack(spacing: 0) {
            headerView; Divider()
            WizardContainer(steps: steps, currentStep: $currentStep, onFinish: {}) {
                switch currentStep {
                case 0: welcomeStep
                case 1: chooseScopeStep
                case 2: manageStep
                default: EmptyView()
                }
            }
        }.onAppear(perform: loadGlobalSkills).sheet(item: $selectedSkill) { skill in SkillDetailView(skill: skill, onSave: { saveSkill($0) }) }.sheet(isPresented: $showingCreateSkill) { createSkillSheet }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text("Skills Management").font(.title2).fontWeight(.bold); Text("Manage skills for AI tools").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
            if currentStep == 2 { HStack(spacing: 12) { TextField("Search...", text: $searchText).textFieldStyle(.roundedBorder).frame(width: 180); Button(action: { showingCreateSkill = true }) { Label("New Skill", systemImage: "plus") }.buttonStyle(.borderedProminent) } }
        }.padding()
    }

    private var welcomeStep: some View {
        WizardStepView(icon: "sparkles", title: "Skills là gì?", description: "Hướng dẫn cho AI") {
            VStack(spacing: 16) {
                InfoCard(icon: "brain", title: "Skills = Hướng dẫn cho AI", description: "Skills chứa hướng dẫn chi tiết để AI thực hiện công việc cụ thể.")
                InfoCard(icon: "folder", title: "2 loại Skills", description: "Global: Dùng cho mọi project\nProject: Chỉ dùng cho project cụ thể")
            }
        }
    }

    private var chooseScopeStep: some View {
        WizardStepView(icon: "folder", title: "Chọn phạm vi", description: "Quản lý skills ở đâu?") {
            HStack(spacing: 16) {
                SelectionCard(icon: "globe", title: "Global Skills", description: "Dùng cho tất cả project", isSelected: selectedScope == .global, color: .purple) { selectedScope = .global; updateStepCompletion() }
                SelectionCard(icon: "folder.badge.gearshape", title: "Project Skills", description: "Chỉ dùng cho project hiện tại", isSelected: selectedScope == .project, color: .orange) { selectedScope = .project; updateStepCompletion() }
            }
        }
    }

    private var manageStep: some View {
        VStack(spacing: 16) {
            if selectedScope == .global { globalSkillsList }
            else if selectedScope == .project { Text("Project: \(selectedProject?.lastPathComponent ?? "None")"); projectSkillsList }
            else { Text("Vui lòng quay lại chọn phạm vi") }
        }
    }

    private var globalSkillsList: some View {
        Group {
            if filteredGlobalSkills.isEmpty { VStack(spacing: 12) { Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.tertiary); Text("Chưa có Global Skills").font(.headline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding() }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(filteredGlobalSkills) { skill in SkillRow(skill: skill, onSelect: { selectedSkill = skill }, onDelete: { deleteSkill(skill) }); if skill.id != filteredGlobalSkills.last?.id { Divider().padding(.leading, 60) } } }.padding(.vertical, 8) } }
        }
    }

    private var projectSkillsList: some View {
        Group {
            if projectSkills.isEmpty { VStack(spacing: 12) { Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.tertiary); Text("Chưa có Project Skills").font(.headline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding() }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(projectSkills) { skill in SkillRow(skill: skill, onSelect: { selectedSkill = skill }, onDelete: { deleteProjectSkill(skill) }); if skill.id != projectSkills.last?.id { Divider().padding(.leading, 60) } } }.padding(.vertical, 8) } }
        }
    }

    private var createSkillSheet: some View {
        VStack(spacing: 20) {
            Text("Create New Skill").font(.headline)
            TextField("e.g., flutter-expert", text: $newSkillName).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showingCreateSkill = false; newSkillName = "" }.buttonStyle(.bordered)
                Spacer()
                Button("Create") { createSkill() }.buttonStyle(.borderedProminent).disabled(newSkillName.isEmpty)
            }
        }.padding().frame(width: 350)
    }

    private func updateStepCompletion() { if currentStep == 1 { steps[1].isCompleted = selectedScope != .none } }
    private func loadGlobalSkills() { globalSkills = (try? SkillsService.shared.scanGlobalSkillItems()) ?? [] }
    private func loadProjectSkills() { guard let project = selectedProject else { projectSkills = []; return }; projectSkills = (try? SkillsService.shared.scanProjectSkillItems(at: project)) ?? [] }
    private func deleteSkill(_ skill: SkillItem) { do { try SkillsService.shared.deleteSkill(at: skill.path); globalSkills.removeAll { $0.id == skill.id } } catch {} }
    private func deleteProjectSkill(_ skill: SkillItem) { do { try SkillsService.shared.deleteSkill(at: skill.path); projectSkills.removeAll { $0.id == skill.id } } catch {} }
    private func saveSkill(_ skill: SkillItem) { do { try SkillsService.shared.writeSkill(skill.content, at: skill.path); loadGlobalSkills() } catch {} }
    private func createSkill() { guard !newSkillName.isEmpty else { return }; do { let skill = try SkillsService.shared.createSkill(name: newSkillName, in: SkillsService.shared.globalSkillsDirectory); globalSkills.append(skill); newSkillName = ""; showingCreateSkill = false } catch {} }
}

struct SkillRow: View {
    let skill: SkillItem; let onSelect: () -> Void; let onDelete: () -> Void
    @State private var isHovering = false
    var body: some View {
        HStack(spacing: 16) {
            ZStack { RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.15)).frame(width: 36, height: 36); Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(.purple) }
            VStack(alignment: .leading, spacing: 4) { Text(skill.name).font(.subheadline).fontWeight(.medium); Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            if isHovering { HStack(spacing: 8) { Button(action: onSelect) { Image(systemName: "doc.text").foregroundStyle(.blue) }.buttonStyle(.plain); Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(.red) }.buttonStyle(.plain) } }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
    }
}

struct SkillDetailView: View {
    let skill: SkillItem; let onSave: (SkillItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    init(skill: SkillItem, onSave: @escaping (SkillItem) -> Void) { self.skill = skill; self.onSave = onSave; self._content = State(initialValue: skill.content) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(skill.name).font(.headline); Spacer(); Button("Cancel") { dismiss() }.buttonStyle(.bordered); Button("Save") { var updated = skill; updated = SkillItem(name: skill.name, path: skill.path, description: skill.description, content: content); onSave(updated); dismiss() }.buttonStyle(.borderedProminent) }.padding()
            Divider()
            TextEditor(text: $content).font(.system(size: 13, design: .monospaced)).padding(8)
        }.frame(width: 700, height: 500)
    }
}
