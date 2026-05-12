
## 📄 File 1: `openspec/project.md`

```markdown
# GreatDeploy

> Native macOS menu bar app to switch your entire deploy identity
> (GitHub + Cloudflare) in one click — and stop pushing to the wrong account.

## Purpose

Developers who maintain multiple identities — personal, employer, freelance
clients, side projects — currently juggle credentials across many tools:
`~/.gitconfig`, macOS Keychain, SSH config, wrangler config, environment
variables. Switching context is manual, error-prone, and silent: the only
feedback that you used the wrong identity is a wrong-author commit, a leaked
token, or a push to the wrong organization.

GreatDeploy collapses all of that into a single concept — a **Profile** —
and exposes it from the macOS menu bar. One click reconfigures git,
Keychain, wrangler, and shell environment atomically. A repo-aware safety
guard blocks pushes when the active profile does not match the remote.

## Target users

- Solo developers maintaining personal + employer GitHub accounts
- Freelancers and agency engineers juggling 3+ client identities
- DevOps engineers operating across multiple Cloudflare accounts
- Indie hackers running several side projects under different orgs

## Non-goals (v1)

- Cross-platform support (Linux, Windows, web)
- Cloud sync of profiles between machines
- Team-shared profiles or organization-level management
- Adapters beyond GitHub and Cloudflare (deferred to post-v1)
- Auto-discovery of profiles from cloud providers
- Browser session switching (cookie management)

## Tech stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI + AppKit (`NSStatusItem` for menu bar)
- **Minimum OS**: macOS 13 Ventura
- **Secret storage**: macOS Keychain Services
- **Auto-update**: Sparkle 2.x
- **Distribution**: Homebrew Cask + direct download (notarized DMG)
- **CI**: GitHub Actions on `macos-14` with Xcode 15+

## Upstream forks

GreatDeploy stands on two MIT-licensed projects:

| Project | Role |
|---|---|
| [MinhOmega/GitAccountSwitcher](https://github.com/MinhOmega/GitAccountSwitcher) | Menu bar app foundation, Keychain pattern, git config writer |
| [sushaantu/CloudflareStatusBar](https://github.com/sushaantu/CloudflareStatusBar) | Cloudflare API client, wrangler config writer, multi-profile UI |

Both authors are credited in `NOTICES.md` and the in-app About panel.

## Architecture at a glance

```

┌─────────────────────────────────────────────────┐

│  Menu Bar UI (SwiftUI + NSStatusItem)           │

├─────────────────────────────────────────────────┤

│  SwitchEngine (transactional, atomic)           │

├──────────────┬──────────────┬───────────────────┤

│ GitHub       │ Cloudflare   │  │

│ Adapter      │ Adapter      │                   │

├──────────────┴──────────────┴───────────────────┤

│  ProfileStore (JSON) + KeychainManager          │

├─────────────────────────────────────────────────┤

│  SafetyGuard (pre-push hook + CLI)              │

└─────────────────────────────────────────────────┘

```

## Glossary

- **Profile**: a bundle of `{ GitHub identity, Cloudflare identity, scope rules, metadata }` representing one developer context.
- **Active Profile**: the profile currently applied across all configured adapters; there is at most one at any time.
- **Adapter**: a pluggable module that knows how to read, snapshot, apply, and revert the local state of one external service.
- **Scope rule**: a glob or regex that maps a working directory or git remote URL to an expected profile.
- **Switch**: the atomic operation of changing the Active Profile, including all adapter side effects.
- **Snapshot**: an opaque record produced by an adapter capturing pre-switch state, used for rollback on failure.
- **Push protection**: the safety feature that blocks `git push` when the active profile mismatches the remote.

## Conventions

- Spec-driven: every non-trivial change starts as a proposal under `openspec/changes/`.
- One change = one folder = one PR.
- Specs under `openspec/specs/` represent the **current** capability surface; they are updated when a change is archived.
- All secrets live in Keychain, never on disk in plaintext.
- All file writes are atomic (write to `.tmp`, then `rename`).
- All adapter operations are revertible.
```

---

## 📄 File 2: `openspec/changes/001-bootstrap-fork/proposal.md`

