#!/usr/bin/env bash
# kb_refresh_customer.sh — run converter for one customer
#
# Usage:
#   kb_refresh_customer.sh "<Customer Display Name or slug>" [--force]
#
# Reads the customer's primary_folder from _customer_registry.json,
# runs convert_to_knowledge_base.py --customer <name>, and reports results.

set -euo pipefail

VAULT_ROOT="/Users/joergpietzsch/AI-Vault"
CONVERTER="$VAULT_ROOT/Claude Folder/convert_to_knowledge_base.py"
VECTORIZER="$VAULT_ROOT/Claude Folder/kb_vectorize.py"
VENV_PY="$VAULT_ROOT/.venv/bin/python3"
VENV_KB_PY="$VAULT_ROOT/.venv-kb/bin/python3"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"<Customer Display Name or slug>\" [--force] [--no-vector]" >&2
  exit 2
fi

CUSTOMER="$1"; shift || true
FORCE=""
DO_VECTOR=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)     FORCE="--force"; shift ;;
    --no-vector) DO_VECTOR=0; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

echo "== Refresh customer KB =="
echo "Customer : $CUSTOMER"
echo "Force    : ${FORCE:-no}"
echo "Vectorize: $([[ $DO_VECTOR -eq 1 ]] && echo yes || echo no)"
echo

echo "-- Step 1/2: convert source docs to text --"
"$VENV_PY" "$CONVERTER" --customer "$CUSTOMER" $FORCE

if [[ $DO_VECTOR -eq 1 ]]; then
  echo
  echo "-- Step 2/2: vectorize into chromadb --"
  # Use kb venv (has chromadb + sentence-transformers) if present, else main venv
  if [[ -x "$VENV_KB_PY" ]]; then
    "$VENV_KB_PY" "$VECTORIZER" --customer "$CUSTOMER" $FORCE
  else
    "$VENV_PY" "$VECTORIZER" --customer "$CUSTOMER" $FORCE
  fi
fi
