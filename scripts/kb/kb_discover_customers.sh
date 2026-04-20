#!/usr/bin/env bash
# kb_discover_customers.sh — scan OneDrive for AI-INFO folders, upsert local registry.
#
# Usage:
#   kb_discover_customers.sh          # verbose
#   kb_discover_customers.sh --quiet  # only output if something changed
#   kb_discover_customers.sh --json   # machine-readable
#
# Idempotent. Cheap (filesystem scan only). Intended for agent session-start.

set -euo pipefail
VAULT="/Users/joergpietzsch/AI-Vault"
"$VAULT/.venv/bin/python3" "$VAULT/Claude Folder/kb_discover_customers.py" "$@"