```markdown
# Change 001 — Bootstrap fork

## Why

Before designing anything new, we need a working SwiftUI menu bar app
skeleton with proven Keychain access and git config writing. Building
this from scratch would burn 1–2 weeks; forking `GitAccountSwitcher`
gives us a known-good foundation in one day. We also need the OpenSpec
scaffold in place so subsequent changes can be authored properly.

This change is intentionally narrow: no new features, no Cloudflare,
no UI redesign. The single success criterion is that the forked app
builds, runs, and switches a GitHub account exactly as the upstream
does — but under the GreatDeploy name and bundle identifier.

## What changes

- Fork `MinhOmega/GitAccountSwitcher` into the new repo `GreatDeploy`.
- Rename the Xcode project, scheme, product name, and bundle identifier
  to `com.<owner>.greatdeploy`.
- Replace user-facing strings: app name, About panel, window titles,
  default app icon (placeholder OK at this stage).
- Verify that the Keychain access group works under the new bundle id
  (Keychain items are namespaced by bundle id, so a fresh start is
  expected; no migration from the upstream app is required since
  there are no GreatDeploy users yet).
- Preserve the original `LICENSE` file unchanged.
- Add `NOTICES.md` crediting `MinhOmega/GitAccountSwitcher`.
- Add the `openspec/` directory scaffold with `project.md` and the
  initial capability spec stubs (profile-management, github-adapter,
  cloudflare-adapter, menu-bar-ui, safety-guard, secret-storage).
- Add a GitHub Actions workflow that builds the app on `macos-14`
  with Xcode 15+, runs unit tests, and uploads the `.app` artifact.
- Tag the first internal release as `v0.0.1-alpha`.

## Impact

- **Codebase**: net addition of the openspec scaffold; rename touches
  project files, Info.plist, asset catalog entries.
- **Users**: none — there are no users yet.
- **Migration**: none required.
- **License**: must remain MIT; must preserve original copyright notice.
- **Risk**: low. If the fork fails to build, the upstream still builds,
  so we have a known-good reference point to diff against.

## Out of scope

- Any Cloudflare functionality (handled in change 003).
- The unified Profile data model (handled in change 002).
- Custom app icon or branding polish (handled in change 006).
- Distribution via Homebrew (handled in change 006).
- Auto-update / Sparkle integration (handled in change 006).

## Acceptance

This change is done when:

1. `git clone && open *.xcodeproj && ⌘R` produces a running app whose
   menu bar item reads "GreatDeploy", not "GitAccountSwitcher".
2. Creating a GitHub account through the existing UI still updates
   `~/.gitconfig` and the macOS Keychain entry for `github.com`.
3. `openspec/` is committed with `project.md` and 6 capability spec
   stubs, even if the stubs are placeholders.
4. CI is green on `main`.
5. `v0.0.1-alpha` is tagged.
```

---

## 📄 File 3: `openspec/changes/002-unified-profile-model/proposal.md`

