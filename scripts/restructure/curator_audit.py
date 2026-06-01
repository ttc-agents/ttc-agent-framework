#!/usr/bin/env python3
"""Curator audit (dry-run): partition leaks, sensitive-in-team, #curator-review markers.

Scans each capability's `memory/` AND `working/` trees. Classification:
  [LEAK]      customer identity is in a dir/file NAME → it is about a customer, sitting in a
              customer-free capability = genuine scatter (escalated). A matched directory is
              reported once and NOT descended into (so a customer working-tree is one finding,
              not hundreds). Catches binaries (.pptx/.xlsx/.docx/.pdf) + aliases (DH/DIB/CBUAE).
  [MENTION]   a reusable, generically-named file merely NAMES a customer in its body
              (e.g. a landscape/estimator listing examples) → informational, not moved.
  [SENSITIVE] a rate/price/salary/value figure in a (team-readable) capability store.
  [REVIEW]    an explicit #curator-review marker.
"""
import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parents[2]))
from scripts.restructure import _partition_rules as pr

TEXT_EXT = {".md", ".txt"}
SCAN_DIRS = ("memory", "working")
PRUNE = {".venv", "node_modules", "__pycache__", ".git", ".auth",
         "_vectordb", ".pytest_cache", ".ipynb_checkpoints"}


def build_customers(args):
    """Return [{"label","keys","aliases"}]. Prefer --registry (gives slug + aliases);
    fall back to a plain --customers name list."""
    if args.registry:
        reg = json.load(open(args.registry))["customers"]
        out = []
        for slug, e in reg.items():
            disp = e.get("display_name", slug)
            # match_keys = extra normalized-substring keys for naming variants
            # (e.g. slug 'dubai-holdings-leapwork' but files written 'dubai-holding').
            out.append({"label": disp,
                        "keys": [slug, disp] + e.get("match_keys", []),
                        "aliases": e.get("aliases", [])})
        return out
    return [{"label": n, "keys": [n], "aliases": []}
            for n in args.customers.split(",") if n]


def load_allow(path):
    """Allowlist of triaged-by-policy scatter (path substrings). One pattern per line;
    text after '#' is the reason (kept for the digest). Matching LEAKs → ACCEPTED."""
    if not path:
        return []
    out = []
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        pat = line.split("#", 1)[0].strip()
        if pat:
            out.append(pat)
    return out


def classify(capdir, customers, names, findings, allow):
    def walk(d):
        for p in sorted(d.iterdir(), key=lambda x: x.name):
            if p.name in PRUNE or p.is_symlink():
                continue
            if p.is_dir():
                label = pr.path_targets_customer(p.name, customers)
                if label:
                    # Roll the whole customer working-tree up to one finding; don't descend.
                    kind = "ACCEPTED" if any(a in str(p) for a in allow) else "LEAK"
                    findings.append((kind, f"customer-specific dir in capability: {p}/  (→ {label})"))
                else:
                    walk(p)
            elif p.is_file():
                is_text = p.suffix.lower() in TEXT_EXT
                txt = ""
                if is_text:
                    txt = p.read_text(encoding="utf-8", errors="ignore")
                    if txt.lstrip().startswith("> MOVED ->"):
                        continue  # forwarding tombstone from a migration, not scatter
                label = pr.path_targets_customer(p.name, customers)
                if label:
                    kind = "ACCEPTED" if any(a in str(p) for a in allow) else "LEAK"
                    findings.append((kind, f"customer-specific file in capability: {p}  (→ {label})"))
                elif is_text and pr.mentions_customer(txt, names):
                    findings.append(("MENTION", f"customer named in reusable file (review, don't auto-move): {p}"))
                if is_text and pr.looks_sensitive(txt):
                    findings.append(("SENSITIVE", f"possible sensitive figure in capability store: {p}"))
                if is_text and pr.has_review_marker(txt):
                    findings.append(("REVIEW", f"#curator-review marker: {p}"))

    for sub in SCAN_DIRS:
        base = capdir / sub
        if base.exists() and base.is_dir():
            walk(base)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--customers", default="")
    ap.add_argument("--registry", default="")
    ap.add_argument("--capabilities", default="")
    ap.add_argument("--allow", default="", help="allowlist file of triaged-by-policy scatter paths")
    ap.add_argument("--dry-run", action="store_true", default=True)
    a = ap.parse_args()

    customers = build_customers(a)
    names = [c["label"] for c in customers]
    caps = [c for c in a.capabilities.split(",") if c]
    allow = load_allow(a.allow)
    root = pathlib.Path(a.root)
    findings = []

    for cap in caps:
        classify(root / "Agents" / cap, customers, names, findings, allow)

    for kind, msg in findings:
        print(f"[{kind}] {msg}")
    counts = {}
    for kind, _ in findings:
        counts[kind] = counts.get(kind, 0) + 1
    summary = ", ".join(f"{k} {counts[k]}" for k in sorted(counts)) or "none"
    print(f"--- {len(findings)} finding(s): {summary} (dry-run; no changes made) ---")


if __name__ == "__main__":
    main()
