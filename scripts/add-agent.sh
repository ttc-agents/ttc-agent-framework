#!/bin/bash
# add-agent.sh — install a single TTC agent by name (macOS/Linux)
#
# Usage:  ./add-agent.sh <agent-name>
# Example: ./add-agent.sh hr
#
# Clones ttc-agents/ttc-agent-<name> into ~/AI-Vault/Agents/<Dir>, runs its
# install.sh if present, and appends the routing line to ~/CLAUDE.md.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <agent-name>" >&2
    exit 1
fi

NAME="$1"
GITHUB_ORG="ttc-agents"
INSTALL_ROOT="${TTC_INSTALL_ROOT:-$HOME/AI-Vault}"
AGENTS_DIR="$INSTALL_ROOT/Agents"
CLAUDE_MD="$HOME/CLAUDE.md"

# Map lowercase apply-name → (repo, agent dir name). Extend as new agents ship.
declare -A DIR_MAP=(
    [sap]="SAP" [test]="Test" [taf]="TAF" [tender]="Tender"
    [hr]="HR" [bwbm]="BwBm" [pptx]="PPTX" [odoo]="Odoo"
    [contracts]="Contracts" [finance]="Finance" [personal]="Personal"
    [private]="Private" [infra]="Infrastructure" [tom]="QA_TOM_Generator"
)

DIR="${DIR_MAP[$NAME]:-}"
if [[ -z "$DIR" ]]; then
    echo "[err] Unknown agent '$NAME'. Known: ${!DIR_MAP[*]}" >&2
    echo "      Trading agents are personal-only and not installable via this script." >&2
    exit 1
fi

REPO="ttc-agent-$NAME"
TARGET="$AGENTS_DIR/$DIR"

mkdir -p "$AGENTS_DIR"

if [[ -d "$TARGET/.git" ]]; then
    echo "[skip] $REPO already cloned — pulling latest"
    git -C "$TARGET" pull --ff-only
else
    echo "[clone] $GITHUB_ORG/$REPO → $TARGET"
    gh repo clone "$GITHUB_ORG/$REPO" "$TARGET" -- --recurse-submodules 2>/dev/null \
        || gh repo clone "$GITHUB_ORG/$REPO" "$TARGET"
fi

if [[ -f "$TARGET/install.sh" ]]; then
    echo "[run]  $TARGET/install.sh"
    (cd "$TARGET" && bash install.sh)
else
    echo "[info] no install.sh in $REPO — clone only"
fi

# Register in CLAUDE.md
LINE="| \`apply $NAME\` | \`$TARGET/system-prompt.md\` |"
if [[ -f "$CLAUDE_MD" ]] && grep -qE "^\| \`apply $NAME\`" "$CLAUDE_MD"; then
    echo "[skip] apply $NAME already in $CLAUDE_MD"
else
    echo "$LINE" >> "$CLAUDE_MD"
    echo "[add]  apply $NAME → $CLAUDE_MD"
fi

echo ""
echo "Done. Try it in Claude Code:  apply $NAME"
