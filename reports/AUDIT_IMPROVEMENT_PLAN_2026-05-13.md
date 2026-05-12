# Great Deploy Audit & Improvement Plan - 2026-05-13

## Scope

Reviewed the macOS SwiftUI app in `/Volumes/Data/Tools/Great Deploy` using the Build macOS Apps guidance for build/run/debug and SwiftUI desktop patterns.

Evidence gathered:
- Project discovery: `GreatDeploy.xcodeproj`, scheme `GreatDeploy`.
- Test command: `xcodebuild test -project GreatDeploy.xcodeproj -scheme GreatDeploy -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO`.
- Result: **passed**, 6 tests, 0 failures.

## Current Strengths

- The app already uses a clear SwiftUI + service layer structure: Models, Services, Views, Utilities, Tests.
- Account tokens are intentionally excluded from `DevProfile` Codable storage and moved into Keychain-only storage.
- Git command execution uses `Process` with argument arrays, a sanitized environment, validation, and timeouts.
- Account switching has a transaction-style rollback path for GitHub credentials, Cloudflare credentials, git config, and active account state.
- XcodeGen is configured, which keeps project file drift under control.

## Key Findings

### P0 - Signing and entitlement path is incomplete

`project.yml` has `CODE_SIGN_ENTITLEMENTS` configured, but `DEVELOPMENT_TEAM` is empty. The test build with signing disabled produced:

> GreatDeploy isn't code signed but requires entitlements. It is not possible to add entitlements to a binary without signing it.

Impact: local unsigned builds can pass tests while not exercising the actual entitlement/runtime shape needed for a production macOS app.

Recommended fix:
- Add a signed Debug/Release path for developer machines.
- Keep a separate unsigned CI test path if needed.
- Add a release validation command that builds with signing enabled.

### P1 - Main-thread blocking and Security diagnostics

The test run emitted Security framework performance diagnostics warning that a method should not be called on the main thread. The likely hotspots are synchronous Keychain/Security and process calls reachable from `AccountStore` and `CloudflareAdapter`.

Recommended fix:
- Move Keychain and launchctl/Wrangler file operations behind async service methods that execute off the main actor.
- Remove `@MainActor` from `CloudflareAdapter` and isolate only UI state updates in `AccountStore`.
- Add tests for cancellation/timeouts and failure propagation.

### P1 - Cloudflare token persistence writes plaintext config

`CloudflareAdapter` writes `api_token = "<token>"` into `~/.wrangler/config/default.toml`.

Impact: this undermines the app's Keychain-first security model. It may be necessary for Wrangler compatibility, but it should be explicit, opt-in, and reversible.

Recommended fix:
- Prefer `launchctl setenv` or process-scoped env where possible.
- If writing Wrangler config remains required, add a user-facing warning, file permissions check, atomic write, backup/restore, and token redaction in diagnostics.
- Add tests around TOML escaping so quotes/newlines cannot corrupt config.

### P1 - Menu bar and settings navigation are not fully aligned

`SettingsWindowView` defines `.account` and `.addAccount` routes, but the sidebar only exposes Home and Settings. Account navigation exists indirectly from `HomeDashboardView`.

Impact: the app works, but the navigation model is a little hidden and less native than it could be for repeated desktop use.

Recommended fix:
- Put profile rows directly in the sidebar using native source-list rows.
- Keep switching action explicit and reversible, not only triggered by selection changes.
- Reserve the detail pane for profile details, validation status, and actions.

### P2 - Test coverage is too shallow for the risk surface

Current tests cover validation, secret scanning, and view instantiation. They do not cover account switching, rollback, Keychain failures, Git config failures, Cloudflare behavior, or GitHub CLI parsing.

Recommended fix:
- Introduce protocols for GitConfig, Keychain, GitHub CLI, and Cloudflare services so `AccountStore` can be unit-tested with fakes.
- Add failure matrix tests for partial account switch rollback.
- Add parsing and validation tests for GitHub CLI auth status.

### P2 - Developer run loop can be made smoother

The repo has `test_gate.sh`, but no project-local `script/build_and_run.sh` or Codex Run action yet.

Recommended fix:
- Add `script/build_and_run.sh` for kill/build/run/verify.
- Add `.codex/environments/environment.toml` pointing to the script.
- Keep release install separate from local debug run.

## Roadmap

### Phase 1 - Stabilize Production Build

Goal: make the app's build output match how users will actually run it.

Tasks:
- Configure signing team or document local signing setup.
- Add signed Debug and Release build commands.
- Update `test_gate.sh` to support Apple Silicon by default and avoid hardcoded `arch=x86_64`.
- Add a release build check that fails if entitlements are present but signing is disabled.

Acceptance:
- `xcodebuild test` passes on arm64.
- signed Release build succeeds.
- no entitlement warning in signed builds.

### Phase 2 - Isolate Services for Reliability Tests

Goal: make account switching testable without touching real Keychain, git config, or user Cloudflare files.

Tasks:
- Define small protocols for Keychain, Git config, GitHub CLI, and Cloudflare operations.
- Inject services into `AccountStore`.
- Add fake service implementations in tests.
- Test successful switch, missing token, Git config failure rollback, Cloudflare failure rollback, and duplicate account rejection.

Acceptance:
- At least 15 focused unit tests around account switching and persistence.
- Rollback behavior verified without mutating the developer machine.

### Phase 3 - Security Hardening

Goal: preserve the Keychain-first promise across GitHub and Cloudflare.

Tasks:
- Review whether plaintext Wrangler config is necessary.
- If necessary, make it opt-in and use secure file permissions.
- Escape TOML values safely.
- Redact usernames/tokens in logs where appropriate.
- Add tests for Cloudflare config write/clear behavior in a temp HOME.

Acceptance:
- No token is written to disk unless the user explicitly enables Wrangler config sync.
- Secret scan covers generated config examples and logs.

### Phase 4 - Native macOS UX Polish

Goal: make the app feel like a small, fast macOS utility rather than an onboarding-heavy page.

Tasks:
- Move profiles into the sidebar.
- Replace hardcoded "GitHub CLI Installed" with live CLI status.
- Add toolbar/commands for Add Profile, Switch Profile, Refresh Status, and Open Settings.
- Add keyboard shortcuts for high-frequency actions.
- Revisit window sizing: allow resizing beyond fixed content size where useful.

Acceptance:
- A user can add, inspect, switch, and edit profiles from predictable macOS navigation.
- Long account names remain readable in sidebar/menu bar without layout pressure.

### Phase 5 - Distribution Readiness

Goal: prepare for trusted installation outside Xcode.

Tasks:
- Add release packaging script.
- Add notarization checklist or script.
- Validate Launch at Login behavior if it is still a product requirement.
- Add a manual smoke checklist for first launch, Keychain prompt, account switch, quit/relaunch, and delete account.

Acceptance:
- Release app can be built, signed, installed, launched, and smoke-tested consistently.

