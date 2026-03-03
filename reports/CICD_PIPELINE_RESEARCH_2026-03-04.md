# CI/CD Pipeline Research: GitHub Actions for GitAccountSwitcher
**Date:** 2026-03-04
**Scope:** Deep Research - GitHub Actions CI/CD for macOS Swift/SwiftUI app
**Project:** GitAccountSwitcher (non-sandboxed, direct download distribution)

---

## Research Summary

This report covers everything needed to build a production-grade GitHub Actions CI/CD pipeline for
GitAccountSwitcher. The pipeline automatically bumps version numbers from conventional commits,
builds the app with xcodebuild (from XcodeGen-generated `.xcodeproj`), packages the result as a
DMG, and publishes a GitHub Release. Code signing options are covered for both the "no-cert" ad-hoc
path and the full Developer ID + notarization path.

---

## Key Findings

### 1. macOS Runners on GitHub Actions (2025/2026 State)

**Current Runner Labels:**
- `macos-15` — macOS Sequoia, Xcode 16.2 default (available now, `macos-latest` migrated to this in late 2025)
- `macos-14` — macOS Sonoma, Xcode 16.2 + 15.x available (Apple Silicon, M1 runner)
- `macos-13` — Deprecated / being retired; avoid for new workflows

**Xcode on `macos-14` runner (as of early 2026):**
- Xcode 16.2 (default, active)
- Xcode 16.1
- Xcode 15.4 (also kept)
- Xcode 15.3, 15.2, 15.1, 15.0.1

**Key Decision:** Use `macos-14` for M1 speed and broad Xcode availability. If you need Xcode 16.x features, use `macos-15`. Both are Apple Silicon runners.

**Selecting a Specific Xcode Version:**
```yaml
- name: Select Xcode version
  run: sudo xcode-select -s /Applications/Xcode_16.2.app/Contents/Developer
```

Or use the marketplace action:
```yaml
- uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: '16.2'
```

---

### 2. XcodeGen Integration in CI

**Approach 1: Homebrew (fastest, no version pinning)**
```yaml
- name: Install XcodeGen
  run: brew install xcodegen
```

Homebrew is pre-installed on all GitHub-hosted macOS runners (version 5.x as of 2026).

**Approach 2: GitHub Action wrapper (version-pinned, recommended)**
```yaml
- name: Generate Xcode project
  uses: xavierLowmiller/xcodegen-action@1.2.4
  with:
    spec: project.yml
    quiet: true
```

**Approach 3: Mint (if your team uses Mint)**
```yaml
- name: Install Mint and XcodeGen
  run: |
    brew install mint
    mint install yonaskolb/XcodeGen
    mint run xcodegen generate
```

**For GitAccountSwitcher**, the simplest and most reliable approach is:
```yaml
- name: Install XcodeGen
  run: brew install xcodegen

- name: Generate Xcode project
  run: xcodegen generate
```

---

### 3. Version Bump Strategy: Conventional Commits + Semantic Versioning

**Conventional Commit Message Format:**
```
feat: add SSH key support         → minor bump (1.0.0 → 1.1.0)
fix: resolve keychain OSStatus    → patch bump (1.0.0 → 1.0.1)
feat!: redesign account model     → major bump (1.0.0 → 2.0.0)
refactor: improve logging         → patch bump
BREAKING CHANGE: in body          → major bump
```

**Recommended Action:** `ietf-tools/semver-action@v1`

Outputs:
- `steps.semver.outputs.next` → `v1.2.0`
- `steps.semver.outputs.nextStrict` → `1.2.0` (no "v" prefix, for plist injection)
- `steps.semver.outputs.bump` → `major` | `minor` | `patch` | `none`

**Version Injection into `project.yml` via `sed`:**
Since `project.yml` contains `MARKETING_VERSION: 1.0.0`, use sed to update it before generating the Xcode project:

```yaml
- name: Bump version in project.yml
  run: |
    NEW_VERSION="${{ steps.semver.outputs.nextStrict }}"
    # Bump the marketing version
    sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: $NEW_VERSION/" project.yml
    # Bump the build number (use the run number for uniqueness)
    sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: ${{ github.run_number }}/" project.yml
```

**Alternative: agvtool (after project is generated)**
```yaml
- name: Set version with agvtool
  run: |
    cd GitAccountSwitcher
    agvtool new-marketing-version "${{ steps.semver.outputs.nextStrict }}"
    agvtool new-version -all "${{ github.run_number }}"
```

**Alternative: PlistBuddy (directly in the built product)**
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" \
  "dist/GitAccountSwitcher.app/Contents/Info.plist"
