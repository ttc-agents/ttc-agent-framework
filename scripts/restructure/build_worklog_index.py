#!/usr/bin/env python3
"""Aggregate all customer worklogs into one chronological cross-customer index."""
import argparse, re, pathlib, datetime

ENTRY = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})\s+—\s+(.*)$")
FIELD = re.compile(r"^-\s+(\w[\w-]*):\s*(.*)$")

def parse_worklog(path):
    # Customer = the folder that OWNS the AI-INFO store (parent of "AI-INFO - DO NOT DELETE"),
    # else the immediate parent (e.g. a Lead's own dir).
    customer = path.parent.parent.name if path.parent.name.startswith("AI-INFO") else path.parent.name
    entries, cur = [], None
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = ENTRY.match(line)
        if m:
            cur = {"customer": customer, "date": m.group(1), "title": m.group(2).strip(),
                   "fields": {}, "source": str(path)}
            entries.append(cur)
        elif cur:
            f = FIELD.match(line)
            if f:
                cur["fields"][f.group(1).lower()] = f.group(2).strip()
    return entries

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--roots", nargs="+", required=True,
                    help="dirs to scan recursively for worklog.md")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    entries = []
    for root in args.roots:
        for wl in pathlib.Path(root).rglob("worklog.md"):
            entries.extend(parse_worklog(wl))
    entries.sort(key=lambda e: e["date"], reverse=True)
    tags = {}
    for e in entries:
        for t in re.findall(r"#[\w-]+", e["fields"].get("tags", "")):
            tags.setdefault(t, []).append(e)
    lines = [f"# Worklog Index (generated {datetime.date.today()})", ""]
    lines.append("## Chronological (newest first)")
    for e in entries:
        cap = e["fields"].get("capability", "")
        lines.append(f"- **{e['date']}** [{e['customer']}] {e['title']} "
                     f"— {cap} — `{e['source']}`")
    lines += ["", "## By tag"]
    for t in sorted(tags):
        items = ", ".join(f"{e['customer']}({e['date']})" for e in tags[t])
        lines.append(f"- {t}: {items}")
    pathlib.Path(args.out).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Indexed {len(entries)} entries from {len(args.roots)} root(s) → {args.out}")

if __name__ == "__main__":
    main()
