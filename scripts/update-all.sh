#!/bin/bash
# update-all.sh — pull latest for framework + every installed agent,
# and refresh runtime KB scripts from the framework versioned copy.
#
# Safe to run any time. Fast-forward pulls only — if you have local
# uncommitted changes, that repo is skipped with a warning.
#
# Usage:
#   update-all.sh                        # default paths
#   TTC_INSTALL_ROOT=/path update-all.sh # custom install root

set -euo pipefail

INSTALL_ROOT="${TTC_INSTALL_ROOT:-$HOME/AI-Vault}"
FRAMEWORK_DIR="$INSTALL_ROOT/ttc-agent-framework"
AGENTS_DIR="$INSTALL_ROOT/Agents"
KB_RUNTIME_DIR="$INSTALL_ROOT/Claude Folder"

log()  { printf "\033[0;36m[update]\033[0m %s\n" "$*"; }
ok()   { printf "\033[0;32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "\033[0;33m[warn]\033[0m %s\n" "$*"; }

pull_repo() {
    local dir="$1"
    local name
    name="$(basename "$dir")"
    if [[ ! -d "$dir/.git" ]]; then
        return 0  # skip non-git dirs silently
    fi
    # dirty check
    if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
        warn "  $name — uncommitted changes, skipping"
        return 0
    fi
    # pull FF-only
    if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
        local h
        h="$(git -C "$dir" log -1 --format='%h %s' | cut -c1-70)"
        ok  "  $name — $h"
    else
        warn "  $name — pull failed (non-FF?)"
    fi
}

echo ""
echo "=== TTC Agent Framework — Update All ==="
echo ""

# 1. Framework
log "Updating framework..."
pull_repo "$FRAMEWORK_DIR"

# 2. All agents
echo ""
log "Updating agents..."
if [[ -d "$AGENTS_DIR" ]]; then
    for agent in "$AGENTS_DIR"/*/; do
        pull_repo "${agent%/}"
    done
fi

# 3. Refresh runtime KB scripts from the framework's versioned copy
echo ""
log "Refreshing runtime KB scripts..."
KB_SRC="$FRAMEWORK_DIR/scripts/kb"
KB_DOCS_SRC="$FRAMEWORK_DIR/docs/KB_CONVENTIONS.md"
if [[ -d "$KB_SRC" ]]; then
    mkdir -p "$KB_RUNTIME_DIR" "$INSTALL_ROOT/docs"
    cp "$KB_SRC/kb_bootstrap_customer.sh"     "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/kb_refresh_customer.sh"       "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/kb_discover_customers.sh"     "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/kb_discover_customers.py"     "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/convert_to_knowledge_base.py" "$KB_RUNTIME_DIR/"
    cp "$KB_SRC/kb_vectorize.py"              "$KB_RUNTIME_DIR/"
    chmod +x "$KB_RUNTIME_DIR/"kb_*.sh 2>/dev/null || true
    ok  "  KB scripts → $KB_RUNTIME_DIR/"
fi
if [[ -f "$KB_DOCS_SRC" ]]; then
    cp "$KB_DOCS_SRC" "$INSTALL_ROOT/docs/KB_CONVENTIONS.md"
    ok  "  KB_CONVENTIONS.md → $INSTALL_ROOT/docs/"
fi

echo ""
ok  "Update complete. System-prompt changes take effect in the next conversation."
echo ""
