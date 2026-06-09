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
#   TTC_MINI_HOST=user@host              # override Mini SSH target
#                                        # (default: Mac-mini.local)
#   TTC_SKIP_MINI_PRECOMMIT=1            # skip the pre-flight even with --force
#
# Use --force on machines that DON'T auto-commit (e.g. MBA, Windows) — the
# script will pull the latest from GitHub and discard local working-tree
# diffs.
#
# SAFETY — pre-flight Mini commit (Macs only, not Mini itself):
# Other Macs share working trees with the Mini via Syncthing, so --force
# first SSHs to the Mini and triggers its auto-commit. This closes a race
# where: Mini has uncommitted edits → Syncthing already shipped them to
# the Mac → Mac's reset --hard reverts them on disk → mtime bumps →
# Syncthing propagates the revert back to Mini → Mini's pending edits
# silently lost.
# Pre-flight order: ssh Mini → auto-commit-agents.sh → push → Mac reset.
#
# Windows / Linux machines are standard git clients — they're not in the
# Syncthing pool, so the race cannot happen. Pre-flight is skipped
# automatically on non-Darwin hosts.

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

# Source the shared sync helper. Both default and --force modes now go through
# sync_repo_to_origin: fetch → guarded reset --hard origin/<branch> →
# re-materialise. This is what finally lets a *materialised* (always-dirty)
# repo receive new commits and files (e.g. KB docs) — the old default mode
# skipped every dirty repo and silently never pulled them.
export TTC_AI_VAULT="$INSTALL_ROOT" TTC_FRAMEWORK_DIR="$FRAMEWORK_DIR" TTC_HOME="$HOME"
SYNC_HELPER="$FRAMEWORK_DIR/scripts/portability/sync-repo.sh"
if [[ -f "$SYNC_HELPER" ]]; then
    source "$SYNC_HELPER"
else
    warn "sync helper not found at $SYNC_HELPER — falling back to ff-only pulls"
fi