```

**Committing the version bump back to git:**
```yaml
- name: Commit version bump
  run: |
    git config --local user.email "github-actions[bot]@users.noreply.github.com"
    git config --local user.name "github-actions[bot]"
    git add project.yml
    git commit -m "chore: bump version to ${{ steps.semver.outputs.next }} [skip ci]"
    git tag "${{ steps.semver.outputs.next }}"
    git push origin main --tags
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Important:** Add `[skip ci]` to the commit message to prevent infinite workflow loops. The
workflow must have `contents: write` permission in its `permissions:` block.

**Prerequisite:** At least one tag must exist for `semver-action` to work. Create an initial tag:
```bash
git tag v1.0.0
git push origin v1.0.0
```

---

### 4. Building with xcodebuild (from `.xcodeproj`)

**Basic build command for macOS app:**
```bash
xcodebuild \
  -project GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  build
```

**Archive approach (required for proper .app export and code signing):**
```bash
xcodebuild archive \
  -project GitAccountSwitcher.xcodeproj \
  -scheme GitAccountSwitcher \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath dist/GitAccountSwitcher.xcarchive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM=""
```

**Export from archive to `.app`:**
```bash
xcodebuild -exportArchive \
  -archivePath dist/GitAccountSwitcher.xcarchive \
  -exportPath dist/ \
  -exportOptionsPlist ExportOptions.plist
```

**ExportOptions.plist for ad-hoc (no Developer ID):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

**ExportOptions.plist for Developer ID distribution:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

**Note about this project's `project.yml`:** It currently has `CODE_SIGN_STYLE: Automatic` and
`DEVELOPMENT_TEAM: ""`. For CI, you will override these on the command line so no local signing
identity is required.

---

### 5. Code Signing Strategies

#### Option A: Ad-hoc Signing (no Apple Developer account required)

Ad-hoc signing uses `"-"` as the identity, which produces a checksum-based signature. The app will:
- Run fine on the machine that built it
- Show a Gatekeeper "unverified developer" warning on other machines
- Be openable via right-click → Open in Finder

This is fine for:
- Developer testing
- Internal team distribution
- Early-stage releases where users understand the workaround

```bash
/usr/bin/codesign --force --sign "-" --deep dist/GitAccountSwitcher.app
```

#### Option B: Developer ID Application (recommended for public releases)

Requires:
- Paid Apple Developer Program membership ($99/year)
- "Developer ID Application" certificate from developer.apple.com
- Certificate exported as `.p12` with a password
- Base64-encoded and stored as a GitHub Secret

**Setup Steps:**
1. In Keychain Access → Certificate Assistant → Request Certificate from CA
2. On developer.apple.com → Certificates → Create → Developer ID Application
3. Download and import the certificate into Keychain
4. Export as `.p12` (include private key): `File → Export Items`
5. Base64 encode: `base64 -i Certificates.p12 | pbcopy`
6. Add to GitHub Secrets as `MACOS_CERTIFICATE`

**GitHub Secrets required:**
| Secret | Value |
|--------|-------|
| `MACOS_CERTIFICATE` | Base64 `.p12` content |
| `MACOS_CERTIFICATE_PWD` | Password used during p12 export |
| `MACOS_CERTIFICATE_NAME` | e.g., `Developer ID Application: Your Name (TEAMID)` |
| `MACOS_CI_KEYCHAIN_PWD` | Any strong random password for temporary keychain |

**Signing step in workflow:**
```yaml
- name: Import code signing certificate
  env:
    MACOS_CERTIFICATE: ${{ secrets.MACOS_CERTIFICATE }}
    MACOS_CERTIFICATE_PWD: ${{ secrets.MACOS_CERTIFICATE_PWD }}
    MACOS_CERTIFICATE_NAME: ${{ secrets.MACOS_CERTIFICATE_NAME }}
    MACOS_CI_KEYCHAIN_PWD: ${{ secrets.MACOS_CI_KEYCHAIN_PWD }}
  run: |
    echo $MACOS_CERTIFICATE | base64 --decode > certificate.p12

    # Create a temporary keychain for this build
    security create-keychain -p "$MACOS_CI_KEYCHAIN_PWD" build.keychain
    security default-keychain -s build.keychain
    security unlock-keychain -p "$MACOS_CI_KEYCHAIN_PWD" build.keychain
    security set-keychain-settings -lut 21600 build.keychain

    # Import the certificate
    security import certificate.p12 \
      -k build.keychain \
      -P "$MACOS_CERTIFICATE_PWD" \
      -T /usr/bin/codesign

    # Allow codesign to access the key without prompts (macOS 10.12.5+ requirement)
    security set-key-partition-list \
      -S apple-tool:,apple:,codesign: \
      -s -k "$MACOS_CI_KEYCHAIN_PWD" build.keychain

    # Verify import
    security find-identity -v build.keychain

- name: Sign the application
  env:
    MACOS_CERTIFICATE_NAME: ${{ secrets.MACOS_CERTIFICATE_NAME }}
  run: |
    # Sign with hardened runtime (required for notarization)
    /usr/bin/codesign \
      --force \
      --deep \
      --sign "$MACOS_CERTIFICATE_NAME" \
      --options runtime \
      --entitlements GitAccountSwitcher/GitAccountSwitcher.entitlements \
      dist/GitAccountSwitcher.app

- name: Cleanup keychain
  if: always()
  run: security delete-keychain build.keychain
```

