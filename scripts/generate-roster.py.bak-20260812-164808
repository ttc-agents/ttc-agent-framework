#!/usr/bin/env python3
"""
generate-roster.py  —  Single source of truth for the TTC agent roster.

Reads install-config.json (+ optional local-agents.json overlay) and generates:
  a) the agent table in root CLAUDE.md  (--check or --write)
  b) the tracked-agent list for sync_personal_knowledge.py  (--show-sync-list)

The CLAUDE.md table is protected by BEGIN/END marker comments that this script
inserts on first run and uses on subsequent runs to locate the block.

TODO (stretch goals, not yet implemented):
  - AgentLauncher.swift auto-update: regenerate the menu items in
    AI-Vault/Tools/AgentLauncher/AgentLauncher.swift from the roster.
  - Warp YAML auto-generation: emit ~/.warp/launch_configurations/TTC-Agent-*.yaml
    for each agent. Both require re-compiling / re-deploying after change —
    flag in agent-framework.md memory file as a future improvement.

Usage:
  # Check CLAUDE.md table against install-config (print diff, no write):
  python3 generate-roster.py --check

  # Write the generated table into CLAUDE.md in-place:
  python3 generate-roster.py --write

  # Show which agents sync_personal_knowledge.py should track:
  python3 generate-roster.py --show-sync-list

  # Custom paths (for testing):
  python3 generate-roster.py --check \\
      --config /path/to/install-config.json \\
      --claude-md /path/to/CLAUDE.md \\
      --local-overlay /path/to/local-agents.json

Config schema (install-config.json):
  agents[]:
    repo        str | null  — GitHub repo name (null = local-only, not distributed)
    dir         str         — path under Agents/ (e.g. "Leads/bwbm")
    apply       str         — the `apply <slug>` command
    auto_install bool       — whether team installers include it
    note        str?        — human note (ignored by generator)

  _excluded_agents_note{}:
    Free-form dict of agent-name → reason strings.  Listed in --show-sync-list
    output as "deliberately excluded" so gaps are documented, not silent.

Local overlay schema (local-agents.json, optional, lives next to install-config.json):
  Same structure as install-config.json "agents[]" but for entries that are:
    - local-only with no GitHub repo AND
    - should NOT be published into the shared install-config
  Example entries: AppDev (PRIVATE/non-TTC).
  The generator merges local-agents into the full roster for CLAUDE.md generation
  but marks them clearly.  If the file doesn't exist it is silently skipped.

Model mapping:
  Driven by a small lookup table at the bottom of this script.
  If an agent's apply-slug isn't in the table, "Sonnet 4.6" is used as default.
  Update MODEL_MAP when a new agent is added or a model is changed.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths (defaults; overridable via CLI args)
# ---------------------------------------------------------------------------
_HERE = Path(__file__).resolve().parent            # .../ttc-agent-framework/scripts/
_FRAMEWORK_DIR = _HERE.parent                      # .../ttc-agent-framework/
_AI_VAULT = _FRAMEWORK_DIR.parent                  # .../AI-Vault/

DEFAULT_CONFIG    = _FRAMEWORK_DIR / "install-config.json"
DEFAULT_OVERLAY   = _FRAMEWORK_DIR / "local-agents.json"
DEFAULT_CLAUDE_MD = _AI_VAULT / "Claude-Config" / "CLAUDE.md"
AGENTS_BASE_DIR   = _AI_VAULT / "Agents"

# Marker comments inserted around the table block in CLAUDE.md
TABLE_BEGIN = "<!-- ROSTER:BEGIN -->"
TABLE_END   = "<!-- ROSTER:END -->"

# ---------------------------------------------------------------------------
# Model lookup  (apply-slug → model string)
# Agents not listed here fall back to "Sonnet 4.6".
# ---------------------------------------------------------------------------
MODEL_MAP: dict[str, str] = {
    # Opus 4.6
    "tender":         "Opus 4.6",
    "finance":        "Opus 4.6",
    "contracts":      "Opus 4.6",
    "bwbm":           "Opus 4.6",
    "sales-admin":    "Opus 4.6",
    "control-review": "Opus 4.6",
    "sap":            "Opus 4.6",
    "tom":            "Opus 4.6",
    "vkb":            "Opus 4.6",
    "dubai-holding":  "Opus 4.6",
    "cbuae":          "Opus 4.6",
    "qatar-energy":   "Opus 4.6",
    "dib":            "Opus 4.6",
    "customer":       "Opus 4.6",
    # Haiku 4.5
    "trading":        "Haiku 4.5",
    "trading-hf":     "Haiku 4.5",
    # Sonnet 4.6 (explicit — same as default, but documented)
    "personal":       "Sonnet 4.6",
    "hr":             "Sonnet 4.6",
    "test":           "Sonnet 4.6",
    "private":        "Sonnet 4.6",
    "sales":          "Sonnet 4.6",
    "odoo":           "Sonnet 4.6",
    "infra":          "Sonnet 4.6",
    "opendesk":       "Sonnet 4.6",
    "taf":            "Sonnet 4.6",
    "autolead":       "Sonnet 4.6",
    "appdev":         "Sonnet 4.6",
    "trading-ibkr":   "Sonnet 4.6",
    "docs":           "Sonnet 4.6",
    "curator":        "Sonnet 4.6",
}

# ---------------------------------------------------------------------------
# Preferred display order for the table (agents listed here come first, in
# this order; remaining agents are appended alphabetically after them).
# Mirrors the current hand-maintained order in CLAUDE.md so --write doesn't
# reorder unnecessarily.
# ---------------------------------------------------------------------------
DISPLAY_ORDER: list[str] = [
    "tender", "finance", "contracts", "personal", "hr",
    "bwbm", "test", "private", "sales-admin", "sales",
    "odoo", "infra", "opendesk", "taf", "autolead", "appdev",
    "trading", "trading-hf", "trading-ibkr", "control-review",
    "sap", "docs", "tom", "customer",
    "vkb", "dubai-holding", "cbuae", "qatar-energy", "dib",
    "curator",
]

# Agents that sync_personal_knowledge.py should watch
# (capabilities + governance; NOT: Personal=head, Leads=not tracked there, Trading=private)
SYNC_TRACKED_CATEGORIES = {
    "capability": {
        "HR", "BwBm", "Tender", "Finance", "Contracts", "Private",
        "Infrastructure", "Odoo", "SAP", "Test", "TAF", "Docs",
        "QA_TOM_Generator", "Sales", "Sales-Admin", "OpenDesk",
        "Control-Review", "AutoLead", "Curator",
    },
    "skip_leads": True,   # Leads/<slug>/ are customer context — not syndicated to Personal
    "skip_trading": True, # Trading agents are private
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_config(path: Path) -> dict:
    with open(path) as f:
        return json.load(f)


def build_roster(config: dict, overlay_path: Path | None) -> list[dict]:
    """
    Returns a flat list of agent dicts with keys:
      apply, dir, system_prompt_path, model, repo, auto_install, local_only, note

    Dedup rule: if two entries share the same apply-slug, the one whose dir
    contains an actual system-prompt.md wins; otherwise the last entry wins.
    This handles the BwBm migration case where both ttc-agent-bwbm (archived,
    dir=BwBm, no system-prompt.md) and ttc-agent-lead-bwbm (dir=Leads/bwbm,
    has system-prompt.md) share apply='bwbm'.
    """
    agents = list(config.get("agents", []))

    # Merge local overlay if it exists
    if overlay_path and overlay_path.exists():
        try:
            local = load_config(overlay_path)
            agents.extend(local.get("agents", []))
        except Exception as e:
            print(f"[warn] Could not load local overlay {overlay_path}: {e}", file=sys.stderr)

    rows: list[dict] = []
    seen_slugs: dict[str, int] = {}   # slug → index in rows

    for a in agents:
        apply_slug = a.get("apply", "")
        dir_rel    = a.get("dir", "")
        repo       = a.get("repo")  # None = local-only

        # Skip entries with no dir
        if not dir_rel:
            continue

        # Derive system-prompt path
        sp_path_obj = AGENTS_BASE_DIR / dir_rel / "system-prompt.md"
        sp_path     = str(sp_path_obj)
        has_prompt  = sp_path_obj.exists()

        # Special case: _generic lead uses "customer <slug>" in the command
        if dir_rel == "Leads/_generic":
            apply_cmd = "apply customer <slug>"
        else:
            apply_cmd = f"apply {apply_slug}"

        row = {
            "apply_cmd":    apply_cmd,
            "apply_slug":   apply_slug,
            "dir":          dir_rel,
            "system_prompt_path": sp_path,
            "model":        MODEL_MAP.get(apply_slug, "Sonnet 4.6"),
            "repo":         repo,
            "auto_install": a.get("auto_install", True),
            "local_only":   repo is None,
            "has_prompt":   has_prompt,
            "note":         a.get("note", ""),
        }

        if apply_slug in seen_slugs:
            existing_idx = seen_slugs[apply_slug]
            existing = rows[existing_idx]
            # Prefer the entry that actually has a system-prompt on disk
            if has_prompt and not existing["has_prompt"]:
                rows[existing_idx] = row
            # else keep existing (already has prompt or neither does)
        else:
            seen_slugs[apply_slug] = len(rows)
            rows.append(row)

    return rows


def sort_roster(rows: list[dict]) -> list[dict]:
    """Sort rows using DISPLAY_ORDER, then alphabetically for unknowns."""
    order_map = {slug: i for i, slug in enumerate(DISPLAY_ORDER)}
    def key(r: dict) -> tuple:
        slug = r["apply_slug"]
        idx  = order_map.get(slug, len(DISPLAY_ORDER))
        return (idx, slug)
    return sorted(rows, key=key)


def generate_table(rows: list[dict]) -> str:
    """Return the Markdown table block (without surrounding markers)."""
    lines = [
        "| Command | System Prompt File | Model |",
        "|---|---|---|",
    ]
    for r in rows:
        lines.append(
            f"| `{r['apply_cmd']}` | `{r['system_prompt_path']}` | {r['model']} |"
        )
    # Footnote added per architecture-fix 2026-06-09
    lines.append("")
    lines.append(
        "> Table is documentation/fallback — "
        "slash-command skills in `Claude-Config/commands/` are the primary activation (created 2026-06-09)."
    )
    return "\n".join(lines)


def read_claude_md(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def extract_existing_table(content: str) -> str | None:
    """Extract the table between ROSTER markers, or the first markdown table found."""
    # Try markers first
    m = re.search(
        re.escape(TABLE_BEGIN) + r"\n(.*?)\n" + re.escape(TABLE_END),
        content, re.DOTALL
    )
    if m:
        return m.group(1).strip()

    # Fallback: find the first | Command | ... table
    m2 = re.search(
        r"(\| Command \| System Prompt File \| Model \|.*?)(?=\n## |\Z)",
        content, re.DOTALL
    )
    if m2:
        return m2.group(1).strip()

    return None


def inject_table(content: str, new_table: str) -> str:
    """
    Replace the existing table block with the new one (including markers).
    If markers don't exist yet, replace the bare table.
    Returns the updated content.
    """
    marked_block = f"{TABLE_BEGIN}\n{new_table}\n{TABLE_END}\n"

    # Case 1: markers already in place
    if TABLE_BEGIN in content:
        return re.sub(
            re.escape(TABLE_BEGIN) + r".*?" + re.escape(TABLE_END),
            marked_block,
            content, count=1, flags=re.DOTALL
        )

    # Case 2: bare table — find the | Command | header and replace the block
    m = re.search(
        r"(\| Command \| System Prompt File \| Model \|.*?)(?=\n## |\Z)",
        content, re.DOTALL
    )
    if m:
        return content[:m.start()] + marked_block + content[m.end():]

    raise ValueError("Could not locate the agent table in CLAUDE.md")


def diff_tables(old: str, new: str) -> list[str]:
    """Return human-readable diff lines."""
    old_lines = set(old.splitlines())
    new_lines = set(new.splitlines())
    removed = sorted(old_lines - new_lines)
    added   = sorted(new_lines - old_lines)
    result = []
    for l in removed:
        if l.strip():
            result.append(f"  - {l}")
    for l in added:
        if l.strip():
            result.append(f"  + {l}")
    return result


def build_sync_list(rows: list[dict]) -> list[str]:
    """
    Return the list of agent directory names (relative to Agents/)
    that sync_personal_knowledge.py should track.
    Mirrors the _SYNC_SKIP_DIRS logic in sync_personal_knowledge.py.
    """
    skip_top_dirs = {
        "Personal",      # head agent — not a knowledge source for itself
        "BwBm",          # archived (MOVED.md only)
        "Trading", "Trading-HF", "Trading-IBKR",  # private
        "Control-Review",                           # private
        "AppDev",        # PRIVATE/non-TTC
    }

    tracked = []
    for r in rows:
        d = r["dir"]
        if not d:
            continue
        # Skip Lead entries
        if d.startswith("Leads/"):
            continue
        top_dir = d.split("/")[0]
        if top_dir in skip_top_dirs:
            continue
        if top_dir not in tracked:
            tracked.append(top_dir)
    return tracked


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate + check the TTC agent roster from install-config.json"
    )
    parser.add_argument("--check", action="store_true",
                        help="Diff generated table vs current CLAUDE.md (no write)")
    parser.add_argument("--write", action="store_true",
                        help="Write generated table into CLAUDE.md in-place")
    parser.add_argument("--show-sync-list", action="store_true",
                        help="Print the agent list for sync_personal_knowledge.py")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG,
                        help=f"Path to install-config.json (default: {DEFAULT_CONFIG})")
    parser.add_argument("--local-overlay", type=Path, default=DEFAULT_OVERLAY,
                        help=f"Path to local-agents.json overlay (default: {DEFAULT_OVERLAY})")
    parser.add_argument("--claude-md", type=Path, default=DEFAULT_CLAUDE_MD,
                        help=f"Path to root CLAUDE.md (default: {DEFAULT_CLAUDE_MD})")
    args = parser.parse_args()

    if not args.check and not args.write and not args.show_sync_list:
        parser.print_help()
        return 0

    # Load
    try:
        config = load_config(args.config)
    except Exception as e:
        print(f"[error] Cannot load config: {e}", file=sys.stderr)
        return 1

    rows = build_roster(config, args.local_overlay)
    rows = sort_roster(rows)
    new_table = generate_table(rows)

    # --show-sync-list
    if args.show_sync_list:
        sync_list = build_sync_list(rows)
        print("# Agents tracked by sync_personal_knowledge.py")
        print(f"# (generated from {args.config.name})")
        print(f"AGENTS = {json.dumps(sync_list, indent=4)}")
        return 0

    # --check / --write
    if not args.claude_md.exists():
        print(f"[error] CLAUDE.md not found at {args.claude_md}", file=sys.stderr)
        return 1

    content = read_claude_md(args.claude_md)
    existing_table = extract_existing_table(content)

    if existing_table is None:
        print("[error] Could not find the agent table in CLAUDE.md", file=sys.stderr)
        return 1

    diff = diff_tables(existing_table, new_table)

    if args.check:
        if not diff:
            print("[ok] CLAUDE.md agent table is in sync with install-config.json")
        else:
            print(f"[drift] {len(diff)} line(s) differ between install-config and CLAUDE.md:")
            for l in diff:
                print(l)
            return 1  # non-zero exit for CI / update-all.sh warn-only
        return 0

    if args.write:
        if not diff:
            print("[ok] No changes needed — CLAUDE.md is already up to date")
        else:
            new_content = inject_table(content, new_table)
            args.claude_md.write_text(new_content, encoding="utf-8")
            print(f"[written] {args.claude_md}")
            print(f"  {len(diff)} line(s) updated:")
            for l in diff:
                print(f"  {l}")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