```markdown
# Change 002 — Unified profile model

## Why

`GitAccountSwitcher` models its core entity as a "GitHub account":
a record with a username, email, and PAT. `CloudflareStatusBar` models
its core entity as a "Cloudflare profile": a record with a display
name and an API token. These two models cannot represent the central
idea of GreatDeploy — a developer **context** that bundles both
identities together so that a single click reconfigures everything.

Without a unified model, we would end up with two parallel switchers
that the user has to operate independently, defeating the entire
premise of the product. The unified `Profile` is the keystone abstraction
that every later change (adapters, switch engine, safety guard, UI)
depends on, which is why we land it before porting the Cloudflare code.

## What changes

- Introduce a `Profile` value type that owns optional `GitHubIdentity`
  and optional `CloudflareIdentity` sub-records, plus shared metadata
  (id, name, color, tag, timestamps) and `ScopeRules` for the safety
  guard.
- Make every identity sub-record reference its secrets by Keychain
  reference only; raw token strings must never appear in the `Profile`
  struct nor in the persisted JSON.
- Rewrite `ProfileStore` to persist a list of `Profile` records as
  JSON to `~/Library/Application Support/GreatDeploy/profiles.json`,
  using atomic write (write-temp + rename).
- Rewrite `KeychainManager` so that every Keychain item is namespaced
  under `greatdeploy.<profileId>.<adapter>`, ensuring profile deletion
  can cleanly remove all associated secrets.
- Provide a one-shot migration: if a legacy `accounts.json` (from the
  upstream fork's data model) exists, convert each entry into a
  `Profile` with `github` populated and `cloudflare = nil`. Back up
  the legacy file as `accounts.json.bak` before deletion.
- Update the existing SwiftUI list view so it renders the new
  `Profile` collection rather than the old "account" collection.
  Profile editor UI for Cloudflare fields is **not** part of this
  change — it lands together with the Cloudflare adapter in 003.

## Impact

- **Breaking on-disk schema**: the legacy `accounts.json` is replaced
  by `profiles.json`. The migration runs at most once and is
  idempotent. A backup is always kept.
- **Keychain items**: existing legacy Keychain items are kept untouched
  but become orphaned. They will be referenced by the migrated profiles
  via their existing service/account keys, so no re-entry of secrets
  is required for migrating users.
- **UI churn**: any screen referring to "GitHub account" must be
  renamed to "Profile". This is mostly string changes.
- **Tests**: add unit tests for migration (happy path, corrupted file,
  empty file, file already migrated).
- **Risk**: medium. The migration must be defensive — a bad migration
  on first launch could lose user data. Always back up, never delete
  the backup automatically.

## Out of scope

- Implementing the Cloudflare adapter (change 003).
- The transactional `SwitchEngine` — for now, switching still applies
  only the GitHub adapter, just driven by the new Profile model
  (change 004 introduces the full engine).
- Push protection and scope rule enforcement (change 005); the
  `ScopeRules` field is added to the model now but is unused.
- Profile import/export UI (deferred).

## Acceptance

This change is done when:

1. The on-disk format is `profiles.json` with the documented schema.
2. A user who upgrades from `v0.0.1-alpha` sees their existing GitHub
   accounts appear as profiles, with secrets still working — no
   re-authentication required.
3. `profiles.json` contains zero secret material on inspection; every
   secret is referenced via a Keychain ref.
4. Migration is covered by unit tests including corrupted input.
5. The Profile list view renders correctly with at least 5 mixed
   profiles in a manual smoke test.
```

---

## 📄 File 4: `openspec/changes/003-cloudflare-adapter-port/proposal.md`

