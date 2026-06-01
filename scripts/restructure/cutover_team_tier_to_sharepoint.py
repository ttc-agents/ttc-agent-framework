#!/usr/bin/env python3
"""SharePoint cutover helper — swap the personal-OneDrive mount token for the SharePoint
library mount in every Team-tier reference (registry + a fixed set of code/config/prompt files).

Dry-run by default. See docs/superpowers/plans/2026-06-01-sharepoint-team-tier-cutover-checklist.md.

    # dry-run (review):
    python3 cutover_team_tier_to_sharepoint.py --new "OneDrive-SharedLibraries-TTCGlobal/QA-Delivery"
    # apply:
    python3 cutover_team_tier_to_sharepoint.py --new "...mount..." --apply
    # if the Restricted vault stays on personal OneDrive:
    python3 cutover_team_tier_to_sharepoint.py --new "...mount..." --team-only --apply

Assumes LIFT-AND-SHIFT (the Delivery/Sales/Admin substructure is recreated under the new library),
so a base-token swap is sufficient. For a FLATTEN restructure, remap registry paths per-customer instead.
"""
import argparse
import json
import pathlib

VAULT = pathlib.Path("{{AI_VAULT}}")
REGISTRY = VAULT / "Claude Folder/Knowledge Base/_customer_registry.json"
REG_FIELDS = ("ai_info_folder", "worklog", "primary_folder", "restricted_ai_info")

# Team-tier code/config/prompt files that hardcode the mount token (NOT the long-tail of
# brand/HR/TAF/historical scripts — those stay on personal OneDrive; see the checklist).
FILES = [
    "Agents/ttc_dispatcher.py",
    "Claude Folder/convert_to_knowledge_base.py",
    "Claude Folder/kb_bootstrap_customer.sh",
    "Claude Folder/kb_discover_customers.py",
    "Agents/Leads/bwbm/system-prompt.md",
    "Agents/Leads/vkb/system-prompt.md",
    "Agents/Leads/dubai-holding/system-prompt.md",
    "Agents/Leads/cbuae/system-prompt.md",
    "Agents/Leads/qatar-energy/system-prompt.md",
    "Agents/Leads/dib/system-prompt.md",
]


def is_restricted(s):
    return "Admin/Finance_Legal" in s or "AI-INFO-RESTRICTED" in s


def short(p, old, new):
    return p.replace(old, f"[{old}→{new}]")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", default="OneDrive-TTCGlobal", help="current mount token")
    ap.add_argument("--new", required=True, help="new SharePoint library mount token")
    ap.add_argument("--team-only", action="store_true", help="skip Restricted-vault paths (they stay on personal OneDrive)")
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry-run)")
    a = ap.parse_args()
    OLD, NEW = a.old, a.new
    n_chg = n_skip = 0

    # --- Registry ---
    reg = json.loads(REGISTRY.read_text(encoding="utf-8"))
    for slug, e in reg["customers"].items():
        for f in REG_FIELDS:
            v = e.get(f)
            if not v or OLD not in v:
                continue
            if a.team_only and is_restricted(v):
                print(f"  SKIP-restricted [REG] {slug}.{f}")
                n_skip += 1
                continue
            print(f"  [REG] {slug}.{f}: {short(v, OLD, NEW)}")
            if a.apply:
                e[f] = v.replace(OLD, NEW)
            n_chg += 1
    if a.apply:
        REGISTRY.write_text(json.dumps(reg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # --- Files (token swap, line-aware so --team-only can skip Restricted lines) ---
    for rel in FILES:
        path = VAULT / rel
        if not path.exists():
            print(f"  MISSING-FILE {rel}")
            continue
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        changed = 0
        for i, line in enumerate(lines):
            if OLD not in line:
                continue
            if a.team_only and is_restricted(line):
                n_skip += 1
                continue
            lines[i] = line.replace(OLD, NEW)
            changed += 1
        if changed:
            print(f"  [FILE] {rel}: {changed} line(s)")
            n_chg += changed
            if a.apply:
                path.write_text("".join(lines), encoding="utf-8")

    mode = "APPLIED" if a.apply else "DRY-RUN (add --apply)"
    print(f"\n--- {n_chg} change(s), {n_skip} skipped-restricted; {mode} ---")
    if not a.apply:
        print("    After --apply: re-run convert_to_knowledge_base + kb_vectorize --force + --worklogs,")
        print("    reconnect the knowledge-base MCP, force the worklog-index task, then verify (checklist Step 4).")


if __name__ == "__main__":
    main()