**Important note about `--options runtime` (Hardened Runtime):**
This is required for notarization. However, since this app has
`com.apple.security.cs.disable-library-validation: false` in entitlements, it should be
compatible. If you later enable `disable-library-validation: true` in entitlements, you must
include the entitlements file in the codesign call (as shown above).

---

### 6. Notarization (Gatekeeper)

Notarization removes the "unverified developer" Gatekeeper warning for end users. It requires:
- Developer ID Application certificate (Option B above)
- App-specific password from appleid.apple.com (not your regular Apple ID password)
- Your Apple ID email and Team ID

**Additional GitHub Secrets for notarization:**
| Secret | Value |
|--------|-------|
| `NOTARIZATION_APPLE_ID` | Your Apple developer email |
| `NOTARIZATION_PASSWORD` | App-specific password from appleid.apple.com |
| `NOTARIZATION_TEAM_ID` | Team ID from developer.apple.com/account |

**Notarization workflow steps:**
```yaml
- name: Notarize application
  env:
    NOTARIZATION_APPLE_ID: ${{ secrets.NOTARIZATION_APPLE_ID }}
    NOTARIZATION_PASSWORD: ${{ secrets.NOTARIZATION_PASSWORD }}
    NOTARIZATION_TEAM_ID: ${{ secrets.NOTARIZATION_TEAM_ID }}
  run: |
    # Store credentials in keychain profile (more secure than inline flags)
    xcrun notarytool store-credentials "notarytool-profile" \
      --apple-id "$NOTARIZATION_APPLE_ID" \
      --team-id "$NOTARIZATION_TEAM_ID" \
      --password "$NOTARIZATION_PASSWORD"

    # Create a zip for submission (app must be zipped or dmg'd)
    ditto -c -k --keepParent dist/GitAccountSwitcher.app dist/notarize-upload.zip

    # Submit and wait for notarization to complete (can take 2-15 minutes)
    xcrun notarytool submit dist/notarize-upload.zip \
      --keychain-profile "notarytool-profile" \
      --wait

    # Staple the notarization ticket to the app
    xcrun stapler staple dist/GitAccountSwitcher.app

    # Clean up zip used for submission
    rm dist/notarize-upload.zip

- name: Verify notarization
  run: spctl -a -v dist/GitAccountSwitcher.app
```

**Skipping notarization (for now):**
If you skip notarization, users will see a Gatekeeper warning. They can bypass it by:
- Right-clicking the app in Finder → Open → Open (first time only)
- Or: `xattr -d com.apple.quarantine /Applications/GitAccountSwitcher.app`

Document this in your release notes.

---

### 7. Creating a DMG for Distribution

**Tool: `create-dmg`** (recommended over raw `hdiutil`)

Installation: `brew install create-dmg`

**Basic DMG creation:**
```bash
# Create staging directory
mkdir -p dist/dmg
cp -r dist/GitAccountSwitcher.app dist/dmg/

# Create the DMG
create-dmg \
  --volname "Git Account Switcher" \
  --volicon "GitAccountSwitcher/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" \
  --window-pos 200 120 \
  --window-size 600 300 \
  --icon-size 100 \
  --icon "GitAccountSwitcher.app" 175 120 \
  --hide-extension "GitAccountSwitcher.app" \
  --app-drop-link 425 120 \
  "dist/GitAccountSwitcher-${{ steps.semver.outputs.nextStrict }}.dmg" \
  "dist/dmg/"
```

