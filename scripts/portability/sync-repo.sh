#!/bin/bash
# sync-repo.sh — bring a managed repo's working tree to origin truth, safely.
#
# Source this file, then call:   sync_repo_to_origin <target_dir> [--discard]
#
# WHY THIS EXISTS
# Managed agent/shared repos are kept in a *materialised* state on disk: the
# path placeholders ({{AI_VAULT}}, {{HOME}}, {{ONEDRIVE_SHARED}}) are replaced
# with this machine's real paths so LaunchAgents/scripts can run. That makes
# the working tree permanently dirty vs. the committed (placeholder/sanitised)
# form on origin. Consequently `git pull --ff-only` ALWAYS fails/skips, so new
# commits — and new files like Knowledge Base docs — never arrive. The old
# code paths hid that failure (`2>&1 | Out-Null`, silent "skip dirty").
#
# THE FIX
# Materialised dirt is *reproducible derived state*, not authored content
# (authoring is owned by scripts/auto-commit-agents.sh). So the safe primitive
# is: fetch → reset --hard origin/<branch> → re-materialise. This is the same
# pattern update-all's --force already used; we factor it out, surface errors,
# and add guards so it is also safe as the DEFAULT path on Joerg's authoring
# machine.
#
# We deliberately do NOT use `git stash → pull → stash pop`: the stash holds
# absolute paths while origin holds placeholders on the SAME lines, so stash
# pop conflicts on every path-bearing line (see
# docs/plans/2026-06-09-auto-commit-divergence-fix.md).
#
# GUARDS (skipped by --discard, which restores the old destructive --force):
#   1. Unpushed local commits  → never discarded; reset is skipped, repo is
#      only re-materialised, and the commits are left for auto-commit to push.
#   2. Authored working-tree edits (only where the sanitiser is present, i.e.
#      Joerg's machine) → detected by round-tripping the tree through the
#      sanitiser and diffing against HEAD; if anything beyond materialisation
#      remains, reset is skipped and the edits are left for auto-commit.
#
# Idempotent. Errors are reported, never swallowed.

# --- logging: delegate to the caller's helpers if present, else fall back ----
_sr_log()   { if command -v log        >/dev/null 2>&1; then log   "$@"; else printf "\033[0;36m[sync]\033[0m %s\n"  "$*"; fi; }
_sr_ok()    { if command -v ok         >/dev/null 2>&1; then ok    "$@"; else printf "\033[0;32m[ok]\033[0m %s\n"    "$*"; fi; }
_sr_warn()  { if command -v warn       >/dev/null 2>&1; then warn  "$@"; else printf "\033[0;33m[warn]\033[0m %s\n"  "$*"; fi; }

_sr_default_branch() {
    local b
    b="$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
    [[ -n "$b" ]] && echo "$b" || echo "main"
}

# Re-apply this machine's real paths to a freshly-synced tree. Forwards the
# same env the installers/updaters use; materialiser is idempotent.
_sr_materialise() {
    local dir="$1" mat="$2"
    if [[ ! -x "$mat" ]]; then
        _sr_warn "  $(basename "$dir") — materialiser not found at $mat; left in committed form"
        return 0
    fi
    TTC_AI_VAULT="${TTC_AI_VAULT:-${TTC_INSTALL_ROOT:-$HOME/AI-Vault}}" \
    TTC_HOME="${TTC_HOME:-$HOME}" \
        "$mat" "$dir" >/dev/null 2>&1 \
        || _sr_warn "  $(basename "$dir") — materialise-paths failed"
}

