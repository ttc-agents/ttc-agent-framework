#!/usr/bin/env python3
"""
kb_discover_customers — scan OneDrive for AI-INFO folders and upsert the local registry.

Walks the well-known OneDrive customer roots, finds every
`AI-INFO - DO NOT DELETE` folder, and adds any missing ones to
`_customer_registry.json` without overwriting existing fields.

Cheap (pure filesystem walk, typically < 2 seconds). Safe to run often
— idempotent. Intended to be called at agent session start so colleagues'
newly-published customer KBs show up automatically.

Usage:
    kb_discover_customers.py                 # scan + upsert, print summary
    kb_discover_customers.py --quiet         # only print on changes
    kb_discover_customers.py --json          # machine-readable output
"""

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

# ── Configuration ─────────────────────────────────────────────────────────────

HOME = Path.home()
ONEDRIVE = HOME / "Library/CloudStorage/OneDrive-TTCGlobal"
REGISTRY_FILE = HOME / "AI-Vault/Claude Folder/Knowledge Base/_customer_registry.json"

# Where to look. Each entry = (root, depth, default region)
SCAN_ROOTS = [
    (ONEDRIVE / "Sales/Customer/Middle East", 1, "Middle East"),
    (ONEDRIVE / "Sales/Customer/DACH Region", 2, "DACH Region"),  # /<Country>/<Customer>
    (ONEDRIVE / "Sales/Customer/UK",          1, "UK"),
    (ONEDRIVE / "Delivery/Leapwork",          1, "South Africa"),  # VKB pattern
    (ONEDRIVE / "Delivery",                   2, "Unspecified"),   # catch-all
    (ONEDRIVE / "Admin/Finance_Legal/Customer Contracts", 1, "Unspecified"),
]

AI_INFO_NAME = "AI-INFO - DO NOT DELETE"


def slugify(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s or "unknown"


def load_registry() -> dict:
    if REGISTRY_FILE.exists():
        return json.loads(REGISTRY_FILE.read_text())
    return {
        "schema_version": "1.0",
        "description": "Maps customers to their primary OneDrive folder and AI-INFO KB location. Edited by kb_bootstrap_customer.sh and kb_discover_customers.py.",
        "customers": {},
    }


def save_registry(data: dict):
    data["last_updated"] = datetime.now().date().isoformat()
    data["customers"] = dict(sorted(data["customers"].items()))
    REGISTRY_FILE.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY_FILE.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def scan() -> list:
    """Return list of {primary_folder, ai_info_folder, display_name, region}.
    Dedupes by ai_info_folder path so overlapping scan roots don't double-count."""
    found = []
    seen = set()
    for root, depth, default_region in SCAN_ROOTS:
        if not root.exists():
            continue
        # Walk to `depth` levels below root, then check for AI_INFO_NAME subdir
        def walk(current: Path, remaining: int):
            if remaining == 0:
                ai = current / AI_INFO_NAME
                if ai.is_dir() and str(ai) not in seen:
                    seen.add(str(ai))
                    found.append({
                        "primary_folder": str(current),
                        "ai_info_folder": str(ai),
                        "display_name": current.name,
                        "region": infer_region(current, default_region),
                    })
                return
            try:
                for child in current.iterdir():
                    if child.is_dir() and not child.name.startswith("."):
                        walk(child, remaining - 1)
            except (PermissionError, OSError):
                pass
        walk(root, depth)
    return found


def infer_region(path: Path, default: str) -> str:
    s = str(path)
    if "/Sales/Customer/Middle East/" in s:         return "Middle East"
    if "/Sales/Customer/DACH Region/" in s:         return "DACH Region"
    if "/Sales/Customer/UK/" in s:                  return "UK"
    if "/Delivery/Leapwork/" in s:                  return "South Africa"
    return default


def upsert(registry: dict, discoveries: list) -> tuple[list, list]:
    """Return (added_slugs, updated_slugs). Preserves existing fields; only fills gaps."""
    added = []
    updated = []
    customers = registry.setdefault("customers", {})
    today = datetime.now().date().isoformat()

    # Build reverse-lookup by ai_info_folder to dedupe
    by_ai_info = {c.get("ai_info_folder"): slug for slug, c in customers.items()}

    for d in discoveries:
        existing_slug = by_ai_info.get(d["ai_info_folder"])
        slug = existing_slug or slugify(d["display_name"])

        existing = customers.get(slug, {})
        new_entry = {
            "display_name":   existing.get("display_name") or d["display_name"],
            "region":         existing.get("region") or d["region"],
            "primary_folder": existing.get("primary_folder") or d["primary_folder"],
            "ai_info_folder": existing.get("ai_info_folder") or d["ai_info_folder"],
            "created":        existing.get("created") or today,
            "active_agents":  existing.get("active_agents") or [],
            "status":         existing.get("status") or "active",
        }
        if existing.get("notes"):
            new_entry["notes"] = existing["notes"]

        if not existing:
            added.append(slug)
        elif any(existing.get(k) != new_entry[k] for k in ("primary_folder", "ai_info_folder")):
            updated.append(slug)

        customers[slug] = new_entry
    return added, updated


def main():
    parser = argparse.ArgumentParser(description="Discover customer AI-INFO folders in OneDrive and upsert the registry.")
    parser.add_argument("--quiet", action="store_true", help="Only print if something changed.")
    parser.add_argument("--json",  action="store_true", help="Print JSON summary.")
    args = parser.parse_args()

    registry = load_registry()
    discoveries = scan()
    added, updated = upsert(registry, discoveries)

    if added or updated:
        save_registry(registry)

    summary = {
        "scanned": len(discoveries),
        "registry_total": len(registry.get("customers", {})),
        "added": added,
        "updated": updated,
    }

    if args.json:
        print(json.dumps(summary, indent=2))
    elif args.quiet and not (added or updated):
        return
    else:
        print(f"[discover] scanned={summary['scanned']}  registry_total={summary['registry_total']}  added={len(added)}  updated={len(updated)}")
        for slug in added:
            entry = registry["customers"][slug]
            print(f"  [+] {slug:30s} {entry['display_name']}  ({entry['region']})")
        for slug in updated:
            entry = registry["customers"][slug]
            print(f"  [~] {slug:30s} {entry['display_name']}  (paths updated)")


if __name__ == "__main__":
    main()
