# Mac Setup Guide

Step-by-step setup for the TTC Agent Framework on macOS.

## Prerequisites

- macOS 13.0 or later
- Admin access
- GitHub account

## 1. Install Warp Terminal

```bash
brew install --cask warp
```

Warp provides the best experience for Claude Code sessions. Terminal.app also works.

## 2. Install Claude Code

```bash
npm install -g @anthropic-ai/claude-code
```

Run `claude` once to authenticate with your Anthropic API key.

## 3. Install 1Password CLI (optional, for secrets in MCP)

```bash
brew install 1password-cli
```

Used by `op-mcp-wrapper.sh` to resolve `op://` secret references in MCP server environment variables.

## 4. Install GitHub CLI

```bash
brew install gh
gh auth login
```

## 5. Clone the framework

```bash
gh repo clone your-org/ttc-agent-framework ~/AI-Vault/ttc-agent-framework
```

## 6. Set up MCP servers

Edit `~/.claude/mcp.json` to register your MCP servers. Example:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-filesystem", "/Users/you/AI-Vault"]
    }
  }
}
```

If using 1Password for secrets, wrap commands with `op-mcp-wrapper.sh`:

```json
{
  "mcpServers": {
    "my-service": {
      "command": "/path/to/scripts/op-mcp-wrapper.sh",
      "args": ["node", "my-mcp-server"],
      "env": {
        "API_KEY": "op://vault/item/field"
      }
    }
  }
}
```

## 7. Set up Claude config symlinks

If you have multiple machines sharing the same config:

```bash
# On secondary machine, symlink to synced config
ln -sf ~/AI-Vault/config/.claude.json ~/.claude.json
```

## 8. Build AgentLauncher

```bash
cd ~/AI-Vault/ttc-agent-framework/launcher
./build.sh
```

The app appears in `launcher/AgentLauncher.app`. Drag it to your Applications folder or add it to Login Items.

Edit `AgentLauncher.swift` to add your agents before building.

## 9. Clone agent repos

If you have existing agent repos, use the restore script:

```bash
# Edit scripts/restore-all.sh to match your GitHub user and repo names
~/AI-Vault/ttc-agent-framework/scripts/restore-all.sh
```

Or create a new agent from the template:

```bash
cp -r ~/AI-Vault/ttc-agent-framework/agent-template ~/AI-Vault/Agents/MyNewAgent
# Edit system-prompt.md, CLAUDE.md, etc.
```

## 10. Add `apply` commands to ~/CLAUDE.md

Copy `CLAUDE.md.example` to `~/CLAUDE.md` and update the table with your agents:

```markdown
| `apply finance` | `/Users/you/AI-Vault/Agents/Finance/system-prompt.md` |
| `apply hr`      | `/Users/you/AI-Vault/Agents/HR/system-prompt.md` |
```

## Optional: Set up the dispatcher

1. Copy `dispatcher/dispatcher-config.example.json` to `dispatcher/dispatcher-config.json`
2. Edit it to match your agents and scripts
3. Create a LaunchAgent plist to run the dispatcher every 15 minutes:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ttc.dispatcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/.venv/bin/python3</string>
        <string>/path/to/dispatcher/ttc_dispatcher.py</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>StandardOutPath</key>
    <string>/tmp/ttc-dispatcher.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ttc-dispatcher.log</string>
</dict>
</plist>
```

```bash
cp com.ttc.dispatcher.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.ttc.dispatcher.plist
```

## Optional: Set up Syncthing conflict monitoring

1. Set the `CONFLICT_EMAIL` environment variable
2. Create a LaunchAgent to run `scripts/sync-conflict-monitor.py` every 5 minutes