```markdown
# Change 003 — Port Cloudflare adapter from CloudflareStatusBar

## Why

`CloudflareStatusBar` already solves the hard parts of working with
Cloudflare from a native macOS app: API token verification against
`/user/tokens/verify`, listing accounts, writing wrangler's TOML
config, and storing API tokens in Keychain via a profile abstraction.
Re-implementing this from scratch would cost two to three weeks and
duplicate code that has already been tested by real users.

Porting the relevant subset — and adapting it to GreatDeploy's
`AdapterProtocol` — lets us deliver Cloudflare support in days
instead of weeks, while preserving the architectural separation we
need (one adapter per service, all driven by the switch engine).

## What changes

- Introduce `AdapterProtocol` as the contract every adapter conforms
  to: `name`, `snapshot()`, `apply(identity:)`, `revert(snapshot:)`,
  `verify()`. (The protocol itself ships now; change 004 adds the
  engine that orchestrates multiple adapters atomically.)
- Vendor the following modules from `sushaantu/CloudflareStatusBar`
  into `Adapters/Cloudflare/`:
  - `CloudflareAPI` — the HTTP client and response models.
  - `WranglerConfigWriter` — TOML serialization and atomic write to
    `~/.wrangler/config/default.toml`.
  - `KeychainProfile` — adapted to plug into GreatDeploy's
    namespaced `KeychainManager` from change 002 rather than its
    own store.
- Strip the upstream's UI surfaces that GreatDeploy does not need:
  Workers list, Pages list, KV/R2/D1/Queues browsers, deployment
  notifications, auto-refresh. The goal here is identity switching,
  not resource monitoring; monitoring features could return later
  as a separate change.
- Implement `CloudflareAdapter.apply(_:)` to:
  1. Write the API token + account id into wrangler config.
  2. Call `launchctl setenv CLOUDFLARE_API_TOKEN <token>` and
     `launchctl setenv CLOUDFLARE_ACCOUNT_ID <id>` so that GUI apps
     and newly spawned shells inherit them.
  3. Surface a warning if the system has the env var set via
     `.zshrc`/`.bashrc`, since those values would override ours in
     already-open terminals (this matches the upstream's known
     wrangler-vs-OAuth caveat).
- Implement `CloudflareAdapter.verify()` to hit `/user/tokens/verify`
  and return a green/red status with a human-readable message.
- Extend the profile editor UI added in change 002 with a Cloudflare
  section: API token field (secure), account selector populated by
  the verify call, optional default zone.
- Add `NOTICES.md` credit and license header to vendored files.

## Impact

- **Codebase**: roughly 1,500–2,000 lines of additional Swift under
  `Adapters/Cloudflare/`, much of it directly ported.
- **Network**: app will now make outbound HTTPS calls to
  `api.cloudflare.com` during profile creation, verification, and
  every switch.
- **Permissions**: no new entitlements; outbound networking is already
  permitted for the sandbox.
- **License**: vendored files retain their original MIT header
  alongside a GreatDeploy attribution line.
- **Risk**: low to medium. The upstream code is production-tested,
  but adapting `KeychainProfile` to our namespaced manager touches
  the secret-handling code path and warrants careful review.

## Out of scope

- The atomic switch engine and rollback (change 004) — for now,
  Cloudflare and GitHub adapters are applied sequentially, and a
  mid-switch failure can leave inconsistent state. This is a known
  temporary regression that 004 closes.
- Push protection (change 005).
- Restoring the monitoring UI (Workers/Pages/etc.). If revisited
  later, it would be a separate change proposal.

## Acceptance

This change is done when:

1. A user can create a profile that contains a Cloudflare API token,
   and the verify call returns a green status with the resolved
   account name displayed in the editor.
2. Switching to that profile causes `wrangler whoami` (run in a
   freshly opened terminal) to show the matching account email.
3. The Cloudflare API token never appears in `profiles.json` nor in
   any log file; only its Keychain reference does.
4. Deleting a profile removes both its GitHub and Cloudflare Keychain
   entries (verified via Keychain Access.app).
5. All vendored files carry both the upstream and GreatDeploy
   attribution headers, and `NOTICES.md` credits `sushaantu`.
```

---

## 📄 File 5: `openspec/changes/004-atomic-switch-engine/proposal.md`

