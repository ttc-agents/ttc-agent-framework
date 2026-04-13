#!/usr/bin/env python3
"""
sync_personal_knowledge.py
Keeps the Head Agent's knowledge file in sync with all other agents.

Auto-discovers agents by scanning Agents/*/memory/ directories.

What it does:
  1. Scans all agent CLAUDE.md files and memory/ folders for changes
  2. Reports what has changed since the last sync
  3. Regenerates a raw concatenation of all agent files as 'all-agents-raw.md'

Usage:
  python3 sync_personal_knowledge.py

  # Check for changes only (no file writes):
  python3 sync_personal_knowledge.py --check

  # Also write all-agents-raw.md (full source dump):
  python3 sync_personal_knowledge.py --dump

  # Override paths:
  python3 sync_personal_knowledge.py --agents-dir /path/to/Agents --head-agent Personal
"""

import os
import sys
import json
import argparse
from datetime import datetime
from pathlib import Path

# ── Defaults (override via CLI args) ─────────────────────────────────────────

DEFAULT_AGENTS_DIR = Path(__file__).resolve().parent.parent / "Agents"
DEFAULT_HEAD_AGENT = "Personal"


# ── Auto-discovery ────────────────────────────────────────────────────────────

def discover_agents(agents_dir: Path, head_agent: str) -> list[str]:
    """Auto-discover agents by scanning for directories with memory/ subfolders."""
    agents = []
    if not agents_dir.exists():
        return agents
    for d in sorted(agents_dir.iterdir()):
        if not d.is_dir():
            continue
        if d.name == head_agent:
            continue  # skip the head agent itself
        if d.name.startswith("."):
            continue
        # Must have at least memory/ or CLAUDE.md or system-prompt.md
        has_memory = (d / "memory").is_dir()
        has_claude = (d / "CLAUDE.md").is_file()
        has_prompt = (d / "system-prompt.md").is_file()
        if has_memory or has_claude or has_prompt:
            agents.append(d.name)
    return agents


# ── Helpers ────────────────────────────────────────────────────────────────────

def get_agent_files(agents_dir: Path, agent: str) -> list[Path]:
    """Return all tracked files for a given agent."""
    agent_dir = agents_dir / agent
    files = []

    # CLAUDE.md
    claude_md = agent_dir / "CLAUDE.md"
    if claude_md.exists():
        files.append(claude_md)

    # system-prompt.md
    sysprompt = agent_dir / "system-prompt.md"
    if sysprompt.exists():
        files.append(sysprompt)

    # All files in memory/
    mem_dir = agent_dir / "memory"
    if mem_dir.exists():
        for f in sorted(mem_dir.iterdir()):
            if f.is_file() and not f.name.startswith("."):
                files.append(f)

    return files


def get_mtime(path: Path) -> float:
    """Return modification time as float, or 0 if file doesn't exist."""
    try:
        return path.stat().st_mtime
    except FileNotFoundError:
        return 0.0


def load_state(state_file: Path) -> dict:
    """Load the last-sync state (file path -> mtime)."""
    if state_file.exists():
        with open(state_file) as f:
            return json.load(f)
    return {}


def save_state(state: dict, state_file: Path):
    """Save the current file mtimes as the new sync state."""
    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)


def build_current_state(agents_dir: Path, agents: list[str]) -> dict:
    """Build a dict of {str(path): mtime} for all tracked files."""
    state = {}
    for agent in agents:
        for f in get_agent_files(agents_dir, agent):
            state[str(f)] = get_mtime(f)
    return state


def detect_changes(old_state: dict, new_state: dict) -> dict:
    """Return changed, added, and removed files."""
    changed = []
    added = []
    removed = []

    for path, mtime in new_state.items():
        if path not in old_state:
            added.append(path)
        elif mtime > old_state[path] + 1:  # +1s tolerance
            changed.append(path)

    for path in old_state:
        if path not in new_state:
            removed.append(path)

    return {"changed": changed, "added": added, "removed": removed}


