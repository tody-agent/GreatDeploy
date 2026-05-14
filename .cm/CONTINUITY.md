# Continuity

## Mistakes & Learnings

- What Failed: Active profile could show GitHub `omisocial`/BM while Cloudflare still pointed at the previous account ID.
- Why It Failed: `syncWithSystemKeychain()` trusted the GitHub keychain entry as the source of truth and silently mutated `isActive` without validating or applying the paired Cloudflare credentials.
- How to Prevent: Treat a development profile as an atomic GitHub + Cloudflare pair; external keychain/environment changes should surface an out-of-sync warning instead of changing app state implicitly.
- Scope: module:profile-switching