```markdown
# Change 004 — Atomic switch engine

## Why

After change 003 the app can apply a GitHub identity and a Cloudflare
identity, but it does so by running each adapter independently and
sequentially. If the Cloudflare step fails after the GitHub step
already succeeded, the user is left in an inconsistent state: git
thinks they are profile B, wrangler still thinks they are profile A.
Inconsistent state is the exact failure mode this product was built
to eliminate, so it cannot stand as a permanent design.

A transactional switch engine — snapshot, apply, and on failure
revert in reverse order — restores the all-or-nothing guarantee that
the product promise depends on. It also gives us a single, audited
choke point through which every change to the user's local
environment must flow, which is critical for both safety and
debuggability.

## What changes

- Introduce a `SwitchEngine` actor that owns the switch lifecycle.
- Define `AdapterSnapshot` as an opaque, per-adapter record that
  captures whatever state the adapter needs to revert: a copy of
  `~/.gitconfig` for GitHub, a copy of `wrangler/config/default.toml`
  plus the previous launchctl env values for Cloudflare.
- Replace the existing sequential-apply code path with the engine's
  transaction:
  1. Resolve the ordered list of adapters that are configured for
     the target profile.
  2. For each adapter, capture a snapshot and apply the new identity.
  3. If any apply throws, walk the already-applied adapters in
     reverse and call `revert(snapshot:)` on each. Surface the
     original error to the UI.
  4. On success, persist the active profile id and broadcast a
     status update so the menu bar UI refreshes.
- Add an append-only audit log at
  `~/Library/Logs/GreatDeploy/audit.log` recording every switch
  attempt, outcome, and adapter timings. Logs never contain secrets.
- Expose a "Last switch" entry in the About panel showing timestamp,
  resulting profile name, and any non-fatal warnings (e.g. "env var
  override detected; restart your terminal").
- Define and document the failure surfaces the engine is responsible
  for handling: disk full, permission denied, `launchctl` missing,
  network verification failing after a successful local write.

## Impact

- **Codebase**: new `Core/SwitchEngine.swift`, plus snapshot/revert
  implementations added to each existing adapter. Net ~600 lines.
- **Behavior**: switching becomes slightly slower (extra disk reads
  for snapshots), but the latency increase should remain under 200ms
  on typical machines and is dwarfed by the network verify step.
- **Observability**: first audit log appears under `~/Library/Logs`.
  This is also the first time the app writes to a logs directory,
  so first-run code must create the directory if absent.
- **Compatibility**: the on-disk schema does not change. The active
  profile pointer (already present from 002) is now written only on
  successful switch.
- **Risk**: medium. The revert path is hard to test exhaustively;
  we will rely on injected fault adapters in unit tests to simulate
  apply-failure-after-N-adapters scenarios.

## Out of scope

- Push protection / pre-push hook (change 005).
- Onboarding flow and distribution (change 006).
- Concurrent switches — the engine serializes switches via actor
  isolation; queueing UI feedback for rapid double-clicks is a
  separate concern handled implicitly by the UI layer disabling
  the switch action while in flight.
- Partial-success modes (e.g. "apply GitHub only, leave Cloudflare
  alone"). For v1 a switch is all configured adapters or none.

## Acceptance

This change is done when:

1. A successful switch updates every configured adapter and persists
   the active profile id, atomically from the user's perspective.
2. A switch in which the Cloudflare adapter is forced to fail (via
   a test seam) leaves `~/.gitconfig` exactly as it was before the
   switch, byte-for-byte.
3. The audit log records both the successful and failed switches
   with adapter-level timings; no secret material appears in the log.
4. Unit tests cover: success, fail-on-first-adapter, fail-on-second-
   adapter, revert-itself-fails-gracefully.
5. Manual switch latency stays under 1 second end-to-end on a
   reference machine for a profile with both adapters configured.
```

---

## 📄 File 6: `openspec/changes/005-safety-guard-prepush/proposal.md`

