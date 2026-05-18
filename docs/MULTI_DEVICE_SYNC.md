# Multi-Device Sync — GreatDeploy

## Setup

### Prerequisites
- macOS 13.0+ on all devices
- Same Apple ID signed in to iCloud
- iCloud Drive enabled

### Enabling Sync
1. Open GreatDeploy → Settings → Multi-Device Sync
2. Toggle "Enable Multi-Device Sync"
3. Wait for iCloud connection (green indicator)
4. Repeat on all devices

## How It Works

### Two-Layer Sync
1. **iCloud Key-Value Store** — Bundle index (< 1KB, instant)
2. **CloudKit** — Full bundle payload (JSON assets)

### Conflict Resolution
- **Per-server timestamp comparison** — last-write-wins
- **Same timestamp, different content** → flag conflict, keep local
- **Identical content** → no-op

### What Syncs
- ✅ Bundle names, descriptions
- ✅ Server configurations (command, args, URL, tags)
- ✅ Enabled client list
- ✅ Sync state (last synced, previously synced names)

### What Does NOT Sync
- ❌ Secret values (API keys, tokens) — stored in Keychain only
- ❌ Audit logs — local to each device
- ❌ File watcher state — local to each device

## FAQ

**Q: Why aren't my secrets syncing?**
A: Secrets are stored in macOS Keychain for security. You must enter them on each device.

**Q: What happens if I edit a config file directly?**
A: GreatDeploy detects external changes and shows a badge. You can re-sync to restore.

**Q: Can I use GreatDeploy without iCloud?**
A: Yes. Multi-device sync is opt-in. Single-device mode works without iCloud.

**Q: What if two devices edit the same server?**
A: Last-write-wins based on timestamp. If timestamps match, local version is kept and a conflict is flagged.
