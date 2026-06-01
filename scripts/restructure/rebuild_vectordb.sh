#!/usr/bin/env bash
# rebuild_vectordb.sh — safe full rebuild of the kb_search vector store.
#
# WHY a dedicated script: a naive `kb_vectorize.py --force` rebuilds ONLY the general KB (KB_ROOT) and
# DROPS every customer's chunks, because customer content lives in OneDrive AI-INFO/converted (outside
# KB_ROOT). And `kb_refresh_customer.sh "<x>" --force` is a data nuke (deletes the WHOLE collection,
# re-adds one customer). The correct rebuild is: force-rebuild the general KB ONCE, then re-vectorize
# EVERY registered customer (delta, no --force).
#
# Usage:  rebuild_vectordb.sh --confirm
#   (without --confirm it prints the plan and exits — this op deletes + rebuilds ~30k chunks)
#
# After running: the kb_search MCP server caches the collection handle → run `/mcp` reconnect
# knowledge-base (or restart Claude Code) once, before kb_search works again.
set -euo pipefail
VAULT="{{AI_VAULT}}"
KB_PY="$VAULT/.venv-kb/bin/python3"
VECTORIZER="$VAULT/Claude Folder/kb_vectorize.py"
REGISTRY="$VAULT/Claude Folder/Knowledge Base/_customer_registry.json"

mapfile_customers() { "$VAULT/.venv/bin/python3" -c "import json;[print(e['display_name']) for e in json.load(open('$REGISTRY'))['customers'].values() if e.get('status','active')!='archived']"; }

echo "== rebuild_vectordb =="
echo "Step 1: kb_vectorize.py --force   (general KB rebuild, drops + recreates collection)"
echo "Step 2: kb_vectorize.py --customer <name>   for each registered customer:"
mapfile_customers | sed 's/^/   - /'
echo

if [[ "${1:-}" != "--confirm" ]]; then
  echo "DRY-RUN. Re-run with --confirm to execute (this deletes + rebuilds the whole vector store)."
  exit 0
fi

echo "-- Step 1/2: force-rebuild general KB --"
"$KB_PY" "$VECTORIZER" --force

echo
echo "-- Step 2/2: re-vectorize each customer (delta, NEVER --force) --"
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  echo ">> $name"
  "$KB_PY" "$VECTORIZER" --customer "$name"
done < <(mapfile_customers)

echo
echo "== DONE. ⚠ Run '/mcp reconnect knowledge-base' (or restart Claude Code) before using kb_search. =="
