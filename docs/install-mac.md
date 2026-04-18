# macOS Install Guide

One-command install for a fresh macOS workstation.

## Prerequisites

- macOS 13+
- Admin password (Homebrew needs sudo once)
- GitHub account with access to `ttc-agents` org

## One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
```

## What it installs

**System tools** (via Homebrew):
- `git`, `gh` (GitHub CLI), `node`, `python@3.12`, `1password-cli`

**Claude Code:**
- `npm install -g @anthropic-ai/claude-code`

**Framework:**
- `~/AI-Vault/ttc-agent-framework/`

**Standard agent bundle** (into `~/AI-Vault/Agents/`):
- `SAP` — SAP engineering & testability (BTP, CAP, ABAP, Fiori, HANA, SAC)
- `Test` — Test management & test design
- `TAF` — Test Automation Framework (Playwright/TypeScript)
- `Tender` — Tender & proposal authoring

**Config files:**
- `~/CLAUDE.md` — agent routing table (created from template if absent, else appended to)
- `~/.claude.json` — minimal MCP config with filesystem server rooted at `~/AI-Vault` (only written if missing)

## Interactive steps

The installer is mostly unattended. Two moments ask for input:

1. **Homebrew install** (if not present) — asks for admin password
2. **`gh auth login`** — if not already authenticated; choose browser or PAT

## After install

```bash
claude          # authenticate with your Anthropic API key
# then inside Claude Code:
apply sap       # or: apply test | apply taf | apply tender
```

## Adding more agents

```bash
~/AI-Vault/ttc-agent-framework/scripts/add-agent.sh hr
```

Known agents: `hr`, `bwbm`, `pptx`, `odoo`, `contracts`, `finance`, `personal`, `private`, `infra`.

## Custom install location

Set `TTC_INSTALL_ROOT` before running:

```bash
TTC_INSTALL_ROOT=~/work/ttc bash -c "$(curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh)"
```

## Re-running

The installer is idempotent — re-running updates clones with `git pull --ff-only`, re-runs per-agent install scripts (which are also idempotent), and only appends missing routing lines to `~/CLAUDE.md`.

## MCP servers beyond filesystem

The installer writes a minimal `~/.claude.json` with just the filesystem server. To add `ms365`, `proton`, or `knowledge-base`, follow the per-server setup in `ttc-agent-infra` (requires per-machine auth).
