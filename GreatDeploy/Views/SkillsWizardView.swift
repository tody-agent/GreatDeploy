import SwiftUI

@available(*, deprecated, message: "SkillsWizardView is deprecated. Use SkillsListView instead for simplified UX.")
struct SkillsWizardView: View {
    var body: some View {
        SkillsListView()
    }
}