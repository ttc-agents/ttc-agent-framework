#!/usr/bin/env python3
"""
Syncthing Conflict Monitor
Scans AI-Vault for new .sync-conflict files and sends a single summary
email via Microsoft Outlook (AppleScript) when conflicts are detected.
"""

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

WATCH_DIR = Path.home() / "AI-Vault"
STATE_FILE = Path.home() / ".syncthing-conflict-state.json"
RECIPIENT = os.environ.get("CONFLICT_EMAIL", "you@example.com")


def find_conflict_files():
    """Find all .sync-conflict files in AI-Vault."""
    conflicts = []
    for path in WATCH_DIR.rglob("*.sync-conflict-*"):
        conflicts.append(str(path))
    return sorted(conflicts)


def load_reported():
    """Load set of previously reported conflict file paths."""
    if STATE_FILE.exists():
        try:
            data = json.loads(STATE_FILE.read_text())
            return set(data.get("reported", []))
        except (json.JSONDecodeError, KeyError):
            return set()
    return set()


def save_reported(reported):
    """Save the set of reported conflict file paths."""
    # Prune entries for files that no longer exist
    existing = {f for f in reported if os.path.exists(f)}
    STATE_FILE.write_text(json.dumps({"reported": sorted(existing)}, indent=2))


def send_email_via_outlook(subject, body_html):
    """Send email using Microsoft Outlook via AppleScript."""
    # Write AppleScript to temp file to avoid quoting issues
    import tempfile
    script = (
        'tell application "Microsoft Outlook"\n'
        '  set subj to (do shell script "cat " & quoted form of POSIX path of (POSIX file "{subj_file}"))\n'
        '  set htmlBody to (do shell script "cat " & quoted form of POSIX path of (POSIX file "{body_file}"))\n'
        '  set newMessage to make new outgoing message with properties '
        '{{subject:subj, content:htmlBody}}\n'
        '  make new to recipient at newMessage with properties '
        '{{email address:{{address:"{recipient}"}}}}\n'
        '  send newMessage\n'
        'end tell'
    )

    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as sf:
        sf.write(subject)
        subj_file = sf.name
    with tempfile.NamedTemporaryFile(mode="w", suffix=".html", delete=False) as bf:
        bf.write(body_html)
        body_file = bf.name

    final_script = script.format(
        subj_file=subj_file, body_file=body_file, recipient=RECIPIENT
    )

    try:
        result = subprocess.run(
            ["osascript", "-e", final_script],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            print(f"ERROR sending email: {result.stderr}", file=sys.stderr)
            return False
        return True
    finally:
        os.unlink(subj_file)
        os.unlink(body_file)


def main():
    all_conflicts = find_conflict_files()
    reported = load_reported()
    new_conflicts = [f for f in all_conflicts if f not in reported]

    if not new_conflicts:
        return

    # Build summary email
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    rel_paths = [os.path.relpath(f, WATCH_DIR) for f in new_conflicts]

    body_lines = [
        f"<h3>Syncthing Sync Conflicts Detected — {now}</h3>",
        f"<p><b>{len(new_conflicts)}</b> new conflict(s) in <code>AI-Vault</code>:</p>",
        "<table style='border-collapse:collapse; font-family:monospace; font-size:13px;'>",
        "<tr style='background:#25415C; color:white;'><th style='padding:6px 12px; text-align:left;'>#</th><th style='padding:6px 12px; text-align:left;'>File</th></tr>",
    ]
    for i, rp in enumerate(rel_paths, 1):
        bg = "#f2f2f2" if i % 2 == 0 else "#ffffff"
        body_lines.append(
            f"<tr style='background:{bg};'><td style='padding:4px 12px;'>{i}</td>"
            f"<td style='padding:4px 12px;'>{rp}</td></tr>"
        )
    body_lines.append("</table>")
    body_lines.append(
        "<p style='margin-top:16px; color:#666; font-size:12px;'>"
        "Resolve by keeping the preferred version and deleting the conflict copy.</p>"
    )
    body_html = "".join(body_lines)

    subject = f"Syncthing: {len(new_conflicts)} sync conflict(s) in AI-Vault"

    if send_email_via_outlook(subject, body_html):
        reported.update(new_conflicts)
        save_reported(reported)
        print(f"Sent conflict summary: {len(new_conflicts)} new conflict(s)")
    else:
        print("Failed to send email", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
