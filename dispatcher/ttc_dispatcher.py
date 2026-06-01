#!/usr/bin/env python3
"""
TTC Task Dispatcher

Replaces 7 separate LaunchAgents with a single dispatcher.
Runs every 15 minutes via launchd (StartInterval: 900).
Checks scheduled tasks and file watches, executing as needed.

Usage:
    python3 ttc_dispatcher.py              # normal run
    python3 ttc_dispatcher.py --dry-run    # show what would run, don't execute
    python3 ttc_dispatcher.py --force NAME # force-run a specific task
    python3 ttc_dispatcher.py --status     # show state and next fire times
"""

import fcntl
import json
import os
import subprocess
import sys
from datetime import datetime, time, timedelta
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────

BASE_DIR = Path("{{AI_VAULT}}")
VENV_PYTHON = str(BASE_DIR / ".venv/bin/python3")
STATE_FILE = BASE_DIR / "Agents/.dispatcher-state.json"
LOCK_FILE = Path.home() / ".ttc-dispatcher.lock"

# ── Scheduled tasks ───────────────────────────────────────────────────────────
# times: list of (hour, minute) in local time

SCHEDULED_TASKS = [
    {
        "name": "morning-briefing",
        "times": [(7, 0)],
        "script": str(BASE_DIR / "Agents/Personal/morning-briefing.py"),
        "args": [],
        "python": VENV_PYTHON,
        "log": str(BASE_DIR / "Agents/Personal/morning-briefing.log"),
    },
    {
        "name": "hr-cv-check",
        "times": [(0, 0), (12, 0)],
        "script": str(BASE_DIR / "Agents/HR/egypt_cv_check_automation.py"),
        "args": [],
        "python": VENV_PYTHON,
        "log": str(BASE_DIR / "Agents/HR/egypt_cv_check.log"),
    },
    {
        "name": "kb-sales",
        "times": [(2, 0)],
        "script": str(BASE_DIR / "Claude Folder/convert_to_knowledge_base.py"),
        "args": [],
        "python": VENV_PYTHON,
        "log": str(BASE_DIR / "Claude Folder/conversion-sales.log"),
    },
    {
        "name": "kb-finance",
        "times": [(2, 15)],
        "script": str(BASE_DIR / "Claude Folder/convert_to_knowledge_base.py"),
        "args": [
            "--source",
            "{{HOME}}/Library/CloudStorage/"
            "OneDrive-TTCGlobal/Admin/Finance_Legal",
            "--dest",
            str(BASE_DIR / "Claude Folder/Knowledge Base/Finance"),
        ],
        "python": VENV_PYTHON,
        "log": str(BASE_DIR / "Claude Folder/conversion-finance.log"),
    },
    {
        "name": "sync-knowledge",
        "times": [(23, 30)],
        "script": str(BASE_DIR / "Agents/sync_personal_knowledge.py"),
        "args": [],
        "python": VENV_PYTHON,
        "log": str(BASE_DIR / "Agents/sync_check.log"),
    },
    {
        # Findability cross-index: aggregate every customer worklog.md (OneDrive
        # Delivery + Sales) into the Personal worklog-index. Static .md write only —
        # no kb_search/MCP impact. Semantic refresh (kb_vectorize --worklogs) stays
        # manual to avoid invalidating a live kb_search handle mid-session.
        "name": "worklog-index",
        "times": [(23, 35)],
        "script": str(BASE_DIR / "scripts/restructure/build_worklog_index.py"),
        "args": [
            "--roots",
            "{{HOME}}/Library/CloudStorage/"
            "OneDrive-TTCGlobal/Delivery",
            "{{HOME}}/Library/CloudStorage/"
            "OneDrive-TTCGlobal/Sales",
            "--out",
            str(BASE_DIR / "Agents/Personal/memory/worklog-index.md"),
        ],
        "python": VENV_PYTHON,
        "log": str(BASE_DIR / "Agents/Personal/worklog-index.log"),
    },
]

# ── File-watch tasks ──────────────────────────────────────────────────────────

