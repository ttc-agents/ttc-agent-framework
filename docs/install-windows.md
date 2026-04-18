# Windows Install Guide

One-command install for a fresh Windows 10/11 workstation.

## Prerequisites

- Windows 10 (build 1809+) or Windows 11
- `winget` (App Installer) — ships by default on Win11; install from Microsoft Store on Win10
- GitHub account with access to `ttc-agents` org
- PowerShell 5.1+ (built in) — PowerShell 7 also works

## One-liner

Open **PowerShell** (as your normal user — no admin needed for winget user-scope installs) and run:

```powershell
iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex
```

If execution policy blocks it:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex"
```

## What it installs

**System tools** (via winget):
- `Git.Git`, `GitHub.cli`, `OpenJS.NodeJS.LTS`, `Python.Python.3.12`, `1Password.CLI`

**Claude Code:**
- `npm install -g @anthropic-ai/claude-code`

**Framework:**
- `%USERPROFILE%\AI-Vault\ttc-agent-framework\`

**Standard agent bundle** (into `%USERPROFILE%\AI-Vault\Agents\`):
- `SAP` — SAP engineering & testability
- `Test` — Test management & design
- `TAF` — Test Automation Framework (Playwright)
- `Tender` — Tender & proposal authoring

**Config files:**
- `%USERPROFILE%\CLAUDE.md` — agent routing (created or appended)
- `%USERPROFILE%\.claude.json` — minimal MCP config (only if missing)

## Interactive steps

1. **`gh auth login`** if not already authenticated — paste a PAT or use browser login

Everything else runs unattended.

## After install

Close and reopen PowerShell (so new tools are picked up from PATH), then:

```powershell
claude          # authenticate with your Anthropic API key
# then inside Claude Code:
apply sap       # or: apply test | apply taf | apply tender
```

## Adding more agents

```powershell
& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\add-agent.ps1" hr
```

Known agents: `hr`, `bwbm`, `pptx`, `odoo`, `contracts`, `finance`, `personal`, `private`, `infra`.

## SAP skill symlinks — note

The SAP agent uses directory **junctions** for its 12 curated skills (not symlinks). Junctions don't need admin or Developer Mode. The SAP `install.ps1` falls back to symlinks if junctions fail.

## Custom install location

```powershell
$env:TTC_INSTALL_ROOT = "C:\work\ttc"
iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 | iex
```

## Re-running

Idempotent. Existing clones are pulled, existing tools are skipped, existing routing lines are not duplicated.

## Platform gaps vs macOS

Not included on Windows (Mac-only features):
- Dispatcher LaunchAgent → would need Task Scheduler
- AgentLauncher tray app → SwiftUI, Mac-only
- Syncthing conflict monitor → script runs, but scheduling needs Task Scheduler
- Trading agents → personal-only, not shipped

The `apply <agent>` interactive workflow works identically.
