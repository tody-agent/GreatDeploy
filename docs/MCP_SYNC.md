# MCP Sync — GreatDeploy

## Overview

GreatDeploy now manages MCP (Model Context Protocol) server configurations across 9 AI coding tools. Configure once, sync everywhere.

## Supported Clients

| Client | Config Path (macOS) | Format |
|--------|---------------------|--------|
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | JSON |
| Cursor | `~/.cursor/mcp.json` | JSON |
| VS Code | `~/Library/Application Support/Code/User/settings.json` | JSON (nested) |
| Claude Code | `~/.claude/settings.json` | JSON |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` | JSON |
| Zed | `~/.config/zed/settings.json` | JSON (context_servers) |
| JetBrains IDE | `~/Library/Application Support/JetBrains/*/options/mcp.xml` | XML |
| Codex CLI | `~/.codex/config.toml` | TOML |
| Antigravity | `.antigravity/config.json` | JSON |

## How It Works

1. **Create a bundle** — Group MCP servers together
2. **Add servers** — Configure command, args, env, URL
3. **Enable clients** — Toggle which AI tools receive the config
4. **Sync** — Push to all enabled clients with one click

## Merge Behavior

GreatDeploy uses a **merge-based sync** (not overwrite):
- Servers you add directly in a client are **preserved**
- Servers removed from the bundle are **removed** from clients (orphan cleanup)
- Non-MCP settings (themes, extensions) are **never touched**

## Secrets Management

- API keys and tokens are stored in **macOS Keychain**
- Secrets are **injected at sync time** — never written to config files
- Secrets are **NOT synced** via iCloud — you must enter them on each device
- Servers with missing secrets show a 🔑 badge

## Multi-Device Sync

1. Go to Settings → Multi-Device Sync
2. Toggle "Enable Multi-Device Sync"
3. Sign in to iCloud on all devices
4. Changes sync within 60 seconds

**Note:** Only bundle metadata syncs via iCloud. Secrets remain device-local.

## Troubleshooting

### Client not detected
- Ensure the AI tool is installed
- Check if config directory exists
- Restart GreatDeploy after installing a new tool

### Sync failed
- Check audit log: `~/Library/Logs/GreatDeploy/mcp-audit.log`
- Verify config file permissions
- Ensure no other process is writing to the config

### Missing secrets after iCloud sync
- This is expected — secrets are NOT synced
- Re-enter tokens on the new device
- Servers will show 🔑 badge until secrets are added
