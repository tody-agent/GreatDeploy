# Design: Security Vulnerability Fixes

## Context & Technical Approach

The security audit identified a critical flaw: PATs (Personal Access Tokens) are serialized
into UserDefaults via `GitAccount.Codable`, making them readable by any process. The fix must:

1. Remove PATs from `CodingKeys` so they are NEVER written to UserDefaults
2. Store each account's PAT in the Keychain using `kSecClassGenericPassword` keyed by UUID
3. Migrate existing PATs from UserDefaults to Keychain on first load
4. Add process timeout protection for all `Process()` invocations
5. Apply consistent error sanitization across all error paths

## Architecture Change

```
BEFORE:
  GitAccount → Codable (includes PAT) → UserDefaults (plaintext plist)
  Only active account PAT → Keychain (kSecClassInternetPassword)

AFTER:
  GitAccount → Codable (NO PAT) → UserDefaults (safe metadata only)
  ALL account PATs → Keychain (kSecClassGenericPassword, keyed by UUID)
  Active account PAT → Keychain (kSecClassInternetPassword, for git credential helper)
```

## Proposed Changes

### 1. GitAccount.swift — Remove PAT from serialization
- Remove `personalAccessToken` from `CodingKeys`
- Use `decodeIfPresent` for migration (old data may have PAT)
- Update comments to match actual behavior

### 2. KeychainService.swift — Per-account PAT storage
- Add `saveAccountToken(accountId:token:)` using kSecClassGenericPassword
- Add `readAccountToken(accountId:)` for retrieval
- Add `deleteAccountToken(accountId:)` for cleanup
- Remove deprecated comment block (L372-376)

### 3. AccountStore.swift — Rewire PAT flow through Keychain
- `addAccount`: save PAT to per-account Keychain
- `updateAccount`: update PAT in per-account Keychain
- `removeAccount`: delete per-account Keychain entry
- `loadAccounts`: hydrate PATs from Keychain after loading metadata
- Migration: detect legacy PATs in loaded data, migrate to Keychain, re-save without PATs
- `restoreActiveAccountCredential`: read from per-account Keychain

### 4. AddEditAccountView.swift — Load PAT from Keychain
- `loadAccountData`: read PAT from Keychain service instead of model

### 5. Process timeout protection (MED-01)
- Add timeout wrapper for `Process.waitUntilExit()`
- Apply to GitConfigService, GitHubCLIService, KeychainService

### 6. Error sanitization (MED-03)
- Apply `ValidationUtilities.sanitizeErrorMessage()` to all `lastError` assignments

## Verification
- Build succeeds with `xcodebuild`
- PAT field absent from UserDefaults serialization
- PATs stored in Keychain under per-account keys
- Existing users' data migrates automatically
