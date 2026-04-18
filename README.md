# TTC Agent Framework

A reusable skeleton for building a Claude Code multi-agent system. Create specialised AI agents that share a common infrastructure for scheduling, syncing, and launching.

## For Team Members — Onboarding

Ask the repo owner to grant you **read access** on the agent repos you need (e.g. `ttc-agent-tender`, `ttc-agent-taf`, `ttc-agent-test`, `ttc-agent-sap`). Then open a terminal on your own workstation and paste **one line**:

**Windows (PowerShell):**
```powershell
iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex
```

**Mac/Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
```

The installer takes about 5 minutes. It installs prerequisites (`git`, `gh`, `node`, `python`, `1Password CLI`), Claude Code itself, clones the framework, and clones the four base agents you have access to: **SAP**, **Test**, **TAF**, **Tender**.

During install, you'll see a one-time device code. Open https://github.com/login/device in any browser, paste the code, and sign in with your GitHub account — that authorises the installer to clone the private agent repos.

When it finishes:
1. Run `claude` once to authenticate with Anthropic.
2. Inside Claude Code, type `apply tender` (or `apply taf` / `apply test` / `apply sap`).

Full guides: [docs/install-mac.md](docs/install-mac.md) · [docs/install-windows.md](docs/install-windows.md)


## What's Included

| Directory | Purpose |
|---|---|
| `agent-template/` | Scaffold for new agents (system prompt, CLAUDE.md, memory/) |
| `dispatcher/` | Config-driven task scheduler replacing multiple LaunchAgents |
| `sync/` | Auto-discovers agents and tracks knowledge changes across them |
| `launcher/` | macOS SwiftUI menu bar app to launch agents in Warp or Terminal |
| `scripts/` | Utilities: 1Password MCP wrapper, Syncthing conflict monitor, restore-all |
| `docs/` | Setup guides for Mac (and future Windows) |

## Quick Start — One-Command Install

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
```

**Windows (PowerShell):**
```powershell
iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex
```

Installs prerequisites, Claude Code, the framework, and the standard base bundle (**SAP, Test, TAF, Tender**). Trading agents are personal-only and not included.

Full guides: [docs/install-mac.md](docs/install-mac.md) · [docs/install-windows.md](docs/install-windows.md)

### Add more agents later

```bash
# macOS / Linux
~/AI-Vault/ttc-agent-framework/scripts/add-agent.sh <name>

# Windows
& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\add-agent.ps1" <name>
```

Available: `hr`, `bwbm`, `pptx`, `odoo`, `contracts`, `finance`, `tom`, `personal-template`, `personal`, `private`, `infra`.

`personal-template` clones the **public, sanitized** Personal Assistant starter — the right choice for team members setting up their own Head Agent. `personal` clones the **private** Personal repo (owner-only).

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
