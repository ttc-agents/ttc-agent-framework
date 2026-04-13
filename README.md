# TTC Agent Framework

A reusable skeleton for building a Claude Code multi-agent system. Create specialised AI agents that share a common infrastructure for scheduling, syncing, and launching.

## What's Included

| Directory | Purpose |
|---|---|
| `agent-template/` | Scaffold for new agents (system prompt, CLAUDE.md, memory/) |
| `dispatcher/` | Config-driven task scheduler replacing multiple LaunchAgents |
| `sync/` | Auto-discovers agents and tracks knowledge changes across them |
| `launcher/` | macOS SwiftUI menu bar app to launch agents in Warp or Terminal |
| `scripts/` | Utilities: 1Password MCP wrapper, Syncthing conflict monitor, restore-all |
| `docs/` | Setup guides for Mac (and future Windows) |

## Quick Start

1. See [docs/setup-guide-mac.md](docs/setup-guide-mac.md) for full installation steps
2. Copy `CLAUDE.md.example` to `~/CLAUDE.md` and add your agents
3. Create agents from `agent-template/`

## Adding a New Agent

```bash
cp -r agent-template/ ~/AI-Vault/Agents/MyAgent
```

Edit the files:
- `system-prompt.md` — the agent's persona, role, and instructions
- `CLAUDE.md` — project config (MCP servers, quick links)
- `memory/` — persistent state files the agent reads at session start

Then add a row to `~/CLAUDE.md`:

```markdown
| `apply myagent` | `/path/to/Agents/MyAgent/system-prompt.md` |
```

## Architecture

```
~/CLAUDE.md                     # "apply <agent>" routing table
~/AI-Vault/
  Agents/
    AgentA/                     # one repo per agent
      system-prompt.md
      CLAUDE.md
      memory/
    AgentB/
      ...
  ttc-agent-framework/          # this repo (shared infra)
    dispatcher/
    sync/
    launcher/
    scripts/
```

Each agent is an independent Git repo. The framework provides shared tooling.

## License

MIT