SYNC_FAILURES=0
pull_repo() {
    local dir="$1"
    [[ -d "$dir/.git" ]] || return 0  # skip non-git dirs silently
    if command -v sync_repo_to_origin >/dev/null 2>&1; then
        local rc=0
        if [[ "$FORCE" == "1" ]]; then
            sync_repo_to_origin "$dir" --discard || rc=$?
        else
            sync_repo_to_origin "$dir" || rc=$?
        fi
        [[ $rc -ne 0 ]] && SYNC_FAILURES=$((SYNC_FAILURES + 1))   # B2: track for exit status
        return 0
    fi
    # Fallback (helper missing): preserve the previous best-effort behaviour.
    local name; name="$(basename "$dir")"
    if [[ "$FORCE" == "1" ]]; then
        local branch; branch="$(default_branch "$dir")"
        git -C "$dir" fetch --quiet origin 2>/dev/null && \
            git -C "$dir" reset --hard "origin/$branch" --quiet 2>/dev/null \
            && ok "  $name — reset to origin/$branch" || warn "  $name — update failed"
    elif [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
        warn "  $name — uncommitted changes, skipping (use --force)"
    elif git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
        ok "  $name — $(git -C "$dir" log -1 --format='%h %s' | cut -c1-70)"
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

# Pre-flight: when --force on a non-Mini Mac (= Syncthing-pool member),
# trigger Mini's auto-commit first so origin/main reflects Mini's pending
# edits BEFORE we reset locally. Without this, Syncthing can propagate our
# reset back to Mini and silently clobber its uncommitted state.
# Skipped on non-Darwin hosts (Windows / Linux are not in the Syncthing
# pool — they're standard git clients).
# See header comment for full reasoning.
IS_MAC=0
[[ "$(uname -s)" == "Darwin" ]] && IS_MAC=1

IS_MINI=0
if [[ "$IS_MAC" == "1" ]]; then
    THIS_HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
    if [[ "$THIS_HOST" == *"Mac mini"* ]] || [[ "$(hostname)" == *"Mac-mini"* ]]; then
        IS_MINI=1
    fi
fi

if [[ "$FORCE" == "1" ]] \
        && [[ "$IS_MAC" == "1" ]] \
        && [[ "$IS_MINI" == "0" ]] \
        && [[ "${TTC_SKIP_MINI_PRECOMMIT:-0}" != "1" ]]; then
    MINI_HOST="${TTC_MINI_HOST:-Mac-mini.local}"
    log "Pre-flight: triggering auto-commit on Mac Mini ($MINI_HOST)..."
    if ssh -o ConnectTimeout=4 -o BatchMode=yes "$MINI_HOST" 'true' 2>/dev/null; then
        # Run the Mini's auto-commit script. It is hostname-guarded so it
        # only does anything when actually executed on Mac mini — running
        # via SSH satisfies that.
        if ssh -o ConnectTimeout=10 "$MINI_HOST" \
                'bash "$HOME/AI-Vault/scripts/auto-commit-agents.sh"' >/dev/null 2>&1; then
            ok  "  Mini pre-commit done — origin reflects Mini's latest state"
            sleep 2  # let push fully settle before we fetch
        else
            warn "  Mini pre-commit script returned non-zero — proceeding cautiously"
        fi
    else
        warn "  Mac Mini ($MINI_HOST) not reachable via SSH"
        warn "  Proceeding WITHOUT pre-commit. Risk: if Mini has uncommitted"
        warn "  edits, Syncthing may revert them after this --force run."
        warn "  Set TTC_MINI_HOST=user@host or TTC_SKIP_MINI_PRECOMMIT=1 to silence."
    fi
    echo ""
fi

# 1. Framework — update first; if it advanced, re-exec so the rest of this run
# uses the new code (avoids rewriting the running script mid-flight).
log "Updating framework..."
if command -v sync_framework_and_reexec >/dev/null 2>&1; then
    TTC_SYNC_DISCARD="$FORCE" sync_framework_and_reexec "$FRAMEWORK_DIR" "$FRAMEWORK_DIR/scripts/update-all.sh" ${@+"$@"}
else
    pull_repo "$FRAMEWORK_DIR"
fi

# 2. All agents
echo ""
log "Updating agents..."
if [[ -d "$AGENTS_DIR" ]]; then
    for agent in "$AGENTS_DIR"/*/; do
        pull_repo "${agent%/}"
    done
fi

# 3. Other repos under AI-Vault root (Claude-Config, brand, Tools/mcp-proton)
# These live outside Agents/ but are versioned and need the same update treatment.
echo ""
log "Updating shared repos..."
for shared in \
        "$INSTALL_ROOT/Claude-Config" \
        "$INSTALL_ROOT/brand" \
        "$INSTALL_ROOT/Tools/mcp-proton"; do
    [[ -d "$shared/.git" ]] && pull_repo "$shared"
done

# 4. Refresh runtime KB scripts from the framework's versioned copy
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

# 4b. Refresh Leads shared files from the framework's versioned copy.
# These files (_partition-law.md, _template/, _generic/, _dispatch/) are the source of truth
# in ttc-agent-framework/leads/ and are copied to Agents/Leads/ for runtime use.
echo ""
log "Refreshing Leads shared files..."
LEADS_SRC="$FRAMEWORK_DIR/leads"
LEADS_RUNTIME="$AGENTS_DIR/Leads"
if [[ -d "$LEADS_SRC" ]] && [[ -d "$LEADS_RUNTIME" ]]; then
    cp "$LEADS_SRC/_partition-law.md" "$LEADS_RUNTIME/_partition-law.md"
    ok  "  _partition-law.md → $LEADS_RUNTIME/"
else
    warn "  Leads shared files: src ($LEADS_SRC) or dest ($LEADS_RUNTIME) missing — skipped"
fi

# 4c. Check agent roster drift (warn-only — does NOT auto-write).
# The single source of truth is install-config.json; CLAUDE.md is the generated output.
# Run: generate-roster.py --write  to apply changes.
echo ""
log "Checking agent roster drift (Claude-Config/CLAUDE.md vs install-config.json)..."
ROSTER_SCRIPT="$FRAMEWORK_DIR/scripts/generate-roster.py"
if [[ -f "$ROSTER_SCRIPT" ]]; then
    if python3 "$ROSTER_SCRIPT" --check 2>/dev/null; then
        ok  "  Roster is in sync"
    else
        warn "  Agent roster has drifted — run: python3 $ROSTER_SCRIPT --write"
    fi
else
    warn "  generate-roster.py not found at $ROSTER_SCRIPT — skipped"
fi

# 5. Materialise {{AI_VAULT}} / {{HOME}} placeholders in newly-pulled files.
# Idempotent — files with no placeholders are skipped. Runs on every update
# so freshly-pulled files always reflect this machine's real paths.
echo ""
log "Materialising path placeholders..."
MATERIALISER="$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh"
if [[ -x "$MATERIALISER" ]]; then
    export TTC_AI_VAULT="$INSTALL_ROOT" TTC_HOME="$HOME"
    if [[ -d "$AGENTS_DIR" ]]; then
        for agent in "$AGENTS_DIR"/*/; do
            [[ -d "${agent}.git" ]] && "$MATERIALISER" "${agent%/}" >/dev/null 2>&1 || true
        done
    fi
    for shared in \
            "$INSTALL_ROOT/Claude-Config" \
            "$INSTALL_ROOT/brand" \
            "$INSTALL_ROOT/Tools/mcp-proton"; do
        [[ -d "$shared/.git" ]] && "$MATERIALISER" "$shared" >/dev/null 2>&1 || true
    done
    # Non-repo directories that still need materialising (sanitised content arrives
    # via Syncthing from a machine where the path IS in a repo). Run unconditionally
    # — materialiser is idempotent and only rewrites files that have placeholders.
    for nonrepo in \
            "$INSTALL_ROOT/Claude Folder"; do
        [[ -d "$nonrepo" ]] && "$MATERIALISER" "$nonrepo" >/dev/null 2>&1 || true
    done
    ok  "  Placeholders materialised across agents + shared repos + Claude Folder"
else
    warn "  Materialiser not found at $MATERIALISER — skipped"
fi

echo ""
if [[ "${SYNC_FAILURES:-0}" -gt 0 ]]; then
    warn "Update finished with $SYNC_FAILURES repo(s) that did NOT sync (fetch/reset failed — see warnings above)."
    warn "System-prompt changes take effect in the next conversation."
    exit 1
fi
ok  "Update complete. System-prompt changes take effect in the next conversation."
echo ""
