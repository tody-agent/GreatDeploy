# Implementation Checklist — Security Fixes

## CRIT-01 + CRIT-02: PAT Storage Fix
- [ ] 1.1 GitAccount.swift — Remove PAT from CodingKeys, fix comments
- [ ] 1.2 KeychainService.swift — Add per-account PAT Keychain methods
- [ ] 1.3 AccountStore.swift — Rewire all PAT operations through Keychain
- [ ] 1.4 AddEditAccountView.swift — Load PAT from Keychain in edit mode
- [ ] 1.5 KeychainService.swift — Remove deprecated comment block

## MED-01: Process Timeout
- [ ] 2.1 Add Process timeout utility function
- [ ] 2.2 Apply timeout to GitConfigService.runGitCommand
- [ ] 2.3 Apply timeout to GitHubCLIService process calls
- [ ] 2.4 Apply timeout to KeychainService.runGitCredentialCommand

## MED-03: Error Sanitization
- [ ] 3.1 AccountStore — Sanitize all lastError assignments

## Verification
- [ ] 4.1 Build verification with xcodebuild