# sync_repo_to_origin <target_dir> [--discard]
sync_repo_to_origin() {
    local dir="" discard=0 a
    for a in "$@"; do
        case "$a" in
            --discard) discard=1 ;;
            -*)        _sr_warn "sync_repo_to_origin: unknown flag '$a' (ignored)" ;;
            *)         dir="$a" ;;
        esac
    done
    [[ -n "$dir" ]]        || { _sr_warn "sync_repo_to_origin: no target dir given"; return 2; }
    [[ -d "$dir/.git" ]]   || return 0   # not a git repo — skip silently
    local name; name="$(basename "$dir")"

    # Locate the materialiser + sanitiser. Primary source is the install root
    # the callers already know and export (TTC_AI_VAULT / TTC_INSTALL_ROOT,
    # optional TTC_FRAMEWORK_DIR); fall back to this file's own location, then
    # to $HOME/AI-Vault. No hard-coded home path — the helper stays portable.
    local aivault_root="${TTC_AI_VAULT:-${TTC_INSTALL_ROOT:-$HOME/AI-Vault}}"
    local fw_dir="${TTC_FRAMEWORK_DIR:-$aivault_root/ttc-agent-framework}"
    local materialiser="${TTC_MATERIALISER:-$fw_dir/scripts/portability/materialise-paths.sh}"
    local sanitiser="${TTC_SANITISER:-$aivault_root/scripts/portability/sanitise-paths.sh}"
    if [[ ! -x "$materialiser" && -n "${BASH_SOURCE[0]:-}" ]]; then
        local self_dir; self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
        [[ -x "$self_dir/materialise-paths.sh" ]] && materialiser="$self_dir/materialise-paths.sh"
    fi

    # Fetch — surface failure, never reset against a stale remote-tracking ref.
    if ! git -C "$dir" fetch --quiet origin 2>/dev/null; then
        _sr_warn "  $name — fetch failed (offline / SSH down?); repo left unchanged"
        return 0
    fi
    local br; br="$(_sr_default_branch "$dir")"

    if [[ "$discard" != "1" ]]; then
        # Guard 1 — protect unpushed authored commits.
        local ahead
        ahead="$(git -C "$dir" rev-list --count "origin/$br..HEAD" 2>/dev/null || echo 0)"
        if [[ "${ahead:-0}" -gt 0 ]]; then
            _sr_warn "  $name — $ahead local commit(s) not on origin; skipping reset (auto-commit owns these), re-materialising only"
            _sr_materialise "$dir" "$materialiser"
            return 0
        fi
        # Guard 2 — protect authored working-tree edits (Joerg's machine only;
        # the sanitiser is absent on consumer installs, where Guard 1 suffices).
        # Round-trip the tree through the sanitiser, then diff vs HEAD: anything
        # left beyond materialisation is genuine authored content. Diff against
        # HEAD (not origin) so a merely-behind repo still advances.
        if [[ -x "$sanitiser" ]]; then
            "$sanitiser" "$dir" >/dev/null 2>&1 || true
            if ! git -C "$dir" diff --quiet HEAD -- . 2>/dev/null; then
                _sr_warn "  $name — authored edits present; skipping reset (leaving for auto-commit), re-materialising"
                _sr_materialise "$dir" "$materialiser"
                return 0
            fi
            # Tree now == HEAD committed form; the reset below is a clean advance.
        fi
    fi

    # Reset to origin truth. reset --hard does not remove gitignored/untracked
    # files; per the 2026-06-09 gotcha we deliberately do NOT git-clean.
    local before after
    before="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
    if git -C "$dir" reset --hard "origin/$br" --quiet 2>/dev/null; then
        after="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
        if [[ "$before" != "$after" ]]; then
            _sr_ok "  $name — synced to origin/$br ($before → $after)"
        else
            _sr_ok "  $name — already at origin/$br ($after)"
        fi
    else
        _sr_warn "  $name — reset to origin/$br failed; re-materialising in place"
        _sr_materialise "$dir" "$materialiser"
        return 0
    fi
    _sr_materialise "$dir" "$materialiser"
}

# sync_framework_and_reexec <framework_dir> <calling_script> [args...]
# Sync the framework repo, then if it ADVANCED re-exec the calling script so the
# rest of the run uses the new code. Safe against self-modification: this
# function body is fully parsed at source time, so it can rewrite the on-disk
# caller script (bash streams its input) without corrupting the current process.
# Honours TTC_SYNC_DISCARD=1 to pass --discard through. Re-exec runs once
# (guarded by TTC_REEXECED).
sync_framework_and_reexec() {
    local fw="$1" self="${2:-}"; shift 2 2>/dev/null || shift $# 2>/dev/null
    [[ -d "$fw/.git" ]] || return 0
    local pre post
    pre="$(git -C "$fw" rev-parse HEAD 2>/dev/null || echo none)"
    if [[ "${TTC_SYNC_DISCARD:-0}" == "1" ]]; then
        sync_repo_to_origin "$fw" --discard
    else
        sync_repo_to_origin "$fw"
    fi
    post="$(git -C "$fw" rev-parse HEAD 2>/dev/null || echo none)"
    if [[ "$pre" != "$post" && -z "${TTC_REEXECED:-}" && -n "$self" && -f "$self" ]]; then
        export TTC_REEXECED=1
        _sr_ok "  framework advanced ($pre → $post) — re-running $(basename "$self") with the new version"
        exec bash "$self" "$@"
    fi
}