WATCH_TASKS = [
    {
        "name": "fix-claude-permissions",
        "watch": str(Path.home() / ".claude.json"),
        "script": str(BASE_DIR / "fix-claude-permissions.py"),
        "args": [],
        "python": "/usr/bin/python3",
        "log": str(BASE_DIR / "logs/fix-claude-permissions.log"),
    },
    {
        "name": "fix-desktop-config",
        "watch": str(
            Path.home()
            / "Library/Application Support/Claude/claude_desktop_config.json"
        ),
        "script": str(BASE_DIR / "fix-desktop-config.py"),
        "args": [],
        "python": VENV_PYTHON,
        "log": str(BASE_DIR / "fix-desktop-config.log"),
    },
]

# ── Helpers ────────────────────────────────────────────────────────────────────


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def load_state():
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return None


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def init_state(now):
    """First run: set last_run = now for all tasks so nothing catches up."""
    state = {
        "scheduled": {t["name"]: now.isoformat() for t in SCHEDULED_TASKS},
        "watched": {},
    }
    for t in WATCH_TASKS:
        try:
            state["watched"][t["name"]] = os.path.getmtime(t["watch"])
        except OSError:
            state["watched"][t["name"]] = 0
    return state


def should_run(fire_times, last_run_str, now):
    """Check if any scheduled fire time falls in (last_run, now]."""
    last_run = datetime.fromisoformat(last_run_str)
    check_date = last_run.date()
    end_date = now.date()
    # Cap lookback at 7 days to avoid huge loops after long downtime
    max_lookback = now.date() - timedelta(days=7)
    if check_date < max_lookback:
        check_date = max_lookback
    while check_date <= end_date:
        for hour, minute in fire_times:
            ft = datetime.combine(check_date, time(hour, minute))
            if last_run < ft <= now:
                return True
        check_date += timedelta(days=1)
    return False


def next_fire_time(fire_times, now):
    """Compute the next upcoming fire time for display."""
    candidates = []
    for day_offset in range(2):  # today and tomorrow
        check_date = now.date() + timedelta(days=day_offset)
        for hour, minute in fire_times:
            ft = datetime.combine(check_date, time(hour, minute))
            if ft > now:
                candidates.append(ft)
    return min(candidates) if candidates else None


def run_task(task):
    """Execute a task script, appending output to its log file."""
    script = task["script"]
    if not os.path.isfile(script):
        log(f"  SKIP {task['name']}: script not found: {script}")
        return -1

    cmd = [task["python"], script] + task.get("args", [])
    log_path = task["log"]
    os.makedirs(os.path.dirname(log_path), exist_ok=True)

    try:
        with open(log_path, "a") as logf:
            result = subprocess.run(
                cmd, stdout=logf, stderr=logf, timeout=600
            )
        return result.returncode
    except subprocess.TimeoutExpired:
        log(f"  TIMEOUT: {task['name']} (killed after 600s)")
        return -1
    except Exception as e:
        log(f"  ERROR running {task['name']}: {e}")
        return -1


# ── Commands ───────────────────────────────────────────────────────────────────


