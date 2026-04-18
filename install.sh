#!/bin/bash
# TTC Agent Framework — One-command installer (macOS / Linux)
#
# Usage (fresh machine):
#   curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
#
# Installs prerequisites, Claude Code, the framework, and the standard bundle
# of 4 work agents (SAP, Test, TAF, Tender). Idempotent — safe to re-run.

set -euo pipefail

GITHUB_ORG="ttc-agents"
FRAMEWORK_REPO="ttc-agent-framework"
INSTALL_ROOT="${TTC_INSTALL_ROOT:-$HOME/AI-Vault}"
FRAMEWORK_DIR="$INSTALL_ROOT/$FRAMEWORK_REPO"
AGENTS_DIR="$INSTALL_ROOT/Agents"
CLAUDE_MD="$HOME/CLAUDE.md"

BASE_AGENTS=(
    "ttc-agent-sap:SAP:sap:submodules"
    "ttc-agent-test:Test:test:-"
    "ttc-agent-taf:TAF:taf:-"
    "ttc-agent-tender:Tender:tender:-"
)

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
    warn "gh is not authenticated. Launching interactive login..."
    gh auth login
fi
ok "GitHub ready"

# --- 4. Clone framework -------------------------------------------------------
log "Step 4/7: Cloning framework"
mkdir -p "$INSTALL_ROOT"
if [[ -d "$FRAMEWORK_DIR/.git" ]]; then
    echo "  [skip] framework already cloned — pulling latest"
    git -C "$FRAMEWORK_DIR" pull --ff-only || warn "pull failed, continuing"
else
    gh repo clone "$GITHUB_ORG/$FRAMEWORK_REPO" "$FRAMEWORK_DIR"
fi
ok "Framework at $FRAMEWORK_DIR"

# --- 5. Install base bundle ---------------------------------------------------
log "Step 5/7: Installing base agent bundle"
mkdir -p "$AGENTS_DIR"
for entry in "${BASE_AGENTS[@]}"; do
    IFS=':' read -r REPO DIR APPLY FLAGS <<< "$entry"
    TARGET="$AGENTS_DIR/$DIR"
    echo ""
    log "  Agent: $APPLY ($REPO)"
    if [[ -d "$TARGET/.git" ]]; then
        echo "    [skip] already cloned — pulling latest"
        git -C "$TARGET" pull --ff-only || warn "    pull failed"
        if [[ "$FLAGS" == "submodules" ]]; then
            git -C "$TARGET" submodule update --init --recursive || warn "    submodule update failed"
        fi
    else
        if [[ "$FLAGS" == "submodules" ]]; then
            gh repo clone "$GITHUB_ORG/$REPO" "$TARGET" -- --recurse-submodules
        else
            gh repo clone "$GITHUB_ORG/$REPO" "$TARGET"
        fi
    fi
    if [[ -x "$TARGET/install.sh" ]]; then
        (cd "$TARGET" && ./install.sh) || warn "    $APPLY install.sh exited non-zero"
    elif [[ -f "$TARGET/install.sh" ]]; then
        (cd "$TARGET" && bash install.sh) || warn "    $APPLY install.sh exited non-zero"
    else
        echo "    [info] no install.sh — clone only"
    fi
done
ok "Base bundle installed"

# --- 6. Write ~/CLAUDE.md -----------------------------------------------------
log "Step 6/7: Configuring ~/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
    for entry in "${BASE_AGENTS[@]}"; do
        IFS=':' read -r REPO DIR APPLY FLAGS <<< "$entry"
        LINE="| \`apply $APPLY\` | \`$AGENTS_DIR/$DIR/system-prompt.md\` |"
        if grep -qE "^\| \`apply $APPLY\`" "$CLAUDE_MD"; then
            echo "  [skip] apply $APPLY already registered"
        else
            echo "$LINE" >> "$CLAUDE_MD"
            echo "  [add]  apply $APPLY"
        fi
    done
else
    TEMPLATE="$FRAMEWORK_DIR/CLAUDE.md.template"
    if [[ -f "$TEMPLATE" ]]; then
        sed "s|{{AGENTS_DIR}}|$AGENTS_DIR|g" "$TEMPLATE" > "$CLAUDE_MD"
        ok "Created $CLAUDE_MD from template"
    else
        warn "Template not found — writing minimal CLAUDE.md"
        {
            echo "# Claude Code — Agent Routing"
            echo ""
            echo "When the user says **\"apply <agent>\"**, read the matching system prompt and adopt it fully."
            echo ""
            echo "| Command | System Prompt File |"
            echo "|---|---|"
            for entry in "${BASE_AGENTS[@]}"; do
                IFS=':' read -r REPO DIR APPLY FLAGS <<< "$entry"
                echo "| \`apply $APPLY\` | \`$AGENTS_DIR/$DIR/system-prompt.md\` |"
            done
        } > "$CLAUDE_MD"
    fi
fi
ok "~/CLAUDE.md configured"

# --- 7. Minimal MCP config ----------------------------------------------------
log "Step 7/7: Minimal MCP config"
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
echo "  2. Inside Claude Code, try: apply sap | apply test | apply taf | apply tender"
echo "  3. Add more agents any time:"
echo "       $FRAMEWORK_DIR/scripts/add-agent.sh <name>"
echo ""