```markdown
# Change 005 — Safety Guard: pre-push hook + drift detector

## Why

Every preceding change improves the **ergonomics** of switching
identities, but none of them prevent the actual failure mode that
motivates the product: a developer working under the wrong active
profile pushes commits to a remote that belongs to a different
identity. By the time the push lands, the wrong-author commits and
any embedded secrets are already in the remote's history.

A purely UI-based defense ("look at the menu bar before you push")
relies on human attention and will not hold under stress, late nights,
or context switching. We need a runtime defense that intercepts the
push at the git layer and refuses it when the remote does not match
the active profile's scope rules. Optionally, a working-directory
drift detector can prompt to switch when the user enters a repo whose
remote does not match the current profile, catching mistakes earlier.

## What changes

- Ship a small `greatdeploy` CLI binary (Swift, statically linked
  where possible) that the app installs to `/usr/local/bin` on user
  consent. The CLI's first subcommand is `verify-push <remote-name>
  <remote-url>`, which exits 0 (allow) or 1 (block) based on the
  active profile's scope rules.
- Ship a managed git pre-push hook template that simply forwards to
  the CLI. The app installs it by setting
  `git config --global core.hooksPath ~/.greatdeploy/hooks` and
  writing the template there. Existing user-installed global hooks
  are preserved by chaining if `core.hooksPath` was previously set;
  the original path is recorded in the app config for restoration.
- Add a Settings panel section "Push protection" with toggles to:
  - Install or uninstall the CLI binary.
  - Enable or disable the pre-push hook.
  - Configure the default behavior on missing scope rules
    (allow with warning, vs. block).
- Implement the matching logic: a push is allowed when the remote URL
  matches at least one entry in `ScopeRules.allowedRemoteRegex` for
  the active profile. When no scope rules are defined for a profile,
  the configured default behavior applies.
- Provide an explicit override: setting `GREATDEPLOY_FORCE=1` in the
  push command's environment bypasses the block but logs the override
  to the audit log together with the remote URL and timestamp.
- Add an opt-in, off-by-default **drift detector**: an `NSWorkspace`
  observer monitors focus changes; when the focused app is a known
  terminal (Terminal.app, iTerm2, Ghostty, Warp, Alacritty) and the
  terminal's cwd resolves to a git repo whose remote does not match
  the active profile, the app shows a notification with two actions:
  "Switch to <suggested>" and "Keep current". This feature is flagged
  experimental in v1 because reading terminal cwd reliably requires
  AppleScript or accessibility permissions, which we want to gate
  carefully.

## Impact

- **New CLI binary**: first time GreatDeploy installs anything outside
  its app bundle. The install action requires a privileged-helper
  prompt (we will use Apple's standard authorization flow rather than
  bundling a SMJobBless helper for v1; the user can also `cp` it
  manually with a copy button in Settings).
- **Global git config**: setting `core.hooksPath` affects every repo
  on the machine. We must preserve and restore any prior value, and
  the uninstall path must be reliable.
- **Privacy**: the drift detector reads terminal state. It is opt-in
  and disabled by default; documentation must make the data flow
  explicit (everything stays on-device, no network).
- **User trust**: a false-positive block (refusing a legitimate push)
  is more painful than a false-negative miss, so the default behavior
  on missing scope rules is "allow with a visible warning", not block.
- **Risk**: medium-high. The pre-push hook is a hot path; if our CLI
  hangs or crashes, the user cannot push. The CLI must therefore have
  an aggressive internal timeout (e.g. 300ms) and fail-open with a
  visible warning if it cannot decide in time.

## Out of scope

- Pre-commit hooks (commit-time identity check). Push-time is the
  right cut for v1 because the rewrite cost of a wrong-author commit
  before push is low.
- Server-side enforcement (e.g. GitHub branch protection rules).
- Hook chaining for repo-local hooks that conflict with our global
  hook (left to user via documentation).
- Cloudflare-side guard (e.g. blocking `wrangler deploy` to wrong
  account). Possible future change.
- Telemetry of how often the guard fires.

## Acceptance

This change is done when:

1. With push protection on and a profile whose scope rules disallow
   the remote, `git push` is blocked with a clear banner naming the
   active profile, the mismatched remote, and the suggested switch.
2. With push protection on and matching scope rules, push proceeds
   without measurable user-visible latency.
3. `GREATDEPLOY_FORCE=1 git push ...` allows the push and writes a
   single audit log entry describing the override.
4. Toggling push protection off restores any prior `core.hooksPath`
   value verbatim.
5. The CLI's `verify-push` subcommand returns within 300ms in 99%
   of measured runs on the reference machine, and fails open with a
   warning if it cannot.
6. The drift detector is gated behind an opt-in toggle and a
   permissions prompt; if the toggle is off, no terminal observation
   occurs.
```

---

## 📄 File 7: `openspec/changes/006-onboarding-and-distribution/proposal.md`

