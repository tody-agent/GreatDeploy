# Tasks: Skill Auto-Harvest Engine
Version: 1.0 | Date: 2026-05-18
Status: pending

## Task List

### Phase 1: Foundation (Models + Core Service)

- [ ] **Task 1.1**: Create `DiscoveredSkill` and `DiscoveryCache` models
  - File: `GreatDeploy/Models/DiscoveredSkill.swift`
  - Includes: id (content hash), name, description, content, sourceTool, sourcePath, lastModified
  - Includes: DiscoveryCache struct with version handling

- [ ] **Task 1.2**: Create `SkillsHarvesterService` protocol and implementation
  - File: `GreatDeploy/Services/SkillsHarvesterService.swift`
  - Protocol: `SkillsHarvesting` in ServiceProtocols.swift
  - Implement: scan all installed tools, build DiscoveredSkill array
  - Implement: cache to ~/.greatdeploy/discovery-cache.json
  - Implement: version-based cache invalidation

- [ ] **Task 1.3**: Add harvester protocol to ServiceProtocols.swift
  - File: `GreatDeploy/Services/ServiceProtocols.swift`
  - Add: `SkillsHarvesting` protocol
  - Add: `HarvestingError` enum

### Phase 2: Notification System

- [ ] **Task 2.1**: Create `HarvestNotificationService`
  - File: `GreatDeploy/Services/HarvestNotificationService.swift`
  - Protocol: `HarvestNotificationServicing`
  - Request authorization on first launch
  - Send notification with skill count + tool count
  - Category with "Review" action

- [ ] **Task 2.2**: Add notification protocol to ServiceProtocols.swift
  - File: `GreatDeploy/Services/ServiceProtocols.swift`
  - Add: `HarvestNotificationServicing` protocol
  - Add: `NotificationAuthorizationError` enum

### Phase 3: Review UI

- [ ] **Task 3.1**: Create `SkillsReviewView`
  - File: `GreatDeploy/Views/SkillsReviewView.swift`
  - States: loading, empty, ready, error
  - Grid layout with skill cards
  - Import/Skip buttons per skill
  - Bulk actions: Import All / Skip All
  - Skill preview on tap

- [ ] **Task 3.2**: Create `SkillCardView` component
  - File: `GreatDeploy/Views/Components/SkillCardView.swift`
  - Shows: name, description (truncated), source tool badge
  - Shows: last modified date
  - States: default, imported, conflict, skipped
  - Conflict badge with warning icon

- [ ] **Task 3.3**: Create `ConflictResolutionView`
  - File: `GreatDeploy/Views/ConflictResolutionView.swift`
  - Side-by-side comparison of existing vs new
  - Three resolution options with descriptions
  - Content preview (scrollable)
  - Confirm/Cancel buttons

### Phase 4: App Integration

- [ ] **Task 4.1**: Add first-run discovery logic to GreatDeployApp.swift
  - File: `GreatDeploy/GreatDeployApp.swift`
  - Check UserDefaults for `hasCompletedSkillDiscovery`
  - If false: run background harvest, update flag
  - Show welcome banner during discovery

- [ ] **Task 4.2**: Update HomeDashboardView to show discovery status
  - File: `GreatDeploy/Views/HomeDashboardView.swift`
  - Show "Skills discovered: X" badge if discovery complete
  - "Review Skills" button to open SkillsReviewView

- [ ] **Task 4.3**: Add harvest status to ServiceProtocols.swift
  - File: `GreatDeploy/Services/ServiceProtocols.swift`
  - Add: `HarvestStatus` enum (neverRun, running, completed, failed)
  - Add: computed property for pending review count

### Phase 5: Security + Testing

- [ ] **Task 5.1**: Create `SkillContentValidator`
  - File: `GreatDeploy/Utilities/SkillContentValidator.swift`
  - Check for exec/eval patterns
  - Check for shell injection patterns
  - Check for excessive secrets in content
  - Return validation result with warnings

- [ ] **Task 5.2**: Write unit tests for harvester
  - File: `GreatDeployTests/SkillsHarvesterServiceTests.swift`
  - Test: all tools scanned
  - Test: cache round-trip
  - Test: version migration

- [ ] **Task 5.3**: Write unit tests for conflict detection
  - File: `GreatDeployTests/ConflictDetectionTests.swift`
  - Test: duplicate detection by content hash
  - Test: same name different content
  - Test: same content different name

---

## Dependencies

```
Task 1.3 → Task 1.1, 1.2
Task 2.2 → Task 2.1
Task 3.2 → Task 3.1
Task 4.2 → Task 4.1, 3.1
Task 5.3 → Task 1.1
```

## Execution Order

1. Phase 1: All tasks in sequence (1.1 → 1.2 → 1.3)
2. Phase 2: Tasks 2.1 → 2.2 (can run parallel with 1.2)
3. Phase 3: Task 3.1, 3.2, 3.3 (3.2 depends on 3.1)
4. Phase 4: Tasks 4.1, 4.2, 4.3 (all depend on Phase 1-3)
5. Phase 5: Tasks 5.1, 5.2, 5.3 (independent, can run parallel)

## Estimated Time

- Phase 1: 3 hours
- Phase 2: 2 hours
- Phase 3: 4 hours
- Phase 4: 2 hours
- Phase 5: 3 hours
- **Total: ~14 hours**