# Design: Skill Auto-Harvest Engine
Version: 1.0 | Date: 2026-05-18

## Overview
Background service that discovers skills from all installed AI tools on first launch, caches results, and notifies user. User reviews before skills are installed to master registry.

---

## Component Architecture

### 1. SkillsHarvesterService

**Responsibility:** One-shot discovery engine that scans all tool directories

**Public API:**
```swift
final class SkillsHarvesterService {
    static let shared = SkillsHarvesterService()
    
    func harvestAllSkills() async throws -> [DiscoveredSkill]
    func cachedDiscovery() -> DiscoveryCache?
    func clearCache() throws
}
```

**Discovery Flow:**
1. Get installed tools from `ToolDiscoveryService.shared.installedSkillsCapableTools()`
2. For each tool: scan skills via `SkillsService.shared.scanGlobalSkillItems(for:)`
3. Build `DiscoveredSkill` model with source tool + metadata
4. Save to `DiscoveryCache` for persistence
5. Return array of discovered skills

**Models:**
```swift
struct DiscoveredSkill: Identifiable, Codable {
    let id: String  // hash of content
    let name: String
    let description: String
    let content: String
    let sourceTool: AITool
    let sourcePath: URL
    let lastModified: Date
}

struct DiscoveryCache: Codable {
    let discoveredAt: Date
    let skills: [DiscoveredSkill]
    let toolsScanned: [AITool]
    let version: String  // "1.0"
}
```

**Cache Location:** `~/.greatdeploy/discovery-cache.json`

**Version Handling:** If cache version != current version, invalidate and re-scan.

---

### 2. Notification Service

**Responsibility:** Present macOS notification when skills are discovered

**Public API:**
```swift
final class HarvestNotificationService {
    static let shared = HarvestNotificationService()
    
    func requestAuthorization() async -> Bool
    func sendDiscoveryNotification(skillCount: Int, toolCount: Int)
}
```

**Notification Content:**
- **Title:** "Skills Discovered"
- **Body:** "Found {N} skills from {X} AI tools. Tap to review."
- **Category:** `GREATDEPLOY_SKILLS`
- **Action:** Opens `SkillsReviewView`

**Authorization:** Request on first launch, not blocking. If denied, skip notification and show in-app banner instead.

---

### 3. SkillsReviewView

**Responsibility:** Display discovered skills for user review before import

**States:**
- **Loading:** Scanning tools...
- **Empty:** No skills found (all tools empty)
- **Ready:** Skills grid with import/skip controls
- **Conflict:** Conflict resolution sheet

**Layout:**
```
┌─────────────────────────────────────────────────────┐
│ Skills Review                            [✕ Close]  │
├─────────────────────────────────────────────────────┤
│ Found 47 skills from 3 tools                        │
│                                                     │
│ [████████████░░░░░░] 80% imported                  │
│                                                     │
│ ┌─────────────────┐ ┌─────────────────┐             │
│ │ cm-tdd          │ │ cm-planning     │             │
│ │ Claude Code     │ │ Claude Code     │             │
│ │ Modified: 2d ago│ │ Modified: 5d ago│             │
│ │ [Import] [Skip] │ │ [Import] [Skip] │             │
│ └─────────────────┘ └─────────────────┘             │
│                                                     │
│ ┌─────────────────┐ ┌─────────────────┐             │
│ │ flutter-dev     │ │ react-native    │             │
│ │ OpenCode        │ │ Cursor          │             │
│ │ ⚠️ Conflict      │ │ Modified: 1d ago │             │
│ │ [Resolve] [Skip] │ │ [Import] [Skip] │             │
│ └─────────────────┘ └─────────────────┘             │
│                                                     │
│ ──────────────────────────────────────────────────── │
│ [Import All] [Skip All]              [Cancel]       │
└─────────────────────────────────────────────────────┘
```

