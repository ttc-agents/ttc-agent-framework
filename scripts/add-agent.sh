#!/bin/bash
# add-agent.sh - install a single TTC agent by name (macOS/Linux)
#
# Usage:  ./add-agent.sh <apply-name>
# Example: ./add-agent.sh hr
#
# Looks up the agent in install-config.json, clones the matching repo
# into the configured Agents dir, runs its install.sh if present, and
# registers the routing line in ~/CLAUDE.md.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <apply-name>" >&2
    exit 1
fi

NAME="$1"
FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$FRAMEWORK_DIR/install-config.json"
INSTALL_ROOT="${TTC_INSTALL_ROOT:-$HOME/AI-Vault}"
AGENTS_DIR="$INSTALL_ROOT/Agents"
CLAUDE_MD="$HOME/CLAUDE.md"

if [[ ! -f "$CONFIG" ]]; then
    echo "[err] install-config.json not found at $CONFIG" >&2
    exit 1
fi

# Look up the agent in the registry. Match by repo name (e.g. ttc-agent-personal-template)
# OR by apply key. If both match with same apply key, prefer the repo-name match.
ENTRY=$(python3 - "$CONFIG" "$NAME" <<'PYEOF'
import json, sys
cfg_path, name = sys.argv[1], sys.argv[2]
with open(cfg_path) as f:
    cfg = json.load(f)
candidates = []
for a in cfg.get("agents", []):
    short = a["repo"].removeprefix("ttc-agent-") if a["repo"].startswith("ttc-agent-") else a["repo"]
    if name == short or name == a["repo"] or name == a["apply"]:
        candidates.append(a)
if not candidates:
    sys.exit(0)
# Prefer the one whose "short repo" exactly matches
for a in candidates:
    short = a["repo"].removeprefix("ttc-agent-") if a["repo"].startswith("ttc-agent-") else a["repo"]
    if name == short:
        print(f'{a["repo"]}\t{a["dir"]}\t{a["apply"]}\t{"true" if a.get("submodules") else "false"}')
        sys.exit(0)
a = candidates[0]
print(f'{a["repo"]}\t{a["dir"]}\t{a["apply"]}\t{"true" if a.get("submodules") else "false"}')
PYEOF
)

if [[ -z "$ENTRY" ]]; then
    echo "[err] Unknown agent '$NAME'. Available names:" >&2
    python3 -c "
import json
with open('$CONFIG') as f: cfg = json.load(f)
for a in cfg.get('agents', []):
    short = a['repo'].replace('ttc-agent-','')
    print(f'  {short:25s}  ({a[\"apply\"]})')
" >&2
    exit 1
fi

IFS=$'\t' read -r REPO DIR APPLY SUBMODULES <<< "$ENTRY"
GITHUB_ORG=$(python3 -c "import json; print(json.load(open('$CONFIG'))['github_org'])")
TARGET="$AGENTS_DIR/$DIR"

mkdir -p "$AGENTS_DIR"

# Source the shared sync helper so updates go through the guarded
# fetch → reset --hard → re-materialise path (and so this agent actually gets
# materialised — add-agent.sh previously skipped materialisation entirely).
export TTC_AI_VAULT="$INSTALL_ROOT" TTC_FRAMEWORK_DIR="$FRAMEWORK_DIR" TTC_HOME="$HOME"
SYNC_HELPER="$FRAMEWORK_DIR/scripts/portability/sync-repo.sh"
[[ -f "$SYNC_HELPER" ]] && source "$SYNC_HELPER"

if [[ ! -d "$TARGET/.git" ]]; then
    echo "[clone] $GITHUB_ORG/$REPO -> $TARGET (SSH)"
    if [[ "$SUBMODULES" == "true" ]]; then
        git clone --recurse-submodules "git@github.com:$GITHUB_ORG/$REPO.git" "$TARGET"
    else
        git clone "git@github.com:$GITHUB_ORG/$REPO.git" "$TARGET"
    fi
else
    echo "[skip] $REPO already cloned - syncing to origin"
fi
# Sync to origin + materialise (replaces the silent-failing `pull --ff-only`).
if command -v sync_repo_to_origin >/dev/null 2>&1; then
    sync_repo_to_origin "$TARGET"
elif [[ -x "$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh" ]]; then
    "$FRAMEWORK_DIR/scripts/portability/materialise-paths.sh" "$TARGET" >/dev/null 2>&1 || true
fi
if [[ "$SUBMODULES" == "true" ]]; then
    git -C "$TARGET" submodule update --init --recursive
fi

if [[ -f "$TARGET/install.sh" ]]; then
    echo "[run]  $TARGET/install.sh"
    (cd "$TARGET" && bash install.sh)
else
    echo "[info] no install.sh in $REPO - clone only"
fi

LINE="| \`apply $APPLY\` | \`$TARGET/system-prompt.md\` |"
if [[ -f "$CLAUDE_MD" ]] && grep -qE "^\| \`apply $APPLY\`" "$CLAUDE_MD"; then
    echo "[skip] apply $APPLY already in $CLAUDE_MD"
else
    echo "$LINE" >> "$CLAUDE_MD"
    echo "[add]  apply $APPLY -> $CLAUDE_MD"
fi

echo ""
echo "Done. Try it in Claude Code:  apply $APPLY"
