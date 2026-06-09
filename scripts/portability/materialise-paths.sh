#!/bin/bash
# SANITISE-SKIP — this file does the substitution; literal patterns must survive
# materialise-paths.sh — replace portable placeholders with this machine's real paths
#
# Reverse direction (fresh clone on user machine → ready-to-run).
#
# Substitutions:
#   /Users/joergpietzsch/AI-Vault        -> ${TTC_AI_VAULT:-$HOME/AI-Vault}
#   /Users/joergpietzsch            -> $HOME
#   {{ONEDRIVE_SHARED}} -> probed per host: either
#                            $HOME/Library/CloudStorage/OneDrive-TTCGlobal              (Joerg, owner)
#                          OR
#                            $HOME/Library/CloudStorage/OneDrive-SharedLibraries-TTCGlobal/Joerg Pietzsch -  (team member)
#                          The placeholder is always written followed by /<FolderName>/...
#                          so the substitution joins cleanly with either form.
#
# Idempotent: if a file has no placeholders, no-op.
#
# Usage:
#   materialise_file <path>
#   materialise_dir <dir>
#   $0 <file-or-dir> [more...]
#
# Environment overrides:
#   TTC_AI_VAULT          — set to override the AI-Vault root (default: $HOME/AI-Vault)
#   TTC_HOME              — set to override the HOME root (default: $HOME)
#   TTC_ONEDRIVE_SHARED   — set to force the OneDrive-shared prefix (skips probe)

set -euo pipefail

: "${TTC_AI_VAULT:=${HOME}/AI-Vault}"
: "${TTC_HOME:=${HOME}}"

# Probe which OneDrive-shared variant exists on this machine.
# "Sales" is used as a tracer because every shared user has it.
# Probe deferrable via TTC_ONEDRIVE_SHARED (e.g. for testing / cross-machine builds).
if [ -n "${TTC_ONEDRIVE_SHARED:-}" ]; then
    _ONEDRIVE_SHARED="$TTC_ONEDRIVE_SHARED"
elif [ -d "$TTC_HOME/Library/CloudStorage/OneDrive-SharedLibraries-TTCGlobal/Joerg Pietzsch - Sales" ]; then
    # Team member: shares appear via SharedLibraries mount with "Joerg Pietzsch - " prefix.
    # Note no trailing slash — the placeholder syntax /Users/joergpietzsch/Library/CloudStorage/OneDrive-TTCGlobal/<F>/... means
    # the substitution string must end such that <F> joins onto it cleanly.
    _ONEDRIVE_SHARED="$TTC_HOME/Library/CloudStorage/OneDrive-SharedLibraries-TTCGlobal/Joerg Pietzsch - "
elif [ -d "$TTC_HOME/Library/CloudStorage/OneDrive-TTCGlobal/Sales" ]; then
    # Owner (Joerg): shares are at his personal OneDrive-TTCGlobal mount.
    _ONEDRIVE_SHARED="$TTC_HOME/Library/CloudStorage/OneDrive-TTCGlobal/"
else
    # Neither probe folder exists — fall back to team form (most common case).
    # User may not yet have accepted the share invite; materialise the path anyway so
    # the file will work once the share is added. The error surfaces at agent-runtime.
    _ONEDRIVE_SHARED="$TTC_HOME/Library/CloudStorage/OneDrive-SharedLibraries-TTCGlobal/Joerg Pietzsch - "
fi

# Escape replacement strings for sed (& \ | newline).
_sed_escape() {
    printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'
}

_AI_VAULT_ESC=$(_sed_escape "$TTC_AI_VAULT")
_HOME_ESC=$(_sed_escape "$TTC_HOME")
_ONEDRIVE_SHARED_ESC=$(_sed_escape "$_ONEDRIVE_SHARED")

# Order: substitute /Users/joergpietzsch/Library/CloudStorage/OneDrive-TTCGlobal/ FIRST (before /Users/joergpietzsch) — the OneDrive prefix
# already includes a fully-resolved $HOME, so no inner placeholder to expand.
_MATERIALISE_SED_SCRIPT="
  s|/Users/joergpietzsch/Library/CloudStorage/OneDrive-TTCGlobal/|${_ONEDRIVE_SHARED_ESC}|g
  s|/Users/joergpietzsch/AI-Vault|${_AI_VAULT_ESC}|g
  s|/Users/joergpietzsch|${_HOME_ESC}|g
"

materialise_file() {
    local f="$1"
    [ -f "$f" ] || { echo "materialise_file: not a file: $f" >&2; return 1; }

    if ! file -b --mime "$f" 2>/dev/null | grep -qE 'text|json|xml|x-empty'; then
        return 0
    fi

    local tmp
    tmp=$(mktemp "${f}.materialise.XXXXXX")
    sed -E "$_MATERIALISE_SED_SCRIPT" "$f" > "$tmp"

    if cmp -s "$f" "$tmp"; then
        rm -f "$tmp"
        return 0
    fi

    chmod --reference="$f" "$tmp" 2>/dev/null || {
        local mode
        mode=$(stat -f '%Mp%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null || echo 644)
        chmod "$mode" "$tmp"
    }
    mv -f "$tmp" "$f"
    echo "materialised: $f"
}

materialise_dir() {
    local d="$1"
    [ -d "$d" ] || { echo "materialise_dir: not a directory: $d" >&2; return 1; }

    find "$d" \
        -type d -name '.git' -prune -o \
        -type d -name '__pycache__' -prune -o \
        -type d -name '.venv' -prune -o \
        -type d -name 'node_modules' -prune -o \
        -type f \( \
            -name '*.md' -o \
            -name '*.py' -o \
            -name '*.sh' -o \
            -name '*.json' -o \
            -name '*.ps1' -o \
            -name '*.yml' -o \
            -name '*.yaml' -o \
            -name '*.toml' -o \
            -name '*.txt' -o \
            -name '*.cfg' -o \
            -name '*.ini' -o \
            -name '*.plist' -o \
            -name '*.xml' -o \
            -name '*.ts' -o \
            -name '*.tsx' -o \
            -name '*.js' -o \
            -name '*.jsx' -o \
            -name '*.mjs' -o \
            -name '*.cjs' \
        \) -print | while read -r f; do
            materialise_file "$f" || echo "FAILED: $f" >&2
        done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <file-or-directory> [more...]" >&2
        echo "  TTC_AI_VAULT (default: \$HOME/AI-Vault) currently: $TTC_AI_VAULT" >&2
        echo "  TTC_HOME     (default: \$HOME)          currently: $TTC_HOME" >&2
        exit 64
    fi
    for arg in "$@"; do
        if [ -d "$arg" ]; then
            materialise_dir "$arg"
        elif [ -f "$arg" ]; then
            materialise_file "$arg"
        else
            echo "skip (not file/dir): $arg" >&2
        fi
    done
fi