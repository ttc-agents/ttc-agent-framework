#!/bin/bash
# TTC Agent Framework — One-command installer (macOS / Linux)
#
# Usage (fresh machine):
#   curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
#
# Installs prerequisites, Claude Code, the framework, and every TTC agent
# the authenticated GitHub user has read access to. Idempotent — safe to re-run.

set -euo pipefail

GITHUB_ORG="ttc-agents"
FRAMEWORK_REPO="ttc-agent-framework"
INSTALL_ROOT="${TTC_INSTALL_ROOT:-$HOME/AI-Vault}"
FRAMEWORK_DIR="$INSTALL_ROOT/$FRAMEWORK_REPO"
AGENTS_DIR="$INSTALL_ROOT/Agents"
CLAUDE_MD="$HOME/CLAUDE.md"

log()  { printf "\033[0;36m[install]\033[0m %s\n" "$*"; }
ok()   { printf "\033[0;32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "\033[0;33m[warn]\033[0m %s\n" "$*"; }
err()  { printf "\033[0;31m[err]\033[0m %s\n" "$*" >&2; }

require_cmd() { command -v "$1" >/dev/null 2>&1; }

echo ""
echo "=== TTC Agent Framework — Install (macOS/Linux) ==="
echo "Install root: $INSTALL_ROOT"
echo ""

# --- 1. Prerequisites ---------------------------------------------------------
log "Step 1/7: Checking prerequisites"

if [[ "$(uname -s)" == "Darwin" ]]; then
    if ! require_cmd brew; then
        log "Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add brew to PATH for this session
        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    PKGS=(git gh node python@3.12 1password-cli)
    for pkg in "${PKGS[@]}"; do
        if brew list "$pkg" >/dev/null 2>&1; then
            echo "  [skip] $pkg"
        else
            log "Installing $pkg..."
            brew install "$pkg"
        fi
    done
else
    # Linux — expect apt or dnf; don't auto-install, just verify
    for cmd in git gh node python3; do
        if ! require_cmd "$cmd"; then
            err "$cmd not found. Install it via your package manager and re-run."
            exit 1
        fi
    done
fi
ok "Prerequisites ready"

# --- 2. Claude Code -----------------------------------------------------------
log "Step 2/7: Installing Claude Code"
if require_cmd claude; then
    echo "  [skip] claude already on PATH ($(claude --version 2>/dev/null || echo installed))"
else
    npm install -g @anthropic-ai/claude-code
fi
ok "Claude Code ready"

# --- 3. GitHub auth -----------------------------------------------------------
log "Step 3/7: GitHub authentication"
if gh auth status >/dev/null 2>&1; then
    echo "  [skip] gh already authenticated"
else
    warn "gh is not authenticated. Starting device-flow login..."
    echo "  A short one-time code will be displayed."
    echo "  Open https://github.com/login/device in any browser and paste the code."
    echo "  When prompted, choose 'SSH' as preferred git protocol and accept"
    echo "  uploading your public key — this avoids gh-token-expiry pain later."
    gh auth login --hostname github.com --git-protocol ssh --web
fi

# Verify SSH to GitHub actually works. If gh auth login uploaded a new key
# it should — but we double-check because cron jobs and SSH-spawned shells
# silently fail if SSH auth is broken.
if ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "successfully authenticated"; then
    ok "GitHub ready (SSH)"
else
    warn "SSH to git@github.com is NOT working yet."
    warn "Generate + upload a key:"
    warn "  ssh-keygen -t ed25519 -C \"\$USER@\$(hostname -s)\""
    warn "  gh ssh-key add ~/.ssh/id_ed25519.pub --title \"\$USER@\$(hostname -s) (\$(date +%Y-%m))\""
    warn "Re-run this installer once that's done."
    exit 1
fi

# --- 4. Clone framework -------------------------------------------------------
log "Step 4/7: Cloning framework"
mkdir -p "$INSTALL_ROOT"
if [[ -d "$FRAMEWORK_DIR/.git" ]]; then
    echo "  [skip] framework already cloned — pulling latest"
    git -C "$FRAMEWORK_DIR" pull --ff-only || warn "pull failed, continuing"
else
    git clone "git@github.com:$GITHUB_ORG/$FRAMEWORK_REPO.git" "$FRAMEWORK_DIR"
fi
ok "Framework at $FRAMEWORK_DIR"

# --- 5. Discover + install every accessible agent ----------------------------
log "Step 5/7: Discovering agents you have access to"

ACCESSIBLE_FILE=$(mktemp)
gh repo list "$GITHUB_ORG" --limit 200 --json name --jq '.[].name' 2>/dev/null \
    | grep '^ttc-agent-' | sort -u > "$ACCESSIBLE_FILE"

ACCESSIBLE_COUNT=$(wc -l < "$ACCESSIBLE_FILE" | tr -d ' ')
echo "  Found $ACCESSIBLE_COUNT accessible ttc-agent-* repo(s)."

INSTALL_LIST=$(python3 - "$FRAMEWORK_DIR/install-config.json" "$ACCESSIBLE_FILE" <<'PYEOF'
import json, sys
cfg_path, accessible_path = sys.argv[1], sys.argv[2]
with open(cfg_path) as f:
    cfg = json.load(f)
with open(accessible_path) as f:
    accessible = {line.strip() for line in f if line.strip()}
skip = set(cfg.get("skip_repos", []))
seen_dirs = set()
for agent in cfg.get("agents", []):
    repo = agent["repo"]
    if repo not in accessible:
        continue
    if repo in skip:
        continue
    if not agent.get("auto_install", True):
        continue
    if agent["dir"] in seen_dirs:
        continue
    seen_dirs.add(agent["dir"])
    sub = "true" if agent.get("submodules", False) else "false"
    print(f"{repo}\t{agent['dir']}\t{agent['apply']}\t{sub}")
PYEOF
)
rm -f "$ACCESSIBLE_FILE"

if [[ -z "$INSTALL_LIST" ]]; then
    warn "No accessible agent repos found. Ask the org owner to grant you team access, then re-run."
else
    INSTALL_N=$(echo "$INSTALL_LIST" | wc -l | tr -d ' ')
    ok "$INSTALL_N agent(s) will be installed"
fi

mkdir -p "$AGENTS_DIR"
INSTALLED_AGENTS=()
while IFS=$'\t' read -r REPO DIR APPLY FLAGS; do
    [[ -z "$REPO" ]] && continue
    TARGET="$AGENTS_DIR/$DIR"
    echo ""
    log "  Agent: $APPLY ($REPO)"
    if [[ -d "$TARGET/.git" ]]; then
        echo "    [skip] already cloned - pulling latest"
        git -C "$TARGET" pull --ff-only 2>/dev/null || warn "    pull failed"
        if [[ "$FLAGS" == "true" ]]; then
            git -C "$TARGET" submodule update --init --recursive 2>/dev/null || warn "    submodule update failed"
        fi
    else
        if [[ "$FLAGS" == "true" ]]; then
            git clone --recurse-submodules "git@github.com:$GITHUB_ORG/$REPO.git" "$TARGET"
        else
            git clone "git@github.com:$GITHUB_ORG/$REPO.git" "$TARGET"
        fi
    fi
    # Materialise {{AI_VAULT}} / {{HOME}} placeholders to this machine's paths.
    if [[ -x "$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh" ]]; then
        TTC_AI_VAULT="$INSTALL_ROOT" TTC_HOME="$HOME" \
            "$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh" "$TARGET" >/dev/null \
            || warn "    materialise-paths failed for $APPLY"
    fi
    if [[ -f "$TARGET/install.sh" ]]; then
        (cd "$TARGET" && bash install.sh) || warn "    $APPLY install.sh exited non-zero"
    else
        echo "    [info] no install.sh - clone only"
    fi
    INSTALLED_AGENTS+=("$APPLY:$DIR")
done <<< "$INSTALL_LIST"
ok "Agents installed: ${#INSTALLED_AGENTS[@]}"

# --- 5b. Shared repos (Claude-Config, brand, Tools/mcp-proton) ---------------
# These live outside Agents/ but are versioned and installed alongside agents.
log "Step 6/7: Installing shared repos"

SHARED_LIST=$(python3 - "$FRAMEWORK_DIR/install-config.json" <<'PYEOF'
import json, sys
cfg = json.load(open(sys.argv[1]))
for s in cfg.get("shared_repos", []):
    if s.get("auto_install", True):
        print(f"{s['repo']}\t{s['path']}")
PYEOF
)
while IFS=$'\t' read -r REPO RELPATH; do
    [[ -z "$REPO" ]] && continue
    TARGET="$INSTALL_ROOT/$RELPATH"
    if [[ -d "$TARGET/.git" ]]; then
        echo "  [skip] $REPO already cloned at $RELPATH — pulling latest"
        git -C "$TARGET" pull --ff-only 2>/dev/null || warn "  pull failed"
    else
        mkdir -p "$(dirname "$TARGET")"
        echo "  [clone] $REPO → $RELPATH"
        git clone "git@github.com:$GITHUB_ORG/$REPO.git" "$TARGET"
    fi
    # Materialise placeholders in shared repos too.
    if [[ -x "$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh" ]]; then
        TTC_AI_VAULT="$INSTALL_ROOT" TTC_HOME="$HOME" \
            "$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh" "$TARGET" >/dev/null \
            || warn "  materialise-paths failed for $REPO"
    fi
    # Per-repo follow-up: mcp-proton needs npm install
    if [[ "$REPO" == "ttc-mcp-proton-server" ]] && [[ -f "$TARGET/package.json" ]]; then
        if [[ ! -d "$TARGET/node_modules" ]]; then
            echo "  [npm] installing mcp-proton dependencies..."
            (cd "$TARGET" && npm install --silent) || warn "  npm install failed"
        fi
    fi
done <<< "$SHARED_LIST"
ok "Shared repos installed"

# --- 6. Configure ~/CLAUDE.md -------------------------------------------------
log "Step 7/7: Configuring ~/CLAUDE.md"
if [[ ! -f "$CLAUDE_MD" ]]; then
    TEMPLATE="$FRAMEWORK_DIR/CLAUDE.md.template"
    if [[ -f "$TEMPLATE" ]]; then
        sed "s|{{AGENTS_DIR}}|$AGENTS_DIR|g" "$TEMPLATE" > "$CLAUDE_MD"
        ok "Created $CLAUDE_MD from template"
    else
        {
            echo "# Claude Code - Agent Routing"
            echo ""
            echo "When the user says **\"apply <agent>\"**, read the matching system prompt and adopt it fully."
            echo ""
            echo "| Command | System Prompt File |"
            echo "|---|---|"
        } > "$CLAUDE_MD"
    fi
fi

for entry in "${INSTALLED_AGENTS[@]}"; do
    IFS=':' read -r APPLY DIR <<< "$entry"
    LINE="| \`apply $APPLY\` | \`$AGENTS_DIR/$DIR/system-prompt.md\` |"
    if grep -qE "^\| \`apply $APPLY\`" "$CLAUDE_MD"; then
        echo "  [skip] apply $APPLY already registered"
    else
        echo "$LINE" >> "$CLAUDE_MD"
        echo "  [add]  apply $APPLY"
    fi
done
ok "~/CLAUDE.md configured"

# --- 6b. Install KB framework (two-tier KB) ----------------------------------
log "Step 6b/6: Installing KB framework (scripts + conventions)"
KB_RUNTIME_DIR="$INSTALL_ROOT/Claude Folder"
KB_SRC="$FRAMEWORK_DIR/scripts/kb"
KB_DOCS_SRC="$FRAMEWORK_DIR/docs/KB_CONVENTIONS.md"
mkdir -p "$KB_RUNTIME_DIR" "$INSTALL_ROOT/docs"
if [[ -d "$KB_SRC" ]]; then
    cp "$KB_SRC/kb_bootstrap_customer.sh"   "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/kb_refresh_customer.sh"     "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/kb_discover_customers.sh"   "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/kb_discover_customers.py"   "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/convert_to_knowledge_base.py" "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/kb_vectorize.py"            "$KB_RUNTIME_DIR/"
    chmod +x "$KB_RUNTIME_DIR/"kb_*.sh 2>/dev/null || true
    # Materialise placeholders in the freshly-copied KB scripts. Source files
    # in scripts/kb/ may be sanitised (committed form) — cp doesn't substitute,
    # so run the materialiser on the destination explicitly.
    if [[ -x "$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh" ]]; then
        TTC_AI_VAULT="$INSTALL_ROOT" TTC_HOME="$HOME" \
            "$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh" "$KB_RUNTIME_DIR" >/dev/null \
            || warn "  materialise-paths failed for $KB_RUNTIME_DIR"
    fi
    ok "KB scripts deployed to $KB_RUNTIME_DIR/"
fi
if [[ -f "$KB_DOCS_SRC" ]]; then
    cp "$KB_DOCS_SRC" "$INSTALL_ROOT/docs/KB_CONVENTIONS.md"
    ok "KB_CONVENTIONS.md deployed to $INSTALL_ROOT/docs/"
fi
REGISTRY="$KB_RUNTIME_DIR/Knowledge Base/_customer_registry.json"
if [[ ! -f "$REGISTRY" ]]; then
    mkdir -p "$(dirname "$REGISTRY")"
    cat > "$REGISTRY" <<'JSON'
{
  "schema_version": "1.0",
  "last_updated": "",
  "description": "Maps customers to their primary OneDrive folder and AI-INFO KB location. Edited by kb_bootstrap_customer.sh.",
  "customers": {}
}
JSON
    ok "Empty customer registry seeded at $REGISTRY"
fi

# --- 7. Minimal MCP config ----------------------------------------------------
log "Minimal MCP config"
MCP_JSON="$HOME/.claude.json"
if [[ -f "$MCP_JSON" ]]; then
    echo "  [skip] $MCP_JSON exists — not touching"
else
    cat > "$MCP_JSON" <<JSON
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "$INSTALL_ROOT"]
    }
  }
}
JSON
    ok "Wrote starter $MCP_JSON (filesystem root: $INSTALL_ROOT)"
fi

# --- Summary ------------------------------------------------------------------
echo ""
echo "=== Install complete ==="
echo "  Install root: $INSTALL_ROOT"
echo "  Framework:    $FRAMEWORK_DIR"
echo "  Agents:       $AGENTS_DIR"
echo "  CLAUDE.md:    $CLAUDE_MD"
echo ""
echo "Next steps:"
echo "  1. Run 'claude' to authenticate Claude Code"
echo "  2. Inside Claude Code, type one of your installed agents:"
for entry in "${INSTALLED_AGENTS[@]:-}"; do
    IFS=':' read -r APPLY DIR <<< "$entry"
    [[ -n "$APPLY" ]] && echo "       apply $APPLY"
done
echo "  3. To add more agents later (e.g. if you get access to a new one):"
echo "       $FRAMEWORK_DIR/scripts/add-agent.sh <name>"
echo ""