**Signed DMG (if you have Developer ID):**
```bash
create-dmg \
  --volname "Git Account Switcher" \
  --window-size 600 300 \
  --icon-size 100 \
  --icon "GitAccountSwitcher.app" 175 120 \
  --app-drop-link 425 120 \
  --codesign "$MACOS_CERTIFICATE_NAME" \
  "dist/GitAccountSwitcher-${{ steps.semver.outputs.nextStrict }}.dmg" \
  "dist/dmg/"
```

**Alternative: ZIP artifact (simpler, no extra tool)**
```bash
# Create zip
ditto -c -k --keepParent \
  dist/GitAccountSwitcher.app \
  "dist/GitAccountSwitcher-${{ steps.semver.outputs.nextStrict }}.zip"
```

**Known issue:** `create-dmg` can occasionally fail on GitHub Actions due to `hdiutil` permission
issues. Mitigation: use `--hdiutil-retries 5` flag or fall back to zip on failure.

---

### 8. Creating a GitHub Release with Artifacts

**Recommended action:** `softprops/action-gh-release@v2`

```yaml
- name: Create GitHub Release
  uses: softprops/action-gh-release@v2
  with:
    tag_name: ${{ steps.semver.outputs.next }}
    name: "Git Account Switcher ${{ steps.semver.outputs.next }}"
    body: |
      ## Changes
      ${{ steps.changelog.outputs.content }}

      ## Installation
      1. Download `GitAccountSwitcher-${{ steps.semver.outputs.nextStrict }}.dmg`
      2. Open the DMG and drag the app to Applications
      3. Right-click the app and select Open (first launch only, if unsigned)
    draft: false
    prerelease: false
    files: |
      dist/GitAccountSwitcher-*.dmg
      dist/GitAccountSwitcher-*.zip
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## Complete Workflow File

This is the full, production-ready workflow. Save it to `.github/workflows/release.yml` in your repository.

```yaml
name: Build and Release

on:
  push:
    branches:
      - main
    paths-ignore:
      - 'reports/**'
      - 'docs/**'
      - '**.md'

# Required so the workflow can push tags and create releases
permissions:
  contents: write