def generate_raw_dump(agents_dir: Path, agents: list[str]) -> str:
    """Concatenate all agent CLAUDE.md and memory files into a single string."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    sections = [
        f"# All-Agents Source Dump\n\nGenerated: {now}\n"
        f"This is a raw concatenation of all agent CLAUDE.md and memory files.\n"
        f"Use this to understand what changed, then update the head agent's knowledge file.\n\n"
        f"---\n"
    ]

    for agent in agents:
        agent_files = get_agent_files(agents_dir, agent)
        if not agent_files:
            continue
        sections.append(f"\n\n# === AGENT: {agent} ===\n")
        for f in agent_files:
            rel = f.relative_to(agents_dir)
            sections.append(f"\n## [{rel}]\n\n")
            try:
                sections.append(f.read_text(encoding="utf-8"))
            except Exception as e:
                sections.append(f"[Error reading file: {e}]\n")

    return "\n".join(sections)


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Sync Head Agent knowledge from all other agents")
    parser.add_argument("--check", action="store_true",
                        help="Check for changes only -- no file writes")
    parser.add_argument("--dump", action="store_true",
                        help="Write all-agents-raw.md (full source dump)")
    parser.add_argument("--agents-dir", type=Path, default=DEFAULT_AGENTS_DIR,
                        help=f"Path to Agents directory (default: {DEFAULT_AGENTS_DIR})")
    parser.add_argument("--head-agent", type=str, default=DEFAULT_HEAD_AGENT,
                        help=f"Name of the head agent to exclude from scanning (default: {DEFAULT_HEAD_AGENT})")
    args = parser.parse_args()

    agents_dir = args.agents_dir.resolve()
    head_agent = args.head_agent
    head_mem = agents_dir / head_agent / "memory"
    state_file = head_mem / ".sync_state.json"
    raw_dump = head_mem / "all-agents-raw.md"
    knowledge = head_mem / "all-agents-knowledge.md"

    # Auto-discover agents
    agents = discover_agents(agents_dir, head_agent)
    if not agents:
        print(f"No agents found in {agents_dir}")
        sys.exit(1)

    print(f"Scanning {len(agents)} agents: {', '.join(agents)}\n")

    old_state = load_state(state_file)
    new_state = build_current_state(agents_dir, agents)
    diff = detect_changes(old_state, new_state)

    changed = diff["changed"]
    added = diff["added"]
    removed = diff["removed"]

    # -- Report
    if not changed and not added and not removed:
        print("All agent files are in sync -- no changes detected.")
        print(f"   Knowledge file: {knowledge}")

        if args.dump:
            print("\nWriting raw dump (--dump requested)...")
            raw_dump.write_text(generate_raw_dump(agents_dir, agents), encoding="utf-8")
            print(f"   Written: {raw_dump}")
        return

    print("Changes detected since last sync:\n")

    if added:
        print("  NEW files:")
        for p in added:
            rel = Path(p).relative_to(agents_dir) if Path(p).is_relative_to(agents_dir) else Path(p).name
            print(f"    + {rel}")

    if changed:
        print("  MODIFIED files:")
        for p in changed:
            rel = Path(p).relative_to(agents_dir) if Path(p).is_relative_to(agents_dir) else Path(p).name
            mtime = datetime.fromtimestamp(new_state[p]).strftime("%Y-%m-%d %H:%M")
            print(f"    ~ {rel}  (modified {mtime})")

    if removed:
        print("  REMOVED files:")
        for p in removed:
            rel = Path(p).relative_to(agents_dir) if Path(p).is_relative_to(agents_dir) else Path(p).name
            print(f"    - {rel}")

    print(f"\nAction needed:")
    print(f"   The head agent's knowledge file may be out of date.")
    print(f"   File to update: {knowledge}")
    print()
    print(f"   Options:")
    print(f"   1. Ask the head agent to review the changes and update the knowledge file")
    print(f"   2. Run with --dump to generate a full source dump, then review manually")

    # -- Write raw dump if requested
    if args.dump:
        print("\nWriting raw dump...")
        raw_dump.write_text(generate_raw_dump(agents_dir, agents), encoding="utf-8")
        print(f"   Written: {raw_dump}")

    # -- Update state (unless --check)
    if not args.check:
        save_state(new_state, state_file)
        print(f"\nSync state updated -- next run will compare from now.")
    else:
        print(f"\n   (--check mode: state not updated)")


if __name__ == "__main__":
    main()
