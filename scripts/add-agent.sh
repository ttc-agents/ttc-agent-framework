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

if [[ -d "$TARGET/.git" ]]; then
    echo "[skip] $REPO already cloned - pulling latest"
    git -C "$TARGET" pull --ff-only
    if [[ "$SUBMODULES" == "true" ]]; then
        git -C "$TARGET" submodule update --init --recursive
    fi
else
    echo "[clone] $GITHUB_ORG/$REPO -> $TARGET"
    if [[ "$SUBMODULES" == "true" ]]; then
        gh repo clone "$GITHUB_ORG/$REPO" "$TARGET" -- --recurse-submodules
    else
        gh repo clone "$GITHUB_ORG/$REPO" "$TARGET"
    fi
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