**Interactions:**
- Tap skill → Expand to show preview
- "Import" → Add to master registry
- "Skip" → Mark as skipped (don't show again)
- "Resolve" → Open conflict sheet
- "Import All" → Bulk import all non-conflicting

---

### 4. Conflict Detection

**Trigger:** When importing a skill that already exists in master registry

**Conflict Resolution Options:**
1. **Keep Existing** — Do nothing, keep master version
2. **Replace with New** — Overwrite master with discovered version
3. **Keep Both** — Rename: `skill-name (source-tool)`

**UI:** Sheet with side-by-side comparison:
```
┌──────────────────────┬──────────────────────┐
│ Current (master)     │ Discovered (Cursor)  │
├──────────────────────┼──────────────────────┤
│ Last modified: 5d    │ Last modified: 2d   │
│ Source: Claude Code  │ Source: Cursor       │
├──────────────────────┼──────────────────────┤
│ ## cm-tdd           │ ## cm-tdd            │
│ ## Description     │ ## Description       │
│ [Preview content]  │ [Preview content]   │
└──────────────────────┴──────────────────────┘
         [Keep Existing] [Replace] [Keep Both]
```

---

### 5. GreatDeployApp Integration

**Trigger:** On app launch, check if first-run discovery has completed:

```swift
// In GreatDeployApp.swift
@State private var showHarvestOnboarding = false

var body: some Scene {
    WindowGroup {
        ContentView()
            .task {
                await checkFirstRunDiscovery()
            }
    }
}

private func checkFirstRunDiscovery() async {
    let userDefaults = UserDefaults.standard
    let hasCompletedDiscovery = userDefaults.bool(forKey: "hasCompletedSkillDiscovery")
    
    if !hasCompletedDiscovery {
        showHarvestOnboarding = true
        await runBackgroundDiscovery()
        userDefaults.set(true, forKey: "hasCompletedSkillDiscovery")
    }
}
```

**Sequence:**
1. App launches → check `hasCompletedSkillDiscovery`
2. If false → show welcome banner "Discovering skills..."
3. Run `SkillsHarvesterService.harvestAllSkills()` in background
4. Cache results → Send notification
5. Next time user opens app → Show review prompt (if skills found)

---

## Security Considerations

1. **No Auto-Install:** Skills never auto-install to other tools without user review
2. **Content Validation:** Before importing, validate SKILL.md content doesn't contain:
   - Obvious malware patterns (exec, eval, shell injection)
   - Excessive API keys or secrets
3. **Audit Log:** Log all imports with timestamp + source tool to `~/.greatdeploy/audit-log.json`
4. **Keychain Safety:** Skills may reference secrets — show warning when skill requests secret access

---

## File Changes

### New Files:
```
GreatDeploy/
├── Services/
│   ├── SkillsHarvesterService.swift   # Discovery engine
│   └── HarvestNotificationService.swift # Notifications
├── Models/
│   ├── DiscoveredSkill.swift          # Discovery model
│   └── DiscoveryCache.swift          # Cache model
├── Views/
│   ├── SkillsReviewView.swift         # Review UI
│   └── ConflictResolutionView.swift   # Conflict sheet
└── Utilities/
    └── SkillContentValidator.swift    # Security checks
```

### Modified Files:
```
GreatDeploy/
├── GreatDeployApp.swift               # Add first-run logic
├── Services/
│   └── ServiceProtocols.swift         # Add harvester protocol
└── Views/
    └── HomeDashboardView.swift        # Add discovery status
```

---

## Error Handling

| Error | User Message | Recovery |
|-------|-------------|----------|
| No tools installed | "No AI tools detected. Install Claude Code, Cursor, or OpenCode first." | Show empty state with install links |
| Permission denied | "Notification permission required for alerts." | Fall back to in-app banner |
| Cache write failed | Silent | Retry with exponential backoff, max 3 attempts |
| Scan failed (tool) | "Failed to scan {tool}. Skipping." | Log error, continue with other tools |

---

## Testing Strategy

1. **Unit Tests:**
   - `SkillsHarvesterServiceTests`: Mock tools, verify all skills extracted
   - `DiscoveryCacheTests`: Round-trip encode/decode, version migration
   - `ConflictDetectionTests`: Verify duplicates detected correctly

2. **Integration Tests:**
   - `SkillImportFlowTests`: Full flow from discovery → cache → review → import

3. **UI Tests:**
   - Verify review grid displays correct count
   - Verify conflict sheet appears on duplicates
   - Verify bulk actions work correctly