def cmd_status():
    """Show current state and next fire times."""
    state = load_state()
    now = datetime.now()
    print(f"Current time: {now.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"State file:   {STATE_FILE}")
    print()

    if state is None:
        print("No state file — first run has not happened yet.")
        return

    print("Scheduled tasks:")
    for task in SCHEDULED_TASKS:
        name = task["name"]
        last = state["scheduled"].get(name, "never")
        nxt = next_fire_time(task["times"], now)
        nxt_str = nxt.strftime("%Y-%m-%d %H:%M") if nxt else "?"
        due = should_run(task["times"], last, now) if last != "never" else False
        flag = " ** DUE **" if due else ""
        print(f"  {name:25s}  last={last[:16]:16s}  next={nxt_str}{flag}")

    print("\nWatch tasks:")
    for task in WATCH_TASKS:
        name = task["name"]
        stored = state["watched"].get(name, 0)
        try:
            current = os.path.getmtime(task["watch"])
        except OSError:
            current = 0
        changed = current > stored
        flag = " ** CHANGED **" if changed else ""
        print(f"  {name:25s}  watching={task['watch']}{flag}")


def cmd_force(task_name):
    """Force-run a specific task by name."""
    all_tasks = SCHEDULED_TASKS + WATCH_TASKS
    task = next((t for t in all_tasks if t["name"] == task_name), None)
    if not task:
        print(f"Unknown task: {task_name}")
        print(f"Available: {', '.join(t['name'] for t in all_tasks)}")
        sys.exit(1)

    log(f"Force-running {task_name}...")
    rc = run_task(task)
    log(f"  {task_name} exited with code {rc}")

    # Update state
    state = load_state() or init_state(datetime.now())
    now = datetime.now()
    if task_name in state["scheduled"]:
        state["scheduled"][task_name] = now.isoformat()
    if task_name in state["watched"]:
        try:
            state["watched"][task_name] = os.path.getmtime(task["watch"])
        except (OSError, KeyError):
            pass
    save_state(state)


def cmd_dry_run():
    """Show what would run without executing."""
    state = load_state()
    now = datetime.now()
    log("DRY RUN — no tasks will be executed")

    if state is None:
        log("No state file — first real run will initialize state.")
        return

    for task in SCHEDULED_TASKS:
        name = task["name"]
        last = state["scheduled"].get(name)
        if last is None:
            log(f"  {name}: NEW task, would set baseline")
        elif should_run(task["times"], last, now):
            log(f"  {name}: WOULD RUN (last={last[:16]})")
        else:
            log(f"  {name}: not due")

    for task in WATCH_TASKS:
        name = task["name"]
        stored = state["watched"].get(name, 0)
        try:
            current = os.path.getmtime(task["watch"])
        except OSError:
            current = 0
        if current > stored:
            log(f"  {name}: WOULD RUN (file changed)")
        else:
            log(f"  {name}: no change")


def cmd_run():
    """Normal dispatcher run."""
    now = datetime.now()

    state = load_state()
    if state is None:
        log("First run — initializing state (no catch-up)")
        state = init_state(now)
        save_state(state)
        return

    ran = []
    skipped = []

    # ── Scheduled tasks ───────────────────────────────────
    for task in SCHEDULED_TASKS:
        name = task["name"]
        last_run = state["scheduled"].get(name)

        if last_run is None:
            state["scheduled"][name] = now.isoformat()
            skipped.append(name)
            continue

        if should_run(task["times"], last_run, now):
            log(f"  Running {name}...")
            rc = run_task(task)
            state["scheduled"][name] = now.isoformat()
            save_state(state)
            ran.append(f"{name}(rc={rc})")
        else:
            skipped.append(name)

    # ── File watches ──────────────────────────────────────
    for task in WATCH_TASKS:
        name = task["name"]
        try:
            stored_mtime = state["watched"].get(name, 0)

            try:
                current_mtime = os.path.getmtime(task["watch"])
            except OSError:
                current_mtime = 0

            if current_mtime > stored_mtime:
                log(f"  Running {name} (file changed)...")
                rc = run_task(task)
                # Re-read mtime after task ran (task may have modified the watched file)
                try:
                    state["watched"][name] = os.path.getmtime(task["watch"])
                except OSError:
                    state["watched"][name] = current_mtime
                save_state(state)
                ran.append(f"{name}(rc={rc})")
            else:
                skipped.append(name)
        except Exception as e:
            log(f"  ERROR processing watch task {name}: {e}")

    # ── Final save (safety net) and summarize ─────────────
    save_state(state)

    if ran:
        log(f"Ran: {', '.join(ran)} | Skipped: {len(skipped)}")
    else:
        log(f"No tasks due. Skipped: {len(skipped)}")


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    args = sys.argv[1:]

    if "--status" in args:
        cmd_status()
        sys.exit(0)

    if "--dry-run" in args:
        cmd_dry_run()
        sys.exit(0)

    if "--force" in args:
        idx = args.index("--force")
        if idx + 1 >= len(args):
            print("Usage: --force TASK_NAME")
            sys.exit(1)
        cmd_force(args[idx + 1])
        sys.exit(0)

    # Normal run — acquire exclusive lock
    lock_fd = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)  # another instance running

    try:
        cmd_run()
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()
