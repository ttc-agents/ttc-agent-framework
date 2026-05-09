#!/bin/bash
# migrate-to-2026-05.sh — bring an old TTC Agent installation up to the
# 2026-05-09 layout in one idempotent pass.
#
# What changed between old and new:
#
#   1. PPTX agent renamed → Docs agent. `apply pptx` is now `apply docs`.
#      Repo: ttc-agent-pptx → ttc-agent-docs. Old PPTX/ folder → Docs/.
#
#   2. mcp-proton MCP server moved out of ~/Personal/ into ~/AI-Vault/Tools/
#      and is now version-controlled (ttc-mcp-proton-server). Configs no
#      longer carry plaintext PROTON_PASSWORD; the server reads it from
#      1Password ("Proton Bridge PWD" in vault "AI Vault").
#
#   3. Brand assets split:
#        - logos + imagery now read from OneDrive directly via
#          Agents/Docs/brand_paths.py (no more local cache)
#        - standards memos live in their own repo: ttc-brand-standards
#          → ~/AI-Vault/brand/
#
#   4. Git remotes switched HTTPS → SSH (no more gh-token-expiry pain).
#
#   5. CLAUDE.md is a symlink to AI-Vault/Claude-Config/CLAUDE.md
#      (was already done March 2026 on most installs — this script is
#      idempotent and only fixes if missing).
#
# Safe to run multiple times. Each step checks current state before acting.
# Detects whether we're on the always-on Mac mini (auto-commits) or another
# machine, and behaves accordingly.
#
# Usage:
#   bash migrate-to-2026-05.sh [--dry-run]

set -euo pipefail

DRY=0
for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY=1
done

INSTALL_ROOT="${TTC_INSTALL_ROOT:-$HOME/AI-Vault}"
AGENTS_DIR="$INSTALL_ROOT/Agents"
GITHUB_ORG="ttc-agents"

log()   { printf "\033[0;36m[migrate]\033[0m %s\n" "$*"; }
ok()    { printf "\033[0;32m[ok]\033[0m %s\n" "$*"; }
warn()  { printf "\033[0;33m[warn]\033[0m %s\n" "$*"; }
err()   { printf "\033[0;31m[err]\033[0m %s\n" "$*" >&2; }
do_it() { if (( DRY )); then echo "  DRY: $*"; else eval "$@"; fi; }

echo ""
echo "=== TTC Agent Framework — Migration to 2026-05 layout ==="
[[ "$DRY" == "1" ]] && warn "DRY-RUN MODE — no changes will be made"
echo "Install root: $INSTALL_ROOT"
echo ""

# ─── 1. Verify SSH to GitHub works (everything depends on this) ─────────────
log "Step 1/8: Verify SSH access to GitHub"
# `ssh -T git@github.com` always exits 1 (GitHub explicitly closes the shell),
# so we capture stderr and look for the success banner instead of relying on
# the exit code. With set -o pipefail we'd otherwise misread the SSH probe.
SSH_OUT="$(ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)"
if [[ "$SSH_OUT" == *"successfully authenticated"* ]]; then
    ok "SSH to git@github.com works"
else
    err "SSH to GitHub is NOT working. Fix this first:"
    err "  ssh-keygen -t ed25519 -C \"\$USER@\$(hostname -s)\""
    err "  gh ssh-key add ~/.ssh/id_ed25519.pub --title \"\$USER@\$(hostname -s) (\$(date +%Y-%m))\""
    err "Probe output was:"
    err "  $SSH_OUT"
    exit 1
fi

# ─── 2. Bootstrap: ensure ttc-agent-framework is present + current ──────────
# The migrate script normally lives inside the framework, but it can also be
# curl'd standalone from GitHub. Either way, every later step needs the
# framework's scripts on disk, so we make sure of it now.
log "Step 2/8: Bootstrap framework"
FRAMEWORK_DIR="$INSTALL_ROOT/ttc-agent-framework"
if [[ -d "$FRAMEWORK_DIR/.git" ]]; then
    log "  Framework present — pulling latest"
    if (( DRY )); then
        echo "  DRY: git -C \"$FRAMEWORK_DIR\" pull --ff-only"
    else
        git -C "$FRAMEWORK_DIR" pull --ff-only --quiet 2>/dev/null \
            || warn "  pull failed (probably divergent local commits) — continuing"
    fi
