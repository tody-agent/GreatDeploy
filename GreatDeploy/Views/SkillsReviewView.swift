import SwiftUI

struct SkillsReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SkillsReviewViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(width: 700, height: 500)
        .task {
            await viewModel.loadSkills()
        }
        .sheet(isPresented: $viewModel.showingConflict) {
            if let conflict = viewModel.currentConflict {
                ConflictResolutionView(
                    existingSkill: conflict.existing,
                    newSkill: conflict.new,
                    onResolve: { resolution in
                        viewModel.resolveConflict(resolution)
                    }
                )
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skills Review")
                    .font(.title2.bold())
                Text(viewModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Scanning AI tools...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        case .empty:
            VStack(spacing: 16) {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Skills Found")
                    .font(.title3.bold())
                Text("No skills were found in your installed AI tools.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        case .ready:
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(viewModel.discoveredSkills) { skill in
                        SkillCardView(
                            skill: skill,
                            status: viewModel.status(for: skill),
                            onImport: { viewModel.importSkill(skill) },
                            onSkip: { viewModel.skipSkill(skill) },
                            onResolve: { viewModel.showConflictSheet(for: skill) }
                        )
                    }
                }
                .padding()
            }
            
        case .error(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.title3.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await viewModel.loadSkills() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var footerView: some View {
        HStack {
            if viewModel.state == .ready {
                Button("Import All (\(viewModel.importableCount))") {
                    viewModel.importAll()
                }
                .buttonStyle(.borderedProminent)
                Button("Skip All") {
                    viewModel.skipAll()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Text("\(viewModel.importedCount) imported")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

@MainActor
final class SkillsReviewViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case empty
        case ready
        case error(String)
    }
    
    @Published var state: State = .loading
    @Published var discoveredSkills: [DiscoveredSkill] = []
    @Published var skillStatus: [String: SkillReviewStatus] = [:]
    @Published var showingConflict = false
    @Published var currentConflict: SkillConflict?
    
    private let harvester = SkillsHarvesterService.shared
    private let registry = SkillRegistry.shared
    private let validator = SkillContentValidator()
    
    var statusText: String {
        switch state {
        case .loading: return "Scanning..."
        case .empty: return "No skills discovered"
        case .ready: return "Found \(discoveredSkills.count) skills"
        case .error: return "Error loading skills"
        }
    }
    
    var importableCount: Int {
        discoveredSkills.filter { skillStatus[$0.id] == .pending }.count
    }
    
    var importedCount: Int {
        discoveredSkills.filter { skillStatus[$0.id] == .imported }.count
    }
    
    func loadSkills() async {
        state = .loading
        do {
            let skills = try await harvester.harvestAllSkills()
            if skills.isEmpty {
                state = .empty
            } else {
                discoveredSkills = skills
                for skill in skills {
                    skillStatus[skill.id] = .pending
                }
                checkForConflicts()
                state = .ready
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func status(for skill: DiscoveredSkill) -> SkillReviewStatus {
        skillStatus[skill.id] ?? .pending
    }
    
    func importSkill(_ skill: DiscoveredSkill) {
        let validation = validator.validate(skill.content)
        if validation.hasWarnings {
            // Could show warning dialog here
        }
        
        do {
            _ = try registry.installSkill(name: skill.name, content: skill.content)
            skillStatus[skill.id] = .imported
        } catch {
            skillStatus[skill.id] = .error(error.localizedDescription)
        }
    }
    
    func skipSkill(_ skill: DiscoveredSkill) {
        skillStatus[skill.id] = .skipped
    }
    
    func skipAll() {
        for skill in discoveredSkills {
            skillStatus[skill.id] = .skipped
        }
    }
    
    func importAll() {
        for skill in discoveredSkills where skillStatus[skill.id] == .pending {
            importSkill(skill)
        }
    }
    
    func checkForConflicts() {
        for skill in discoveredSkills {
            if let existing = try? registry.getMasterSkill(name: skill.name), existing.content != skill.content {
                skillStatus[skill.id] = .conflict
            }
        }
    }
    
    func showConflictSheet(for skill: DiscoveredSkill) {
        guard let existing = try? registry.getMasterSkill(name: skill.name) else { return }
        currentConflict = SkillConflict(existing: existing, new: skill)
        showingConflict = true
    }
    
    func resolveConflict(_ resolution: ConflictResolution) {
        guard let conflict = currentConflict else { return }
        
        switch resolution {
        case .keepExisting:
            skillStatus[conflict.new.id] = .skipped
        case .replaceWithNew:
            do {
                try registry.updateSkill(name: conflict.existing.name, content: conflict.new.content)
                skillStatus[conflict.new.id] = .imported
            } catch {
                skillStatus[conflict.new.id] = .error(error.localizedDescription)
            }
        case .keepBoth:
            let newName = "\(conflict.new.name) (\(conflict.new.sourceToolEnum?.displayName ?? "Unknown"))"
            do {
                _ = try registry.installSkill(name: newName, content: conflict.new.content)
                skillStatus[conflict.new.id] = .imported
            } catch {
                skillStatus[conflict.new.id] = .error(error.localizedDescription)
            }
        }
        
        showingConflict = false
        currentConflict = nil
    }
}

enum SkillReviewStatus: Equatable {
    case pending
    case imported
    case skipped
    case conflict
    case error(String)
    
    var icon: String {
        switch self {
        case .pending: return "circle.dashed"
        case .imported: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .conflict: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

struct SkillConflict {
    let existing: RegisteredSkill
    let new: DiscoveredSkill
}

enum ConflictResolution {
    case keepExisting
    case replaceWithNew
    case keepBoth
}

#Preview {
    SkillsReviewView()
}