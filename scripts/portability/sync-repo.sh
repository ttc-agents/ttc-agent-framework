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
#   2. Authored working-tree edits → detected NON-MUTATINGLY: temp copies of
#      the changed tracked files are sanitised and diffed against HEAD (the live
#      tree is never touched). If anything beyond reproducible materialisation
#      remains, reset is skipped and the edits are left for auto-commit. The
#      sanitiser ships with the framework, so this runs on macOS and Windows.
#
# A per-repo mkdir lock (.git/ttc-sync.lock) mutually excludes a manual run from
# the hourly auto-commit-agents.sh so reset --hard can't fire mid-rebase.
#
# Idempotent. Errors are reported, never swallowed.

# --- logging: delegate to the caller's helpers if present, else fall back ----
_sr_log()   { if command -v log        >/dev/null 2>&1; then log   "$@"; else printf "\033[0;36m[sync]\033[0m %s\n"  "$*"; fi; }
_sr_ok()    { if command -v ok         >/dev/null 2>&1; then ok    "$@"; else printf "\033[0;32m[ok]\033[0m %s\n"    "$*"; fi; }
_sr_warn()  { if command -v warn       >/dev/null 2>&1; then warn  "$@"; else printf "\033[0;33m[warn]\033[0m %s\n"  "$*"; fi; }