else
    log "  Framework not yet on disk — cloning"
    do_it "mkdir -p \"$INSTALL_ROOT\""
    do_it "git clone git@github.com:$GITHUB_ORG/ttc-agent-framework.git \"$FRAMEWORK_DIR\""
fi
ok "Framework at $FRAMEWORK_DIR"

# ─── 3. Convert HTTPS remotes to SSH ────────────────────────────────────────
log "Step 3/8: Convert HTTPS remotes to SSH"
CONVERTED=0
for d in "$AGENTS_DIR"/*/ \
         "$INSTALL_ROOT/ttc-agent-framework" \
         "$INSTALL_ROOT/Claude-Config" \
         "$INSTALL_ROOT/brand" \
         "$INSTALL_ROOT/Tools/mcp-proton"; do
    [[ -d "$d/.git" ]] || continue
    url=$(git -C "$d" remote get-url origin 2>/dev/null || echo "")
    if [[ "$url" == https://github.com/* ]]; then
        new="${url/https:\/\/github.com\//git@github.com:}"
        do_it "git -C \"$d\" remote set-url origin \"$new\""
        CONVERTED=$((CONVERTED+1))
    fi
done
ok "$CONVERTED remote(s) converted to SSH"

# ─── 3. Old PPTX agent → Docs agent ─────────────────────────────────────────
log "Step 4/8: Migrate PPTX agent to Docs"
if [[ -d "$AGENTS_DIR/PPTX" ]] && [[ ! -d "$AGENTS_DIR/Docs" ]]; then
    log "  Found old Agents/PPTX/ but no Agents/Docs/ — cloning Docs from GitHub"
    do_it "git clone git@github.com:$GITHUB_ORG/ttc-agent-docs.git \"$AGENTS_DIR/Docs\""
    warn "  Old Agents/PPTX/ is preserved on disk for safety. Verify Docs/ has all"
    warn "  your customer work, then remove it manually:"
    warn "    rm -rf \"$AGENTS_DIR/PPTX\""
elif [[ -d "$AGENTS_DIR/PPTX" ]] && [[ -d "$AGENTS_DIR/Docs" ]]; then
    warn "  Both Agents/PPTX/ and Agents/Docs/ exist. Verify Docs/ is current,"
    warn "  then remove old PPTX dir manually: rm -rf \"$AGENTS_DIR/PPTX\""
elif [[ ! -d "$AGENTS_DIR/Docs" ]]; then
    log "  Neither exists — installing Docs"
    do_it "git clone git@github.com:$GITHUB_ORG/ttc-agent-docs.git \"$AGENTS_DIR/Docs\""
fi
# Update ~/CLAUDE.md if it has 'apply pptx' (only matters if not symlinked yet)
if [[ -f "$HOME/CLAUDE.md" ]] && [[ ! -L "$HOME/CLAUDE.md" ]] && grep -q "apply pptx" "$HOME/CLAUDE.md"; then
    warn "  ~/CLAUDE.md still references 'apply pptx' — handled in Step 6 below"
fi
ok "Docs agent in place"

# ─── 4. mcp-proton: ~/Personal → AI-Vault/Tools, into git, password to 1P ─
log "Step 5/8: Relocate + version mcp-proton"
TOOLS_PROTON="$INSTALL_ROOT/Tools/mcp-proton"
if [[ ! -d "$TOOLS_PROTON/.git" ]]; then
    if [[ -d "$HOME/Personal/mcp-proton" ]] && [[ ! -L "$HOME/Personal/mcp-proton" ]]; then
        log "  Found old ~/Personal/mcp-proton/ — replacing with git clone"
        do_it "mkdir -p \"$INSTALL_ROOT/Tools\""
        do_it "rm -rf \"$TOOLS_PROTON\""
        do_it "git clone git@github.com:$GITHUB_ORG/ttc-mcp-proton-server.git \"$TOOLS_PROTON\""
        do_it "(cd \"$TOOLS_PROTON\" && npm install --silent) || echo '  (npm install issues)'"
        do_it "rm -rf \"$HOME/Personal/mcp-proton\""
    else
        log "  No existing ~/Personal/mcp-proton — fresh clone"
        do_it "mkdir -p \"$INSTALL_ROOT/Tools\""
        do_it "git clone git@github.com:$GITHUB_ORG/ttc-mcp-proton-server.git \"$TOOLS_PROTON\""
        do_it "(cd \"$TOOLS_PROTON\" && npm install --silent) || echo '  (npm install issues)'"
    fi
else
    ok "  Tools/mcp-proton already a git repo — skipping clone"
fi

# Strip PROTON_PASSWORD + rewrite mcp-proton path in all 4 known config files
log "  Patching configs (path → AI-Vault/Tools, remove plaintext password)"
CFGS=(
    "$HOME/.claude.json"
    "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    "$INSTALL_ROOT/Claude-Config/.mcp.json"
    "$INSTALL_ROOT/Claude-Config/claude_desktop_config.json"
)
PATCHED=0
for cfg in "${CFGS[@]}"; do
    [[ -f "$cfg" ]] || continue
    if grep -q "/Personal/mcp-proton/\|PROTON_PASSWORD" "$cfg" 2>/dev/null; then
        if (( DRY )); then
            echo "  DRY: would patch $cfg"
        else
            python3 - "$cfg" <<'PYEOF'
import json, sys
p = sys.argv[1]
data = json.loads(open(p).read())
def walk(node):
    n = 0
    if isinstance(node, dict):
        if "args" in node and isinstance(node["args"], list):
            node["args"] = [a.replace("/Personal/mcp-proton/", "/AI-Vault/Tools/mcp-proton/") if isinstance(a, str) else a for a in node["args"]]
        if "env" in node and isinstance(node["env"], dict) and "PROTON_PASSWORD" in node["env"]:
            del node["env"]["PROTON_PASSWORD"]; n += 1
        for v in node.values():
            n += walk(v)
    elif isinstance(node, list):
        for v in node:
            n += walk(v)
    return n
walk(data)
open(p, "w").write(json.dumps(data, indent=2) + "\n")
PYEOF
            PATCHED=$((PATCHED+1))
        fi
    fi
done
ok "  Patched $PATCHED config(s); password now resolved from 1Password at runtime"
# Tidy up ~/Personal if it's now empty (no children remain after mcp-proton moved out)
if [[ -d "$HOME/Personal" ]] && [[ -z "$(ls -A "$HOME/Personal" 2>/dev/null | grep -v '^\.DS_Store$' || true)" ]]; then
    do_it "rm -rf \"$HOME/Personal\""
    ok "  removed empty ~/Personal"
fi

# ─── 5. Brand-split: clone ttc-brand-standards, drop old imagery/logos ──────
log "Step 6/8: Brand split (logos + imagery → OneDrive)"
BRAND_DIR="$INSTALL_ROOT/brand"
if [[ ! -d "$BRAND_DIR/.git" ]]; then
    if [[ -d "$BRAND_DIR" ]]; then
        log "  Existing brand/ folder is not a git repo — replacing with ttc-brand-standards"
        do_it "mv \"$BRAND_DIR\" \"$BRAND_DIR.tmp\""
        do_it "git clone git@github.com:$GITHUB_ORG/ttc-brand-standards.git \"$BRAND_DIR\""
        # Restore manifest.json if it existed (gitignored, machine-local)
        if [[ -f "$BRAND_DIR.tmp/manifest.json" ]]; then
            do_it "cp \"$BRAND_DIR.tmp/manifest.json\" \"$BRAND_DIR/manifest.json\""
        fi
        do_it "rm -rf \"$BRAND_DIR.tmp\""
    else
        do_it "git clone git@github.com:$GITHUB_ORG/ttc-brand-standards.git \"$BRAND_DIR\""
    fi
else
    ok "  brand/ already a git repo — pulling latest"
    do_it "git -C \"$BRAND_DIR\" pull --ff-only"
fi

# Old local imagery + logos cache → delete (assets read from OneDrive now)
for stale in "$BRAND_DIR/imagery" "$BRAND_DIR/logos"; do
    if [[ -d "$stale" ]]; then
        log "  Removing stale local cache: $stale"
        # Some old caches had chflags uchg set
        do_it "chflags -R nouchg \"$stale\" 2>/dev/null || true"
        do_it "rm -rf \"$stale\""
    fi
done

# Verify OneDrive central branding is mounted (else warn)
ONEDRIVE_BRAND="$HOME/Library/CloudStorage/OneDrive-SharedLibraries-TTCGlobal/Branding - TTC Global Branding"
if [[ ! -d "$ONEDRIVE_BRAND" ]]; then
    warn "  OneDrive central branding NOT found at: $ONEDRIVE_BRAND"
    warn "  Sign in to OneDrive and sync the 'Branding - TTC Global Branding' library."
    warn "  Without it, the Docs agent's logo + imagery references will fail."
else
    ok "  OneDrive central branding mounted"
fi

# ─── 6. ~/CLAUDE.md → symlink to Claude-Config ──────────────────────────────
log "Step 7/8: Ensure ~/CLAUDE.md is a symlink to Claude-Config"
CLAUDE_MD="$HOME/CLAUDE.md"
TARGET_MD="$INSTALL_ROOT/Claude-Config/CLAUDE.md"
if [[ ! -d "$INSTALL_ROOT/Claude-Config/.git" ]]; then
    log "  Cloning Claude-Config (was missing)"
    do_it "git clone git@github.com:$GITHUB_ORG/ttc-agent-claude-config.git \"$INSTALL_ROOT/Claude-Config\""
fi
if [[ -L "$CLAUDE_MD" ]]; then
    ok "  ~/CLAUDE.md already a symlink → $(readlink "$CLAUDE_MD")"
elif [[ -f "$CLAUDE_MD" ]]; then
    log "  Backing up existing ~/CLAUDE.md and replacing with symlink"
    do_it "mv \"$CLAUDE_MD\" \"$CLAUDE_MD.pre-migrate-$(date +%Y%m%d)\""
    do_it "ln -s \"$TARGET_MD\" \"$CLAUDE_MD\""
else
    do_it "ln -s \"$TARGET_MD\" \"$CLAUDE_MD\""
fi

# Same for ~/.claude/commands → Claude-Config/commands
COMMANDS_LINK="$HOME/.claude/commands"
COMMANDS_TARGET="$INSTALL_ROOT/Claude-Config/commands"
if [[ -L "$COMMANDS_LINK" ]]; then
    ok "  ~/.claude/commands already a symlink"
elif [[ -d "$COMMANDS_TARGET" ]]; then
    if [[ -e "$COMMANDS_LINK" ]]; then
        do_it "mv \"$COMMANDS_LINK\" \"$COMMANDS_LINK.pre-migrate-$(date +%Y%m%d)\""
    fi
    do_it "mkdir -p \"$HOME/.claude\""
    do_it "ln -s \"$COMMANDS_TARGET\" \"$COMMANDS_LINK\""
fi

# ─── 7. Final pull-everything-current ───────────────────────────────────────
log "Step 8/8: Pull every repo to its current GitHub state"
if [[ "$DRY" == "1" ]]; then
    echo "  DRY: would run update-all.sh --force"
else
    if [[ -x "$INSTALL_ROOT/ttc-agent-framework/scripts/update-all.sh" ]]; then
        bash "$INSTALL_ROOT/ttc-agent-framework/scripts/update-all.sh" --force
    else
        warn "  ttc-agent-framework/scripts/update-all.sh not found — skipping"
    fi
fi

echo ""
ok "Migration complete."
echo ""
echo "Manual verification recommended:"
echo "  1. Open Claude Desktop and try Proton tools (mcp__proton__list_mailboxes)"
echo "  2. Try 'apply docs' to confirm the new Docs agent loads"
echo "  3. Run a Word generation test (LOGO_PATH should resolve to OneDrive)"
echo ""
