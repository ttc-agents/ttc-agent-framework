# TTC Agent Framework — Installation Routines

Reference for all six install/update/migrate paths across macOS and Windows.

| Scenario | macOS | Windows |
|---|---|---|
| **Fresh install** | [§ 1.1](#11-mac--fresh-install) | [§ 2.1](#21-windows--fresh-install) |
| **Update (existing install)** | [§ 1.2](#12-mac--update-existing-install) | [§ 2.2](#22-windows--update-existing-install) |
| **Migrate from pre-2026-05 layout** | [§ 1.3](#13-mac--migrate-pre-2026-05-install) | [§ 2.3](#23-windows--migrate-pre-2026-05-install) |

End-user oriented walkthrough with screenshots: [`TTC-Agent-Install-Manual.md`](TTC-Agent-Install-Manual.md). This document is the operator-level technical reference.

---

## 0. Common prerequisites (all platforms, all scenarios)

Before any install path you need three things in place — once, then never again:

1. **Active Claude account** (claude.ai / Claude Desktop / Claude Code).
2. **GitHub account** with read access to the `ttc-agents` org. Ask Joerg to grant access; he adds you with `gh repo add-collaborator ttc-agents/ttc-agent-<name> <github-user> --permission read`.
3. **SSH key registered with GitHub.** All TTC repos are accessed over SSH (no more OAuth-token expiry pain). See [Appendix A — SSH key setup](#appendix-a--ssh-key-setup).

Optional but recommended:

- **1Password CLI** — needed by the Proton Mail MCP server (Personal/Private agents) and by the SAP / 1Password-bound MCP servers. See [Appendix B — 1Password CLI](#appendix-b--1password-cli-service-account).
- **OneDrive** signed in and the SharePoint library `Branding - TTC Global Branding` synced locally. The Docs agent reads logos and approved imagery from there directly.

---

## 1. macOS

### 1.1 Mac — Fresh install

**Audience:** new Mac, no prior TTC setup.

**Prerequisites:** § 0 above. SSH to GitHub must work before you start.

**One-line install:**

```bash
curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
```

**What it does** (7 steps, idempotent — safe to re-run):

| Step | Action |
|---|---|
| 1/7 | Checks prerequisites: brew, git, gh, node, python@3.12, 1password-cli (auto-installs missing via brew) |
| 2/7 | Installs Claude Code via npm (`@anthropic-ai/claude-code`) if missing |
| 3/7 | `gh auth login --git-protocol ssh` if not already authenticated; verifies `ssh -T git@github.com` works |
| 4/7 | Clones `ttc-agent-framework` to `~/AI-Vault/ttc-agent-framework/` |
| 5/7 | Discovers every `ttc-agent-*` repo your GitHub user can read; clones the ones in `install-config.json` (with `auto_install: true`) into `~/AI-Vault/Agents/<dir>/` |
| 6/7 | Clones shared repos: `Claude-Config`, `brand` (`ttc-brand-standards`), `Tools/mcp-proton` (`ttc-mcp-proton-server`); runs `npm install` for `mcp-proton` |
| 7/7 | Writes `~/CLAUDE.md` from `CLAUDE.md.template` if it doesn't exist |

**After it finishes:**

```bash
# 1. Restart your shell (so brew shellenv + Claude Code are on PATH)
exec zsh

# 2. Try an agent
claude
> apply personal
```

**Expected output (last lines):**

```
[ok] GitHub ready (SSH)
[ok] Framework at /Users/<you>/AI-Vault/ttc-agent-framework
[ok] N agent(s) will be installed
... (per-agent clone output)
[ok] Agents installed: N
[ok] Shared repos installed
[ok] ~/CLAUDE.md present
```

**Troubleshooting:**

| Symptom | Fix |
|---|---|
| `brew: command not found` after install | Add brew to PATH: `eval "$(/opt/homebrew/bin/brew shellenv)"` (Apple Silicon) or `/usr/local/bin/brew` (Intel) |
| `SSH to git@github.com is NOT working` | See [Appendix A](#appendix-a--ssh-key-setup) |
| Some agent repos missing | Ask Joerg to grant access; re-run the same install command (idempotent) |
| `apply <agent>` says "no such agent" | The script wrote `~/CLAUDE.md` only if it didn't exist. If you have a stale one, replace it with a symlink to `Claude-Config/CLAUDE.md` (see § 1.3 step 6) |

---

### 1.2 Mac — Update (existing install)

**Audience:** install already exists; you want today's commits from GitHub.

**Standard mode (skips repos with uncommitted changes):**

```bash
bash ~/AI-Vault/ttc-agent-framework/scripts/update-all.sh
```

**Force mode (discards local working-tree changes; reset every repo to `origin/main`):**

```bash
bash ~/AI-Vault/ttc-agent-framework/scripts/update-all.sh --force
```

**When to use which:**

- **Standard** when you trust your local state. Repos with uncommitted changes are skipped with a warning.
- **`--force`** when you have phantom dirtiness from Syncthing-vs-git interactions, or when GitHub is the source of truth and you want to throw away local diffs. **The Mac mini is the canonical committer** — other Macs should usually pull `--force`.

**What the script updates (in order):**

1. `ttc-agent-framework` itself
2. Every `~/AI-Vault/Agents/*/` git repo
3. Shared repos: `Claude-Config`, `brand`, `Tools/mcp-proton`
4. Refreshes runtime KB scripts under `~/AI-Vault/Claude Folder/`

**Pre-flight on non-Mini Macs (`--force` only):**

When you run `--force` on a Mac that is NOT the Mac mini, the script first SSHes to the Mini and triggers its hourly auto-commit script. This pushes any pending memory edits on Mini to GitHub before your local reset, so Syncthing can't propagate your reset back to Mini and clobber its uncommitted state. Configurable via:

```bash
TTC_MINI_HOST=joerg@10.0.0.x bash ~/AI-Vault/ttc-agent-framework/scripts/update-all.sh --force
TTC_SKIP_MINI_PRECOMMIT=1   bash ~/AI-Vault/ttc-agent-framework/scripts/update-all.sh --force
```

The Mini itself skips the pre-flight automatically (it would SSH to itself).

**Expected output:**

```
=== TTC Agent Framework -- Update All ===

[update] Updating framework...
[ok]      ttc-agent-framework -- abc1234 latest commit message
[update] Updating agents...
[ok]      Personal -- def5678 ...
... (one line per agent)
[update] Updating shared repos...
[ok]      Claude-Config -- ...
[ok]      brand -- ...
[ok]      mcp-proton -- ...
[update] Refreshing runtime KB scripts...
[ok] Update complete.
```

**Troubleshooting:**

| Symptom | Fix |
|---|---|
| `<repo> -- uncommitted changes, skipping` | Either commit those changes manually, or re-run with `--force` to discard them |
| `<repo> -- pull failed (non-FF?)` | Local repo has divergent commits. Either rebase manually, or `--force` |
| `Mini pre-commit done` followed by lots of `reset` lines | Working as designed — Mini had pending memory edits, they got pushed first, your Mac is now in sync |

---

### 1.3 Mac — Migrate (pre-2026-05 install)

**Audience:** Mac with a TTC install from before 2026-05-09. Symptoms:

- `~/AI-Vault/Agents/PPTX/` exists (the agent was renamed to `Docs`)
- `~/Personal/mcp-proton/` exists (the server was moved into `~/AI-Vault/Tools/`)
- `PROTON_PASSWORD` appears in plaintext in any Claude config file
- git remotes use `https://github.com/...` (should be `git@github.com:...`)
- `~/AI-Vault/brand/imagery/` or `~/AI-Vault/brand/logos/` exists locally (~1 GB of cached files, now read from OneDrive directly)

**Prerequisites:**

1. SSH key registered with GitHub ([Appendix A](#appendix-a--ssh-key-setup))
2. 1Password item `Proton Bridge PWD` exists in vault `AI Vault` (only matters if you use the Proton MCP)
3. OneDrive central branding synced locally (only matters for the Docs agent)

**Dry-run first** to see what would change without making any modifications:

```bash
bash ~/AI-Vault/ttc-agent-framework/scripts/migrate-to-2026-05.sh --dry-run
```

**Actual run:**

```bash
bash ~/AI-Vault/ttc-agent-framework/scripts/migrate-to-2026-05.sh
```

**The 7 steps the script performs (all idempotent):**

| Step | What changes |
|---|---|
| 1/7 | Verifies `ssh -T git@github.com` succeeds. Aborts with instructions if not. |
| 2/7 | Converts `https://github.com/...` remotes → `git@github.com:...` for every repo under `~/AI-Vault/`. |
| 3/7 | Clones `ttc-agent-docs` if missing. Leaves the old `Agents/PPTX/` folder on disk for you to verify + delete manually (safety). |
| 4/7 | Moves `~/Personal/mcp-proton/` → `~/AI-Vault/Tools/mcp-proton/` and re-clones it as a proper git repo. Patches `~/.claude.json`, `~/Library/Application Support/Claude/claude_desktop_config.json`, and the two Claude-Config copies to (a) point at the new path and (b) remove plaintext `PROTON_PASSWORD` (it's now read from 1Password at server startup). Removes empty `~/Personal/`. |
| 5/7 | Clones `ttc-brand-standards` into `~/AI-Vault/brand/`. Removes the stale local `brand/imagery/` and `brand/logos/` caches (handles `chflags uchg` if present). Warns if OneDrive central branding isn't mounted. |
| 6/7 | Symlinks `~/CLAUDE.md` → `Claude-Config/CLAUDE.md` and `~/.claude/commands/` → `Claude-Config/commands/`, backing up any existing files first. |
| 7/7 | Runs `update-all.sh --force` to land every repo on its current GitHub HEAD. |

**Manual finishing touches (reported by the script):**

- Old `~/AI-Vault/Agents/PPTX/` is preserved. After verifying that `Agents/Docs/` has all your customer work, remove it: `rm -rf ~/AI-Vault/Agents/PPTX`.
- After the migration, restart Claude Desktop so the Proton MCP server respawns from the new path with the 1Password-resolved password.

---

## 2. Windows

### 2.1 Windows — Fresh install

**Audience:** new Windows machine, no prior TTC setup.

**Prerequisites:** § 0 above. PowerShell 7+ recommended (`winget install Microsoft.PowerShell`). SSH key registered with GitHub.

**One-line install:**

```powershell
iwr https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.ps1 -UseBasicParsing | iex
```

**What it does** (parallel structure to the Mac flow):

| Step | Action |
|---|---|
| 1/7 | Verifies prerequisites via `winget`: Git, GitHub CLI, Node.js LTS, Python 3.12, 1Password CLI |
| 2/7 | Installs Claude Code via npm if missing |
| 3/7 | `gh auth login --git-protocol ssh` if not already authenticated; verifies SSH to GitHub |
| 4/7 | Clones `ttc-agent-framework` to `%USERPROFILE%\AI-Vault\ttc-agent-framework\` |
| 5/7 | Discovers + clones every accessible `ttc-agent-*` repo into `%USERPROFILE%\AI-Vault\Agents\<dir>\` |
| 6/7 | Clones shared repos (`Claude-Config`, `brand`, `Tools/mcp-proton`); `npm install` for `mcp-proton` |
| 7/7 | Writes `%USERPROFILE%\CLAUDE.md` from template if missing |

**After it finishes:**

```powershell
# Restart PowerShell so PATH updates take effect
exit
# Open new PowerShell, then:
claude
```

**Troubleshooting:**

| Symptom | Fix |
|---|---|
| `winget: command not found` | Update Windows to a recent version (winget ships with App Installer) |
| `gh: not authenticated` after step 3 | Run `gh auth login -h github.com -p ssh` interactively |
| `SSH to git@github.com is NOT working` | See [Appendix A](#appendix-a--ssh-key-setup); use Windows-style key path (`%USERPROFILE%\.ssh\id_ed25519.pub`) |
| Symlinks fall back to copy at the end | See [Appendix C — Windows symlinks](#appendix-c--windows-symlinks) |

---

### 2.2 Windows — Update (existing install)

**Audience:** install already exists; you want today's commits from GitHub.

**Standard mode:**

```powershell
& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\update-all.ps1"
```

**Force mode (reset every repo to `origin`):**

```powershell
& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\update-all.ps1" -Force
```

**Same scope as Mac:** framework, all agents, shared repos, KB scripts.

**Differences from Mac:**

- **No Mini pre-flight** — Windows is treated as a standard git client; it's not in the Syncthing pool, so the race condition that pre-flight protects against on Macs cannot happen here.
- **Symlinks are not refreshed** — if you have copies (because Developer Mode wasn't enabled at migrate time), they don't auto-update. See [Appendix C](#appendix-c--windows-symlinks).

**Expected output:** mirrors the Mac variant; just no `Pre-flight` block.

**Troubleshooting:**

| Symptom | Fix |
|---|---|
| `pull failed (non-FF?)` for a repo | Use `-Force` to reset to origin |
| Permission errors on Windows-protected paths | Run PowerShell as Administrator, OR move install root with `-InstallRoot` to a non-system location |
| Stale `<repo> -- uncommitted changes, skipping` | The repo has working-tree diffs. Commit + push manually, or use `-Force` to discard |

---

### 2.3 Windows — Migrate (pre-2026-05 install)

**Audience:** Windows machine with a TTC install from before 2026-05-09.

**Prerequisites:** same as Mac migration (§ 1.3). Plus:

- **Developer Mode** enabled in `Settings → Privacy & Security → For developers` (lets the script create symlinks without admin rights). If neither Developer Mode nor admin elevation is available, the script transparently falls back to copying files instead of linking — but then your `~/CLAUDE.md` and `~/.claude/commands/` won't auto-pick-up updates from Claude-Config without re-running the migrate script after every Claude-Config change.

**Dry-run first:**

```powershell
& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\migrate-to-2026-05.ps1" -DryRun
```

**Actual run:**

```powershell
& "$env:USERPROFILE\AI-Vault\ttc-agent-framework\scripts\migrate-to-2026-05.ps1"
```

**The 7 steps:** identical structure to the Mac migration, with these Windows-specific differences:

| Step | Windows specifics |
|---|---|
| 1/7 | Same SSH check |
| 2/7 | Same HTTPS → SSH conversion |
| 3/7 | Old `Agents\PPTX\` preserved on disk; the manual cleanup command shown is `Remove-Item -Recurse -Force` |
| 4/7 | Reads `%APPDATA%\Claude\claude_desktop_config.json` instead of `~/Library/...` for the Claude Desktop config. Strips PROTON_PASSWORD using PowerShell's `ConvertFrom-Json -AsHashtable` |
| 5/7 | Probes 3 OneDrive path candidates (SharePoint sync paths vary on Windows): `%USERPROFILE%\TTCGlobal\Branding...`, `%USERPROFILE%\OneDrive - TTCGlobal\...`, `%OneDrive%\Branding...`. Warns if none match. No `chflags` cleanup needed (Windows doesn't have file flags). |
| 6/7 | Symlinks created via `New-Item -ItemType SymbolicLink`. Falls back to copy + warning if symlink creation fails |
| 7/7 | Runs `update-all.ps1 -Force` |

**Note on symlinks:** Windows requires elevated privileges OR Developer Mode for symlinks. If you skipped enabling Developer Mode, the migrate script will warn you and copy the file instead. The copy version is functional but won't track upstream Claude-Config edits — you'll need to re-run migrate periodically or just enable Developer Mode and re-run once.

---

## Appendix A — SSH key setup

Required on every machine before any install/update/migrate routine works.

**Generate key (if you don't have one):**

```bash
# macOS / Linux:
ssh-keygen -t ed25519 -C "$USER@$(hostname -s)"
# accept default path; passphrase optional but recommended
```

```powershell
# Windows:
ssh-keygen -t ed25519 -C "$env:USERNAME@$env:COMPUTERNAME"
```

**Upload to GitHub:**

```bash
# macOS / Linux:
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$USER@$(hostname -s) ($(date +%Y-%m))"
```

```powershell
# Windows:
gh ssh-key add "$env:USERPROFILE\.ssh\id_ed25519.pub" `
  --title "$env:USERNAME@$env:COMPUTERNAME ($(Get-Date -Format 'yyyy-MM'))"
```

**Verify:**

```bash
ssh -T git@github.com
# Expected: "Hi <user>! You've successfully authenticated, but GitHub does not provide shell access."
# Exit code 1 is normal here.
```

**Convention for SSH key titles:** `<user>@<machine> (YYYY-MM)`. Example: `joerg@Mac-mini (2026-05)`. The date stamp lets you spot stale keys when rotating.

---

## Appendix B — 1Password CLI (service account)

Required for: Proton MCP server (Personal / Private agents), some MCP servers that read tokens at runtime.

**On macOS:**

```bash
brew install 1password-cli
op signin                          # interactive: sign in with your 1Password account
# OR for a service-account-based setup (recommended for the Mini):
# 1. Create a service account in 1Password (web UI), scope to "AI Vault"
# 2. Store its token in macOS Keychain:
security add-generic-password -a "$USER" -s OP_SERVICE_ACCOUNT_TOKEN -w
# 3. Source it in shells via ~/.zshenv:
echo 'export OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -a "$USER" -s OP_SERVICE_ACCOUNT_TOKEN -w 2>/dev/null)' >> ~/.zshenv
```

**On Windows:**

```powershell
winget install AgileBits.1Password.CLI
op signin
```

**Verify:**

```bash
op vault list
# expect "AI Vault" in the output
```

**Required item for Proton MCP:** Title `Proton Bridge PWD`, vault `AI Vault`, field `password` = your Proton Bridge **app password** (not the Proton account password).

---

## Appendix C — Windows symlinks

Several files are designed to be symlinks pointing into versioned `Claude-Config/`:

- `%USERPROFILE%\CLAUDE.md` → `AI-Vault\Claude-Config\CLAUDE.md`
- `%USERPROFILE%\.claude\commands` → `AI-Vault\Claude-Config\commands`

**Why symlinks:** when `Claude-Config` is updated (e.g. agent table change after a rename), the live config follows automatically — no manual sync.

**Windows symlink permission requirement:** by default, only Administrators can create symlinks. Two ways to allow non-admin symlinks:

1. **Enable Developer Mode** (recommended): `Settings → Privacy & Security → For developers → Developer Mode: On`. One-time toggle, persists across reboots, no admin rights needed afterwards.
2. **Run PowerShell as Administrator** when running the install or migrate script. Less convenient.

If neither is available, the migrate / install scripts fall back to **copying** the files. Functional, but you must re-run the migrate script (or the equivalent copy commands manually) after every Claude-Config change to stay in sync.

---

## Appendix D — Common environment variables

All routines honour these env vars (set them in your shell or before the command):

| Variable | Default | Purpose |
|---|---|---|
| `TTC_INSTALL_ROOT` | `~/AI-Vault` (Mac), `%USERPROFILE%\AI-Vault` (Windows) | Override install location |
| `TTC_FORCE_RESET` (Mac) | unset | Set to `1` for `--force` behaviour without the flag |
| `TTC_MINI_HOST` (Mac) | `Mac-mini.local` | Override Mini SSH target for `--force` pre-flight |
| `TTC_SKIP_MINI_PRECOMMIT` (Mac) | unset | Set to `1` to skip pre-flight even on a Mac that's not the Mini |

---

## Appendix E — Repository inventory

What gets installed where:

| Repo | Path | Auto-installed | Notes |
|---|---|---|---|
| `ttc-agent-framework` | `~/AI-Vault/ttc-agent-framework/` | yes | This repo (installer + scripts) |
| `ttc-agent-claude-config` | `~/AI-Vault/Claude-Config/` | yes | User-level Claude config + slash commands; symlinked from `~/CLAUDE.md` |
| `ttc-brand-standards` | `~/AI-Vault/brand/` | yes | TTC standard memos. Logos + imagery NOT here — read from OneDrive |
| `ttc-mcp-proton-server` | `~/AI-Vault/Tools/mcp-proton/` | yes | Proton Mail MCP server (1Password-bound) |
| `ttc-agent-oracle-staging` | `~/AI-Vault/Agents/Oracle/` | **no** (parked) | Material for a planned-but-not-built Oracle agent. Install on demand: `gh repo clone ttc-agents/ttc-agent-oracle-staging ~/AI-Vault/Agents/Oracle` |
| `ttc-agent-<name>` (×19) | `~/AI-Vault/Agents/<dir>/` | per agent — see `install-config.json` | One per agent persona |
| `ttc-agent-personal-template` | `~/AI-Vault/Agents/Personal/` | **no** | Sanitized template for sharing. Conflicts with the live `ttc-agent-personal` repo. Install via `add-agent personal-template` if needed |

The full list with apply-keys, dirs, and submodule flags is in [`install-config.json`](../install-config.json).
