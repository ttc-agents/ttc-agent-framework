#!/bin/bash
# update-all.sh — pull latest for framework + every installed agent,
# and refresh runtime KB scripts from the framework versioned copy.
#
# Safe to run any time. Fast-forward pulls only — if you have local
# uncommitted changes, that repo is skipped with a warning.
#
# Usage:
#   update-all.sh                        # default: FF-only, skip dirty repos
#   update-all.sh --force                # GitHub is truth: reset --hard
#                                        # discards local working-tree changes
#                                        # (gitignored files like working/ stay)
#   TTC_INSTALL_ROOT=/path update-all.sh # custom install root
#   TTC_FORCE_RESET=1 update-all.sh      # same as --force via env
#
# Use --force on machines that DON'T auto-commit (e.g. MBA, Windows) where
# Syncthing already shipped your working changes to the always-on machine
# (Mac Mini), which committed + pushed them. Local "modifications" there
# are stale shadows of work that's already on GitHub via the other path.

set -euo pipefail

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=1 ;;
        *) echo "[err] unknown arg: $arg" >&2; exit 2 ;;
    esac
done
if [[ "${TTC_FORCE_RESET:-0}" == "1" ]]; then FORCE=1; fi

INSTALL_ROOT="${TTC_INSTALL_ROOT:-$HOME/AI-Vault}"
FRAMEWORK_DIR="$INSTALL_ROOT/ttc-agent-framework"
AGENTS_DIR="$INSTALL_ROOT/Agents"
KB_RUNTIME_DIR="$INSTALL_ROOT/Claude Folder"

log()        { printf "\033[0;36m[update]\033[0m %s\n" "$*"; }
ok()         { printf "\033[0;32m[ok]\033[0m %s\n" "$*"; }
warn()       { printf "\033[0;33m[warn]\033[0m %s\n" "$*"; }
reset_msg()  { printf "\033[0;35m[reset]\033[0m %s\n" "$*"; }

# Detect the default branch on origin (main / master / something else).
# Falls back to 'main' if the symbolic ref isn't set.
default_branch() {
    local dir="$1"
    local b
    b="$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
    [[ -n "$b" ]] && echo "$b" || echo "main"
}

pull_repo() {
    local dir="$1"
    local name
    name="$(basename "$dir")"
    if [[ ! -d "$dir/.git" ]]; then
        return 0  # skip non-git dirs silently
    fi

    local dirty=0
    if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
        dirty=1
    fi

    # Force mode: GitHub is truth → fetch + hard reset to origin/<default>.
    # Working-tree changes are discarded; gitignored files (working/, .venv,
    # *.log, .DS_Store) are untouched because reset --hard doesn't remove
    # ignored files.
    if [[ "$FORCE" == "1" ]]; then
        local branch before after
        branch="$(default_branch "$dir")"
        if ! git -C "$dir" fetch --quiet origin 2>/dev/null; then
            warn "  $name — fetch failed"
            return 0
        fi
        before="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
        if git -C "$dir" reset --hard "origin/$branch" --quiet 2>/dev/null; then
            after="$(git -C "$dir" rev-parse --short HEAD)"
            if [[ "$dirty" == "1" ]]; then
                reset_msg "  $name — reset to origin/$branch ($before → $after, local changes discarded)"
            elif [[ "$before" != "$after" ]]; then
                ok "  $name — reset to origin/$branch ($before → $after)"
            else
                ok "  $name — already at origin/$branch ($after)"
            fi
        else
            warn "  $name — reset failed"
        fi
        return 0
    fi

    # Default mode: skip dirty, FF-only pull.
    if [[ "$dirty" == "1" ]]; then
        warn "  $name — uncommitted changes, skipping (use --force to discard and reset to origin)"
        return 0
    fi
    if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
        local h
        h="$(git -C "$dir" log -1 --format='%h %s' | cut -c1-70)"
        ok  "  $name — $h"
    else
        warn "  $name — pull failed (non-FF?)"
    fi
}

echo ""
if [[ "$FORCE" == "1" ]]; then
    echo "=== TTC Agent Framework — Update All (FORCE: GitHub is truth) ==="
    warn "  Force mode: local working-tree changes will be DISCARDED."
    warn "  Gitignored files (working/, .venv, *.log) are kept."
else
    echo "=== TTC Agent Framework — Update All ==="
fi
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
