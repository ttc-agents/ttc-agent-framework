#!/usr/bin/env python3
"""Inventory every BwBm footprint across Agents/ + KB, propose a class for review."""
import argparse, csv, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parents[2]))
from scripts.restructure import _partition_rules as pr

def propose(path, text, names):
    if pr.has_review_marker(text):
        return "review"
    fn = path.name.lower()
    # Heuristic: program-specific artefacts (Beleg, Q02, regression status, delivery) → customer;
    # methodology/skills/framework → capability. Final call is human (this is a proposal only).
    cust_hints = ("beleg", "q01", "q02", "regression", "delivery-volume", "status", "engagement")
    cap_hints  = ("skill", "template", "methodik", "idiom", "framework", "playwright-", "reference_")
    if any(h in fn for h in cap_hints):
        return "capability"
    if any(h in fn for h in cust_hints) or any(h in text.lower() for h in cust_hints):
        return "customer"
    return "review"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--names", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    names = [n for n in a.names.split(",") if n]
    root = pathlib.Path(a.root)
    rows = []
    for base in [root / "Agents", root / "Claude Folder" / "Knowledge Base"]:
        if not base.exists():
            continue
        for f in base.rglob("*"):
            if not f.is_file() or f.suffix.lower() not in {".md", ".json", ".csv", ".txt"}:
                continue
            sp = str(f)
            if any(skip in sp for skip in ("/.git/", "/.venv/", "/node_modules/",
                                            "/__pycache__/", "/_vectordb/", "/.auth/")):
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
            if not (pr.mentions_customer(f.name, names) or pr.mentions_customer(text, names)):
                continue
            parts = f.relative_to(root).parts
            agent = parts[1] if parts[0] == "Agents" and len(parts) > 1 else parts[0]
            rows.append({
                "path": str(f), "agent": agent, "bytes": f.stat().st_size,
                "sensitive": pr.looks_sensitive(text),
                "proposed_class": propose(f, text, names),
                "decided_class": "", "target": "", "reuse_pointer": "",
            })
    with open(a.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else
                           ["path","agent","bytes","sensitive","proposed_class",
                            "decided_class","target","reuse_pointer"])
        w.writeheader(); w.writerows(rows)
    print(f"Inventory: {len(rows)} BwBm files → {a.out}")

if __name__ == "__main__":
    main()
