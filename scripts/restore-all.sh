#!/bin/bash
set -euo pipefail

GITHUB_ORG="ttc-agents"
AGENTS_DIR="${1:-$HOME/AI-Vault/Agents}"

REPOS=(
    "ttc-agent-personal:Personal"
    "ttc-agent-tender:Tender"
    "ttc-agent-finance:Finance"
    "ttc-agent-contracts:Contracts"
    "ttc-agent-hr:HR"
    "ttc-agent-test:Test"
    "ttc-agent-taf:TAF"
    "ttc-agent-bwbm:BwBm"
    "ttc-agent-pptx:PPTX"
    "ttc-agent-odoo:Odoo"
    "ttc-agent-infra:Infrastructure"
    "ttc-agent-private:Private"
    "ttc-agent-trading:Trading"
    "ttc-agent-trading-hf:Trading-HF"
    "ttc-agent-trading-ibkr:Trading-IBKR"
    "ttc-agent-control-review:Control-Review"
)

mkdir -p "$AGENTS_DIR"

for entry in "${REPOS[@]}"; do
    REPO="${entry%%:*}"
    DIR="${entry##*:}"
    TARGET="$AGENTS_DIR/$DIR"
    if [ -d "$TARGET/.git" ]; then
        echo "Updating $DIR..."
        git -C "$TARGET" pull --ff-only
    else
        echo "Cloning $REPO into $DIR..."
        gh repo clone "$GITHUB_ORG/$REPO" "$TARGET"
    fi
done

echo "=== All agents restored to $AGENTS_DIR ==="