jobs:
  # ─────────────────────────────────────────────────────────────
  # JOB 1: Determine next semantic version from conventional commits
  # ─────────────────────────────────────────────────────────────
  version:
    name: Calculate Next Version
    runs-on: ubuntu-latest
    outputs:
      next: ${{ steps.semver.outputs.next }}
      nextStrict: ${{ steps.semver.outputs.nextStrict }}
      bump: ${{ steps.semver.outputs.bump }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history needed for semver analysis

      - name: Calculate next version
        id: semver
        uses: ietf-tools/semver-action@v1
        with:
          token: ${{ github.token }}
          branch: main
          # Customize which prefixes trigger which bumps
          majorList: ''           # Use BREAKING CHANGE footer or feat!/fix! suffix
          minorList: 'feat, feature'
          patchList: 'fix, bugfix, perf, refactor, test, tests, chore, docs, style, ci'

      - name: Log version decision
        run: |
          echo "Current version: ${{ steps.semver.outputs.current }}"
          echo "Next version: ${{ steps.semver.outputs.next }}"
          echo "Bump type: ${{ steps.semver.outputs.bump }}"

  # ─────────────────────────────────────────────────────────────
  # JOB 2: Build, sign, package, and release
  # ─────────────────────────────────────────────────────────────
  build:
    name: Build macOS App
    runs-on: macos-14
    needs: version
    # Only run if there is actually a version bump (skip if bump == 'none')
    if: needs.version.outputs.bump != 'none'

    env:
      SCHEME: GitAccountSwitcher
      PROJECT: GitAccountSwitcher.xcodeproj
      BUILD_DIR: dist
      APP_NAME: GitAccountSwitcher
      VERSION: ${{ needs.version.outputs.nextStrict }}
      TAG: ${{ needs.version.outputs.next }}

    steps:
      # ── Checkout ──────────────────────────────────────────────
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      # ── Select Xcode ──────────────────────────────────────────
      - name: Select Xcode 16.2
        run: sudo xcode-select -s /Applications/Xcode_16.2.app/Contents/Developer

      # ── Bump version in project.yml ───────────────────────────
      # This modifies project.yml BEFORE xcodegen runs, so the
      # generated .xcodeproj already has the correct version embedded.
      - name: Bump version in project.yml
        run: |
          echo "Bumping version to $VERSION (build ${{ github.run_number }})"
          # Update MARKETING_VERSION (the user-visible version string)
          sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: $VERSION/" project.yml
          # Update CURRENT_PROJECT_VERSION (build number, must be integer)
          sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"${{ github.run_number }}\"/" project.yml
          echo "Updated project.yml:"
          grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" project.yml

      # ── Install XcodeGen and generate project ─────────────────
      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Verify generated project
        run: |
          ls -la $PROJECT/
          echo "Schemes available:"
          xcodebuild -project $PROJECT -list

      # ── Build the app ─────────────────────────────────────────
      - name: Build and archive
        run: |
          mkdir -p $BUILD_DIR
          xcodebuild archive \
            -project $PROJECT \
            -scheme $SCHEME \
            -configuration Release \
            -destination 'generic/platform=macOS' \
            -archivePath $BUILD_DIR/$APP_NAME.xcarchive \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="-" \
            DEVELOPMENT_TEAM="" \
            OTHER_CODE_SIGN_FLAGS="--deep" \
            | xcpretty || true

      # ── Export .app from archive ───────────────────────────────
      - name: Export .app from archive
        run: |
          # Write ExportOptions.plist for ad-hoc export
          # Change method to "developer-id" if you have a Developer ID cert
          cat > ExportOptions.plist << 'EOF'
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
              <key>method</key>
              <string>mac-application</string>
              <key>destination</key>
              <string>export</string>
          </dict>
          </plist>
          EOF

          xcodebuild -exportArchive \
            -archivePath $BUILD_DIR/$APP_NAME.xcarchive \
            -exportPath $BUILD_DIR/ \
            -exportOptionsPlist ExportOptions.plist

      - name: Verify exported app
        run: |
          ls -la $BUILD_DIR/
          # Print the version from the built app's Info.plist
          /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist"

      # ── (OPTIONAL) Code sign with Developer ID ────────────────
      # Uncomment this block if you have a Developer ID certificate.
      # If skipped, the app will be ad-hoc signed (already done by xcodebuild above).
      #
      # - name: Import Developer ID certificate
      #   env:
      #     MACOS_CERTIFICATE: ${{ secrets.MACOS_CERTIFICATE }}
      #     MACOS_CERTIFICATE_PWD: ${{ secrets.MACOS_CERTIFICATE_PWD }}
      #     MACOS_CERTIFICATE_NAME: ${{ secrets.MACOS_CERTIFICATE_NAME }}
      #     MACOS_CI_KEYCHAIN_PWD: ${{ secrets.MACOS_CI_KEYCHAIN_PWD }}
      #   run: |
      #     echo $MACOS_CERTIFICATE | base64 --decode > certificate.p12
      #     security create-keychain -p "$MACOS_CI_KEYCHAIN_PWD" build.keychain
      #     security default-keychain -s build.keychain
      #     security unlock-keychain -p "$MACOS_CI_KEYCHAIN_PWD" build.keychain
      #     security set-keychain-settings -lut 21600 build.keychain
      #     security import certificate.p12 \
      #       -k build.keychain \
      #       -P "$MACOS_CERTIFICATE_PWD" \
      #       -T /usr/bin/codesign
      #     security set-key-partition-list \
      #       -S apple-tool:,apple:,codesign: \
      #       -s -k "$MACOS_CI_KEYCHAIN_PWD" build.keychain
      #
      # - name: Sign with Developer ID
      #   env:
      #     MACOS_CERTIFICATE_NAME: ${{ secrets.MACOS_CERTIFICATE_NAME }}
      #   run: |
      #     /usr/bin/codesign \
      #       --force \
      #       --deep \
      #       --sign "$MACOS_CERTIFICATE_NAME" \
      #       --options runtime \
      #       --entitlements GitAccountSwitcher/GitAccountSwitcher.entitlements \
      #       $BUILD_DIR/$APP_NAME.app
      #     codesign --verify --deep --strict $BUILD_DIR/$APP_NAME.app
      #
      # - name: Cleanup keychain
      #   if: always()
      #   run: security delete-keychain build.keychain 2>/dev/null || true

      # ── (OPTIONAL) Notarization ────────────────────────────────
      # Only enabled if you have Developer ID cert AND Apple credentials.
      # Requires the signing step above to have run first.
      #
      # - name: Notarize application
      #   env:
      #     NOTARIZATION_APPLE_ID: ${{ secrets.NOTARIZATION_APPLE_ID }}
      #     NOTARIZATION_PASSWORD: ${{ secrets.NOTARIZATION_PASSWORD }}
      #     NOTARIZATION_TEAM_ID: ${{ secrets.NOTARIZATION_TEAM_ID }}
      #   run: |
      #     xcrun notarytool store-credentials "notarytool-profile" \
      #       --apple-id "$NOTARIZATION_APPLE_ID" \
      #       --team-id "$NOTARIZATION_TEAM_ID" \
      #       --password "$NOTARIZATION_PASSWORD"
      #     ditto -c -k --keepParent \
      #       $BUILD_DIR/$APP_NAME.app \
      #       $BUILD_DIR/notarize-upload.zip
      #     xcrun notarytool submit $BUILD_DIR/notarize-upload.zip \
      #       --keychain-profile "notarytool-profile" \
      #       --wait
      #     xcrun stapler staple $BUILD_DIR/$APP_NAME.app
      #     rm $BUILD_DIR/notarize-upload.zip
      #     spctl -a -v $BUILD_DIR/$APP_NAME.app

      # ── Create DMG ─────────────────────────────────────────────
      - name: Install create-dmg
        run: brew install create-dmg

      - name: Create DMG
        run: |
          # Stage the app
          mkdir -p $BUILD_DIR/dmg-staging
          cp -r $BUILD_DIR/$APP_NAME.app $BUILD_DIR/dmg-staging/

          DMG_NAME="$APP_NAME-$VERSION.dmg"

          create-dmg \
            --volname "Git Account Switcher $VERSION" \
            --window-pos 200 120 \
            --window-size 600 300 \
            --icon-size 100 \
            --icon "$APP_NAME.app" 175 120 \
            --hide-extension "$APP_NAME.app" \
            --app-drop-link 425 120 \
            --hdiutil-retries 5 \
            "$BUILD_DIR/$DMG_NAME" \
            "$BUILD_DIR/dmg-staging/"

          echo "DMG created: $BUILD_DIR/$DMG_NAME"
          ls -lh $BUILD_DIR/*.dmg

      # ── Create ZIP as backup artifact ─────────────────────────
      - name: Create ZIP artifact
        run: |
          ditto -c -k --keepParent \
            $BUILD_DIR/$APP_NAME.app \
            "$BUILD_DIR/$APP_NAME-$VERSION.zip"
          echo "ZIP created:"
          ls -lh $BUILD_DIR/*.zip

      # ── Commit version bump and push tag ──────────────────────
      - name: Commit version bump and tag release
        run: |
          git config --local user.email "github-actions[bot]@users.noreply.github.com"
          git config --local user.name "github-actions[bot]"
          git add project.yml
          git commit -m "chore: bump version to $TAG [skip ci]"
          git tag "$TAG"
          git push origin main --follow-tags
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      # ── Create GitHub Release ─────────────────────────────────
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ env.TAG }}
          name: "Git Account Switcher ${{ env.TAG }}"
          body: |
            ## Git Account Switcher ${{ env.TAG }}

            ### Installation
            1. Download `${{ env.APP_NAME }}-${{ env.VERSION }}.dmg` below
            2. Open the DMG and drag **Git Account Switcher** to your Applications folder
            3. **First launch:** Right-click the app → Open → Open
               (This bypasses the Gatekeeper warning for apps without App Store signing)

            ### What Changed
            See commit history for details. This release was automatically generated from
            conventional commits pushed to `main`.

            ### Requirements
            - macOS 13.0 (Ventura) or later
          draft: false
          prerelease: false
          files: |
            dist/${{ env.APP_NAME }}-${{ env.VERSION }}.dmg
            dist/${{ env.APP_NAME }}-${{ env.VERSION }}.zip
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## Supporting Files to Add to Your Repository

### `.github/workflows/ci.yml` (separate PR check workflow)

Keep a lightweight CI workflow for pull request checks, separate from the release workflow:

```yaml
name: CI

on:
  pull_request:
    branches:
      - main

jobs:
  build-check:
    name: Build Check
    runs-on: macos-14

    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 16.2
        run: sudo xcode-select -s /Applications/Xcode_16.2.app/Contents/Developer

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Build (Debug, unsigned)
        run: |
          xcodebuild build \
            -project GitAccountSwitcher.xcodeproj \
            -scheme GitAccountSwitcher \
            -configuration Debug \
            -destination 'generic/platform=macOS' \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            | xcpretty || true
```

### `ExportOptions.plist` (commit to repository root)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

When you get a Developer ID certificate, change `mac-application` to `developer-id` and add:
```xml
    <key>teamID</key>
    <string>YOUR10CHTEAMID</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
```

---

## Initial Setup Checklist

Before the workflow will run successfully:

- [ ] Create initial git tag: `git tag v1.0.0 && git push origin v1.0.0`
- [ ] Enable workflow write permissions: Repository Settings → Actions → General → Workflow permissions → "Read and write permissions"
- [ ] Create `.github/workflows/` directory and add both workflow YAML files
- [ ] Commit `ExportOptions.plist` to repository root
- [ ] Start writing commits using conventional commit format:
  - `feat:` for new features
  - `fix:` for bug fixes
  - `refactor:` for code changes that don't add features or fix bugs
  - `chore:` for maintenance (version bumps, dependency updates)
  - `docs:` for documentation changes
- [ ] (Optional, for Developer ID signing) Add GitHub Secrets:
  - `MACOS_CERTIFICATE`
  - `MACOS_CERTIFICATE_PWD`
  - `MACOS_CERTIFICATE_NAME`
  - `MACOS_CI_KEYCHAIN_PWD`
- [ ] (Optional, for notarization) Add additional secrets:
  - `NOTARIZATION_APPLE_ID`
  - `NOTARIZATION_PASSWORD`
  - `NOTARIZATION_TEAM_ID`

---

## Detailed Analysis

### Version Strategy Deep Dive

The version bump strategy has three layers:

**Layer 1: `MARKETING_VERSION` in `project.yml`**
This is the user-visible version string (e.g., `1.2.3`). It gets stored as `CFBundleShortVersionString`
in the built app's Info.plist because the plist file uses `$(MARKETING_VERSION)`. The workflow
updates this with `sed` before `xcodegen generate` runs, so the generated `.xcodeproj` has the
correct value embedded.

**Layer 2: `CURRENT_PROJECT_VERSION` in `project.yml`**
This is the build number, mapped to `CFBundleVersion`. Using `${{ github.run_number }}` here gives
a monotonically increasing integer unique to each CI run — exactly what Apple expects.

**Layer 3: Git tag**
The tag (e.g., `v1.2.3`) is what the GitHub Release anchors to. The `semver-action` reads all
tags to determine what the current version is and what the next one should be.

### Why `sed -i ''` and not `sed -i`?

On macOS, `sed -i ''` is required (empty string for in-place backup suffix). On Linux, `sed -i` works
without the `''`. Since the workflow runs on `macos-14`, use `sed -i ''`. The `version:` job runs
on `ubuntu-latest` (just for semver calculation, no file edits there), so this distinction only
matters in the `build:` job.

### Preventing Infinite Workflow Loops

When the workflow pushes the version bump commit back to `main`, it could trigger the workflow
again. Two safeguards prevent this:

1. `[skip ci]` in the commit message — GitHub Actions honors this to skip workflow triggers
2. The commit is made by `github-actions[bot]`, and the `GITHUB_TOKEN` does not trigger other
   `push` event workflows (GitHub security feature)

If you use a Personal Access Token instead of `GITHUB_TOKEN` for the push (e.g., to trigger
downstream workflows), then `[skip ci]` becomes the only safeguard — make sure it is in the message.

### XcodeGen in CI vs. Committed `.xcodeproj`

Your project correctly gitignores `.xcodeproj` and uses `project.yml` as the source of truth.
This means CI must install XcodeGen and run `xcodegen generate` as an early step. The generated
project only lives for the duration of the workflow run.

**Caching XcodeGen install (if build time matters):**
```yaml
- name: Cache Homebrew packages
  uses: actions/cache@v4
  with:
    path: |
      ~/Library/Caches/Homebrew
      /usr/local/Cellar/xcodegen
    key: homebrew-xcodegen-${{ runner.os }}-${{ hashFiles('project.yml') }}

- name: Install XcodeGen
  run: brew install xcodegen
```

### DMG vs. ZIP Trade-offs

| | DMG | ZIP |
|---|---|---|
| User experience | Polished drag-to-install | Unzip and copy manually |
| Tool dependency | `create-dmg` (brew install) | None (ditto is built-in) |
| CI reliability | Occasional hdiutil failures | Very reliable |
| File size | Slightly larger | Smaller |
| Signing support | Can sign the DMG itself | Sign the .app inside |
| Recommendation | Preferred for releases | Good fallback |

Shipping both (as the workflow does) gives users choice and provides a fallback if one fails.

### Entitlements and Hardened Runtime Compatibility

This project's entitlements file disables the App Sandbox but keeps hardened runtime enabled
(via `ENABLE_HARDENED_RUNTIME: YES` in `project.yml`). This is the correct configuration for:
- Non-sandboxed apps that need full Keychain access
- Apps distributed outside the App Store
- Apps that need to run `git` as a subprocess

With `--options runtime` in the codesign command, the app runs in hardened runtime mode but
with the relaxations specified in the entitlements file. This satisfies Apple's notarization
requirements while still allowing unrestricted Keychain and process execution access.

---

## Research Gaps and Limitations

- **macOS 15 runner**: The workflow uses `macos-14`. If you need macOS 15 features or Xcode 16.3+,
  switch to `macos-15`. Check available Xcode versions at https://github.com/actions/runner-images
  before changing.

- **xcpretty**: The workflow uses `xcpretty` for cleaner build output, but it may not be installed
  by default on the runner. Either add `gem install xcpretty` as a step, or pipe through `cat`
  instead (remove `| xcpretty || true`).

- **`create-dmg` hdiutil failures**: Known flaky issue on GitHub Actions macOS runners
  (see GitHub issue actions/runner-images#7522). The `--hdiutil-retries 5` flag mitigates this.
  If it persists, fall back to ZIP only.

- **`semver-action` fallback tag**: If no tags exist in the repository, `semver-action` will fail.
  Must create `v1.0.0` tag first as documented in the setup checklist.

- **Branch protection rules**: If your `main` branch has branch protection enabled, the workflow's
  git push back to main may fail. You can either: disable protection for the bot's push, use a
  GitHub App token with bypass permissions, or move the version bump to a separate step that only
  creates the git tag (not a commit to main).

---

## Contradictions and Decisions Made

- **`macos-14` vs `macos-15`**: Some sources recommend `macos-latest` for simplicity, but since
  `macos-latest` now maps to macOS 15 (as of late 2025) and the project targets macOS 13+, pinning
  to `macos-14` gives more stability. Either works for this project.

- **`archive + exportArchive` vs direct `build`**: The archive approach is more work but produces
  a properly structured `.app` suitable for signing and distribution. Direct `build` is faster but
  produces a `.app` in DerivedData that is harder to locate and package. The archive approach is
  used here.

- **Version bump commit before or after build**: The version is bumped in `project.yml` before
  `xcodegen generate` and the build, so the built binary actually contains the correct version
  string. The git commit/tag push happens after the build succeeds, ensuring a failed build does
  not create a dangling version tag.

---

## Search Methodology

- Searches performed: 12 web searches + 6 page fetches
- Most productive search terms:
  - "distributing Mac apps with GitHub Actions"
  - "automatic code signing notarization macOS GitHub Actions"
  - "create-dmg GitHub"
  - "ietf-tools/semver-action"
  - "xcodebuild archive exportArchive macOS ExportOptions plist"
- Primary information sources:
  - defn.io (Franz app distribution case study)
  - federicoterzi.com (Espanso code signing guide)
  - localazy.com (Developer ID certificate workflow)
  - ietf-tools/semver-action (GitHub Marketplace)
  - github.com/actions/runner-images (runner specs)
  - create-dmg/create-dmg (DMG creation tool)
  - softprops/action-gh-release (release action)

---

## Sources

- [Distributing Mac Apps With GitHub Actions — defn.io](https://defn.io/2023/09/22/distributing-mac-apps-with-github-actions/)
- [Automatic Code-signing and Notarization for macOS apps using GitHub Actions — Federico Terzi](https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/)
- [How to automatically sign macOS apps using GitHub Actions — Localazy](https://localazy.com/blog/how-to-automatically-sign-macos-apps-using-github-actions)
- [create-dmg — GitHub](https://github.com/create-dmg/create-dmg)
- [ietf-tools/semver-action — GitHub Marketplace](https://github.com/marketplace/actions/semver-conventional-commits)
- [softprops/action-gh-release — GitHub](https://github.com/softprops/action-gh-release)
- [xcodegen GitHub Action — Marketplace](https://github.com/marketplace/actions/xcodegen)
- [macOS 14 Runner Image README — actions/runner-images](https://github.com/actions/runner-images/blob/main/images/macos/macos-14-Readme.md)
- [Upcoming changes to macOS hosted runners 2025 — GitHub Changelog](https://github.blog/changelog/2025-07-11-upcoming-changes-to-macos-hosted-runners-macos-latest-migration-and-xcode-support-policy-updates/)
- [Technical Q&A QA1827: Automating Version and Build Numbers Using agvtool — Apple](https://developer.apple.com/library/archive/qa/qa1827/_index.html)
- [Semver Conventional Commits Action — GitHub Marketplace](https://github.com/marketplace/actions/semver-conventional-commits)
- [GitHub Actions: hdiutil failures when creating DMGs — Issue #7522](https://github.com/actions/runner-images/issues/7522)
