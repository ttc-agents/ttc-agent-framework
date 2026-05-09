#!/bin/bash
# DEPRECATED — for new installations, use ../install.sh which reads
# install-config.json and handles shared_repos + per-agent submodules
# automatically:
#   curl -fsSL https://raw.githubusercontent.com/ttc-agents/ttc-agent-framework/main/install.sh | bash
#
# This script is kept only for legacy callers (older Mac Mini cron jobs etc.)
# It now reads install-config.json directly to stay in sync with the agents
# list, but has no claim on staying feature-parity with install.sh.
set -euo pipefail

FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$FRAMEWORK_DIR/install-config.json"
INSTALL_ROOT="${TTC_INSTALL_ROOT:-$HOME/AI-Vault}"
AGENTS_DIR="${1:-$INSTALL_ROOT/Agents}"

GITHUB_ORG=$(python3 -c "import json; print(json.load(open('$CONFIG'))['github_org'])")

mkdir -p "$AGENTS_DIR"

# Agents (auto_install=true only)
python3 - "$CONFIG" <<'PYEOF' | while IFS=$'\t' read -r REPO DIR; do
    TARGET="$AGENTS_DIR/$DIR"
    if [ -d "$TARGET/.git" ]; then
        echo "Updating $DIR..."
        git -C "$TARGET" pull --ff-only 2>/dev/null || echo "  (pull failed, skipping)"
    else
        echo "Cloning $REPO into $DIR (SSH)..."
        git clone "git@github.com:$GITHUB_ORG/$REPO.git" "$TARGET"
    fi
done
import json, sys
cfg = json.load(open(sys.argv[1]))
seen = set()
for a in cfg.get("agents", []):
    if not a.get("auto_install", True): continue
    if a["dir"] in seen: continue
    seen.add(a["dir"])
    print(f"{a['repo']}\t{a['dir']}")
PYEOF

# Shared repos (Claude-Config, brand, Tools/mcp-proton) — at AI-Vault root
python3 - "$CONFIG" <<'PYEOF' | while IFS=$'\t' read -r REPO RELPATH; do
    TARGET="$INSTALL_ROOT/$RELPATH"
    if [ -d "$TARGET/.git" ]; then
        echo "Updating $RELPATH..."
        git -C "$TARGET" pull --ff-only 2>/dev/null || echo "  (pull failed, skipping)"
    else
        mkdir -p "$(dirname "$TARGET")"
        echo "Cloning $REPO into $RELPATH (SSH)..."
        git clone "git@github.com:$GITHUB_ORG/$REPO.git" "$TARGET"
        if [ "$REPO" = "ttc-mcp-proton-server" ] && [ -f "$TARGET/package.json" ]; then
            (cd "$TARGET" && npm install --silent) || echo "  (npm install failed)"
        fi
    fi
done
import json, sys
cfg = json.load(open(sys.argv[1]))
for s in cfg.get("shared_repos", []):
    if s.get("auto_install", True):
        print(f"{s['repo']}\t{s['path']}")
PYEOF

echo "=== All repos restored to $INSTALL_ROOT ==="