_sr_default_branch() {
    local b
    b="$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
    if [[ -z "$b" ]]; then
        # origin/HEAD unset (common after a plain clone) — probe main then master
        # instead of blindly assuming main (B1).
        if   git -C "$1" rev-parse --verify --quiet origin/main   >/dev/null 2>&1; then b=main
        elif git -C "$1" rev-parse --verify --quiet origin/master >/dev/null 2>&1; then b=master
        else b=main; fi
    fi
    echo "$b"
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

# _sr_has_authored_edits <dir> <sanitiser>
# Decide whether the working tree holds genuine authored content (beyond path
# materialisation) — WITHOUT mutating the live tree (H1). Copies every changed
# tracked file into a temp dir, sanitises the COPIES, and diffs each against its
# HEAD blob: if a sanitised copy still differs from HEAD, that's authored
# content. Returns 0 (true) if authored edits exist, 1 (false) if the only
# difference is reproducible materialisation. A deleted/added tracked path also
# counts as authored. Untracked files are out of scope here (see review C2).
_sr_has_authored_edits() {
    local dir="$1" sanitiser="$2"
    local names; names="$(git -C "$dir" diff --name-only HEAD 2>/dev/null)"
    [[ -z "$names" ]] && return 1   # no tracked changes at all
    local tmpd; tmpd="$(mktemp -d)"
    local rc=1 f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if [[ ! -f "$dir/$f" ]]; then rc=0; break; fi   # deleted tracked file = authored
        mkdir -p "$tmpd/$(dirname "$f")"
        cp "$dir/$f" "$tmpd/$f"
    done <<< "$names"
    if [[ $rc -eq 1 ]]; then
        "$sanitiser" "$tmpd" >/dev/null 2>&1 || true     # sanitise the COPIES only
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            [[ -f "$tmpd/$f" ]] || continue
            if ! git -C "$dir" show "HEAD:$f" 2>/dev/null | diff -q - "$tmpd/$f" >/dev/null 2>&1; then
                rc=0; break
            fi
        done <<< "$names"
    fi
    rm -rf "$tmpd"
    return $rc
}

_sr_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# Portable (macOS-safe — no flock) per-repo lock via atomic mkdir. Mutually
# excludes a manual sync from the hourly auto-commit-agents.sh so reset --hard
# can't fire mid-rebase (C1). auto-commit takes the SAME lock path. Steals a
# lock older than 600s (a normal cycle is seconds); gives up after ~30s of
# contention so a stuck peer can't hang the whole run.
_sr_acquire_lock() {
    local lock="$1/.git/ttc-sync.lock" waited=0
    while ! mkdir "$lock" 2>/dev/null; do
        if [[ -d "$lock" && $(( $(date +%s) - $(_sr_mtime "$lock") )) -gt 600 ]]; then
            rm -rf "$lock" 2>/dev/null; continue
        fi
        sleep 1; waited=$((waited+1))
        [[ $waited -ge 30 ]] && return 1
    done
    return 0
}
_sr_release_lock() { rm -rf "$1/.git/ttc-sync.lock" 2>/dev/null || true; }

# sync_repo_to_origin <target_dir> [--discard]
# Returns 0 on success/skip, 2 on bad args, 3 on fetch/reset failure.
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

    # --- locked critical section (C1): mutually exclude with the hourly
    # auto-commit so reset --hard can't fire mid-rebase. A subshell guarantees
    # the lock is released via the EXIT trap on every path. `local` is omitted
    # inside — subshell vars are already isolated. ---
    (
        if ! _sr_acquire_lock "$dir"; then
            _sr_warn "  $name — busy (locked by another sync/auto-commit); skipped this round"
            exit 0
        fi
        trap '_sr_release_lock "$dir"' EXIT

        # Fetch — surface failure, never reset against a stale remote-tracking ref.
        if ! git -C "$dir" fetch --quiet origin 2>/dev/null; then
            _sr_warn "  $name — fetch failed (offline / SSH down?); repo left unchanged"
            exit 3
        fi
        br="$(_sr_default_branch "$dir")"

        if [[ "$discard" != "1" ]]; then
            # Guard 1 — protect unpushed authored commits.
            ahead="$(git -C "$dir" rev-list --count "origin/$br..HEAD" 2>/dev/null || echo 0)"
            if [[ "${ahead:-0}" -gt 0 ]]; then
                _sr_warn "  $name — $ahead local commit(s) not on origin; skipping reset (auto-commit owns these), re-materialising only"
                _sr_materialise "$dir" "$materialiser"
                exit 0
            fi
            # Guard 2 — NON-MUTATING (H1): _sr_has_authored_edits sanitises COPIES
            # in a temp dir and diffs vs HEAD, so the live tree is never altered —
            # an interrupt can no longer leave the repo in broken placeholder form.
            if [[ -x "$sanitiser" ]] && _sr_has_authored_edits "$dir" "$sanitiser"; then
                _sr_warn "  $name — authored edits present; skipping reset (leaving for auto-commit), re-materialising"
                _sr_materialise "$dir" "$materialiser"
                exit 0
            fi
        fi

        # Warn about untracked files the reset would overwrite (review C2-untracked):
        # reset --hard silently clobbers an untracked path that origin now tracks.
        # We don't block (Syncthing legitimately deposits such files) but surface
        # it so an accidental authored untracked file isn't lost in silence.
        while IFS= read -r u; do
            [[ -z "$u" ]] && continue
            git -C "$dir" cat-file -e "origin/$br:$u" 2>/dev/null \
                && _sr_warn "  $name — untracked '$u' will be overwritten by origin's version"
        done < <(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null)

        # Reset to origin truth. reset --hard does not remove gitignored/untracked
        # files; per the 2026-06-09 gotcha we deliberately do NOT git-clean.
        before="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
        if git -C "$dir" reset --hard "origin/$br" --quiet 2>/dev/null; then
            after="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
            if [[ "$before" != "$after" ]]; then
                _sr_ok "  $name — synced to origin/$br ($before → $after)"
            else
                _sr_ok "  $name — already at origin/$br ($after)"
            fi
            # C2 — advance submodules to the superproject's reset pointer; reset
            # --hard moves the gitlink but never updates the submodule tree, so
            # update-all would otherwise leave a submodule-bearing repo (e.g. SAP)
            # drifting. Fresh clones land here too (.gitmodules present post-clone).
            if [[ -f "$dir/.gitmodules" ]]; then
                git -C "$dir" submodule update --init --recursive >/dev/null 2>&1 \
                    || _sr_warn "  $name — submodule update failed"
            fi
        else
            _sr_warn "  $name — reset to origin/$br failed; re-materialising in place"
            _sr_materialise "$dir" "$materialiser"
            exit 3
        fi
        _sr_materialise "$dir" "$materialiser"
        exit 0
    )
    return $?
}

# sync_framework_and_reexec <framework_dir> <calling_script> [args...]
# Sync the framework repo, then if it ADVANCED re-exec the calling script so the
# rest of the run uses the new code. Honours TTC_SYNC_DISCARD=1 to pass
# --discard through. Re-exec runs once (guarded by TTC_REEXECED).
#
# Self-modification safety: syncing the framework rewrites files inside it —
# including the running caller script (install.sh / update-all.sh) and this
# helper. bash does NOT fully buffer a streamed script, so this is safe ONLY
# because every writer replaces files by ATOMIC RENAME (materialise-paths.sh and
# sanitise-paths.sh use mktemp+`mv -f`; git reset/checkout swap via the index):
# the directory entry is repointed while bash keeps reading the ORIGINAL inode
# behind its open fd. INVARIANT — never rewrite a running caller in place
# (no `sed -i`/`>` without a temp file); that would truncate what bash reads and
# silently run a partial tail. (This function body itself is parsed at
# source time, so calling it after such a rewrite is independently safe.)
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