```markdown
# Change 006 — Onboarding wizard + Homebrew distribution

## Why

The features built in changes 001–005 are only valuable if a new user
can reach "first successful switch" quickly and trust the binary they
just installed. Both upstream forks ship via Homebrew Cask and offer
guided first-run experiences; matching that bar is the minimum for a
credible v1 release.

Equally important, the first-run experience is the single moment when
we can transform a user's existing scattered identity (their current
`~/.gitconfig`, any wrangler login they already have) into a clean
first profile. If we miss this window, the user has to manually
re-enter information that is already on their machine, and adoption
drops sharply. Onboarding is therefore not cosmetic — it is the
primary acquisition path.

## What changes

- Add a four-step SwiftUI onboarding flow that runs on first launch
  and is reachable later from the Help menu:
  1. **Welcome & permissions** — explain what the app does in one
     sentence, request notification permission, explain that Keychain
     will be used.
  2. **Import existing identity** — read `~/.gitconfig` for
     `user.name`, `user.email`, `user.signingkey`; run `wrangler
     whoami` if wrangler is installed; present the discovered values
     as the starting point for the first profile.
  3. **Create first profile** — prefilled form with the imported
     values, asking only for a profile name, color, and optionally a
     GitHub PAT and Cloudflare API token if not already discoverable.
  4. **Enable push protection (optional)** — explain the safety guard
     and offer to install the CLI + hook. Default is **on** but can
     be skipped.
- Integrate Sparkle 2.x for auto-update, using an `appcast.xml`
  hosted on the project's GitHub Pages site. Generate Sparkle signing
  keys and store the private key only in CI secrets.
- Set up the Homebrew tap repository so the install command becomes:
  `brew install --cask <owner>/greatdeploy/greatdeploy`. A GitHub
  Actions workflow on release publishes the cask formula update.
- Notarize the release build with Apple Developer ID via `xcrun
  notarytool` in CI. The notarization credentials live in repo
  secrets; the workflow staples the ticket and uploads the DMG.
- Build the public README with: a one-line value proposition, an
  animated GIF demo of a switch, install instructions, security
  notes (Keychain, no telemetry by default), credits to the two
  upstream projects, and an FAQ.
- Add a minimal landing page on GitHub Pages with a download button,
  the appcast feed, and the same content as the README's first half.

## Impact

- **First release artifact**: a notarized, stapled DMG plus a
  Homebrew cask formula. This is the first time the project produces
  a user-facing binary outside of CI artifacts.
- **CI complexity**: release workflow grows to include codesigning,
  notarization, appcast generation, and tap-formula PRs. Estimated
  one-time setup cost: 1–2 days, mostly Apple Developer account
  plumbing.
- **Privacy**: README and onboarding must clearly state that no
  telemetry is collected. (We may add opt-in anonymous version pings
  later, but not in v1.)
- **Maintenance**: every future release must go through the same
  notarize + tap-update flow. This is automated but adds a hard
  dependency on Apple's notarization service being up at release time.
- **Risk**: low for code; medium for process. Notarization rejections
  are the most common failure here and usually stem from entitlements
  mismatches; the dry-run notarization in a pre-release workflow
  should catch them.

## Out of scope

- Mac App Store distribution. Sandbox restrictions there would block
  the Keychain access patterns and `launchctl setenv` calls we rely
  on. Direct distribution + Homebrew is the right v1 channel.
- Localization. The app ships English-only in v1.
- A paid tier or licensing system. v1 is fully MIT, free, and
  open source.
- Cloud sync, account creation flows, or login on the marketing site.
- A Sparkle "delta updates" optimization. Full-binary updates are
  acceptable at our binary size.

## Acceptance

This change is done when:

1. A clean macOS account with no GreatDeploy data installs the app
   via `brew install --cask` and reaches a successful first switch
   in under 3 minutes without reading external documentation.
2. The shipped DMG passes `spctl --assess --type execute` with no
   warnings.
3. Sparkle correctly detects and offers an update when a newer
   version is published to the appcast.
4. The README renders cleanly on GitHub with a working demo GIF and
   prominent credits to `MinhOmega/GitAccountSwitcher` and
   `sushaantu/CloudflareStatusBar`.
5. A `v1.0.0` tag exists; the corresponding GitHub Release contains
   the notarized DMG; the Homebrew tap points to it.
6. The onboarding flow is reachable again later via Help → "Show
   Onboarding…", so users can re-run import if they reinstall.
```

---

## ✅ Tóm tắt

Bạn vừa có đầy đủ 7 file:

* `openspec/project.md` — single source of truth của dự án
* 6 file `proposal.md` cho changes 001–006, mỗi file tự đứng được, có cấu trúc nhất quán (Why → What → Impact → Out of scope → Acceptance)

**Cách dùng tiếp theo:**

1. Tạo repo `GreatDeploy` rỗng, paste 7 file vào đúng đường dẫn như trên, commit `chore: bootstrap openspec scaffold`.
2. Bắt đầu với change 001 — tạo branch `change/001-bootstrap-fork`, fork code base, mở PR.
3. Khi PR merge → tạo file `tasks.md` (checklist) và `design.md` (nếu cần) bên cạnh `proposal.md`, rồi archive vào `openspec/changes/archive/YYYY-MM-DD-001-bootstrap-fork/` khi đóng.

Khi bạn sẵn sàng, mình có thể viết tiếp:

* Bộ `tasks.md` + `design.md` cho change 002 và 004 (hai change technical-heavy nhất), hoặc
* Skeleton code Swift cho `Profile`, `ProfileStore`, `AdapterProtocol`, `SwitchEngine` để bạn bắt đầu Phase 1 ngay.

Bạn muốn đi tiếp hướng nào?
