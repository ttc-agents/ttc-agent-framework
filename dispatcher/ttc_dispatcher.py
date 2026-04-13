#!/usr/bin/env python3
"""
TTC Task Dispatcher

Replaces multiple LaunchAgents with a single dispatcher.
Runs periodically via launchd (e.g. StartInterval: 900 = every 15 min).
Checks scheduled tasks and file watches, executing as needed.

Configuration is loaded from dispatcher-config.json (same directory).

Usage:
    python3 ttc_dispatcher.py              # normal run
    python3 ttc_dispatcher.py --dry-run    # show what would run, don't execute
    python3 ttc_dispatcher.py --force NAME # force-run a specific task
    python3 ttc_dispatcher.py --status     # show state and next fire times
    python3 ttc_dispatcher.py --config /path/to/config.json  # use custom config
"""

import fcntl
import json
import os
import subprocess
import sys
from datetime import datetime, time, timedelta
from pathlib import Path

# ── Config loading ────────────────────────────────────────────────────────────

DEFAULT_CONFIG = Path(__file__).parent / "dispatcher-config.json"


def load_config(config_path: Path) -> dict:
    """Load dispatcher configuration from JSON file."""
    if not config_path.exists():
        print(f"ERROR: Config file not found: {config_path}")
        print(f"Copy dispatcher-config.example.json to dispatcher-config.json and edit it.")
        sys.exit(1)
    with open(config_path) as f:
        return json.load(f)


def resolve_path(p: str, base_dir: str) -> str:
    """Resolve a path, expanding ~ and substituting {base_dir}."""
    return os.path.expanduser(p.replace("{base_dir}", base_dir))


def build_tasks(config: dict):
    """Build SCHEDULED_TASKS and WATCH_TASKS from config."""
    base_dir = os.path.expanduser(config.get("base_dir", "~/AI-Vault"))
    default_python = resolve_path(config.get("default_python", "python3"), base_dir)
    state_file = Path(resolve_path(config.get("state_file", "{base_dir}/.dispatcher-state.json"), base_dir))
    lock_file = Path(resolve_path(config.get("lock_file", "~/.ttc-dispatcher.lock"), base_dir))

    scheduled = []
    for t in config.get("scheduled_tasks", []):
        scheduled.append({
            "name": t["name"],
            "times": [tuple(pair) for pair in t["times"]],
            "script": resolve_path(t["script"], base_dir),
            "args": t.get("args", []),
            "python": resolve_path(t.get("python", default_python), base_dir),
            "log": resolve_path(t.get("log", f"{{base_dir}}/logs/{t['name']}.log"), base_dir),
        })

    watched = []
    for t in config.get("watch_tasks", []):
        watched.append({
            "name": t["name"],
            "watch": resolve_path(t["watch"], base_dir),
            "script": resolve_path(t["script"], base_dir),
            "args": t.get("args", []),
            "python": resolve_path(t.get("python", default_python), base_dir),
            "log": resolve_path(t.get("log", f"{{base_dir}}/logs/{t['name']}.log"), base_dir),
        })

    return scheduled, watched, state_file, lock_file


# ── Helpers ────────────────────────────────────────────────────────────────────


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def load_state(state_file):
    if state_file.exists():
        with open(state_file) as f:
            return json.load(f)
    return None


def save_state(state, state_file):
    state_file.parent.mkdir(parents=True, exist_ok=True)
    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)


def init_state(now, scheduled_tasks, watch_tasks):
    """First run: set last_run = now for all tasks so nothing catches up."""
    state = {
        "scheduled": {t["name"]: now.isoformat() for t in scheduled_tasks},
        "watched": {},
    }
    for t in watch_tasks:
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


def cmd_status(scheduled_tasks, watch_tasks, state_file):
    """Show current state and next fire times."""
    state = load_state(state_file)
    now = datetime.now()
    print(f"Current time: {now.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"State file:   {state_file}")
    print()

    if state is None:
        print("No state file -- first run has not happened yet.")
        return

    print("Scheduled tasks:")
    for task in scheduled_tasks:
        name = task["name"]
        last = state["scheduled"].get(name, "never")
        nxt = next_fire_time(task["times"], now)
        nxt_str = nxt.strftime("%Y-%m-%d %H:%M") if nxt else "?"
        due = should_run(task["times"], last, now) if last != "never" else False
        flag = " ** DUE **" if due else ""
        print(f"  {name:25s}  last={last[:16]:16s}  next={nxt_str}{flag}")

    print("\nWatch tasks:")
    for task in watch_tasks:
        name = task["name"]
        stored = state["watched"].get(name, 0)
        try:
            current = os.path.getmtime(task["watch"])
        except OSError:
            current = 0
        changed = current > stored
        flag = " ** CHANGED **" if changed else ""
        print(f"  {name:25s}  watching={task['watch']}{flag}")


def cmd_force(task_name, scheduled_tasks, watch_tasks, state_file):
    """Force-run a specific task by name."""
    all_tasks = scheduled_tasks + watch_tasks
    task = next((t for t in all_tasks if t["name"] == task_name), None)
    if not task:
        print(f"Unknown task: {task_name}")
        print(f"Available: {', '.join(t['name'] for t in all_tasks)}")
        sys.exit(1)

    log(f"Force-running {task_name}...")
    rc = run_task(task)
    log(f"  {task_name} exited with code {rc}")

    # Update state
    state = load_state(state_file) or init_state(datetime.now(), scheduled_tasks, watch_tasks)
    now = datetime.now()
    if task_name in state["scheduled"]:
        state["scheduled"][task_name] = now.isoformat()
    if task_name in state["watched"]:
        try:
            state["watched"][task_name] = os.path.getmtime(task["watch"])
        except (OSError, KeyError):
            pass
    save_state(state, state_file)


def cmd_dry_run(scheduled_tasks, watch_tasks, state_file):
    """Show what would run without executing."""
    state = load_state(state_file)
    now = datetime.now()
    log("DRY RUN -- no tasks will be executed")

    if state is None:
        log("No state file -- first real run will initialize state.")
        return

    for task in scheduled_tasks:
        name = task["name"]
        last = state["scheduled"].get(name)
        if last is None:
            log(f"  {name}: NEW task, would set baseline")
        elif should_run(task["times"], last, now):
            log(f"  {name}: WOULD RUN (last={last[:16]})")
        else:
            log(f"  {name}: not due")

    for task in watch_tasks:
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


def cmd_run(scheduled_tasks, watch_tasks, state_file):
    """Normal dispatcher run."""
    now = datetime.now()

    state = load_state(state_file)
    if state is None:
        log("First run -- initializing state (no catch-up)")
        state = init_state(now, scheduled_tasks, watch_tasks)
        save_state(state, state_file)
        return

    ran = []
    skipped = []

    # -- Scheduled tasks
    for task in scheduled_tasks:
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
            save_state(state, state_file)
            ran.append(f"{name}(rc={rc})")
        else:
            skipped.append(name)

    # -- File watches
    for task in watch_tasks:
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
                try:
                    state["watched"][name] = os.path.getmtime(task["watch"])
                except OSError:
                    state["watched"][name] = current_mtime
                save_state(state, state_file)
                ran.append(f"{name}(rc={rc})")
            else:
                skipped.append(name)
        except Exception as e:
            log(f"  ERROR processing watch task {name}: {e}")

    # -- Final save and summarize
    save_state(state, state_file)

    if ran:
        log(f"Ran: {', '.join(ran)} | Skipped: {len(skipped)}")
    else:
        log(f"No tasks due. Skipped: {len(skipped)}")


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    args = sys.argv[1:]

    # Parse --config flag
    config_path = DEFAULT_CONFIG
    if "--config" in args:
        idx = args.index("--config")
        if idx + 1 < len(args):
            config_path = Path(args[idx + 1])
            args = args[:idx] + args[idx + 2:]
        else:
            print("Usage: --config /path/to/config.json")
            sys.exit(1)

    config = load_config(config_path)
    scheduled_tasks, watch_tasks, state_file, lock_file = build_tasks(config)

    if "--status" in args:
        cmd_status(scheduled_tasks, watch_tasks, state_file)
        sys.exit(0)

    if "--dry-run" in args:
        cmd_dry_run(scheduled_tasks, watch_tasks, state_file)
        sys.exit(0)

    if "--force" in args:
        idx = args.index("--force")
        if idx + 1 >= len(args):
            print("Usage: --force TASK_NAME")
            sys.exit(1)
        cmd_force(args[idx + 1], scheduled_tasks, watch_tasks, state_file)
        sys.exit(0)

    # Normal run -- acquire exclusive lock
    lock_fd = open(lock_file, "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)  # another instance running

    try:
        cmd_run(scheduled_tasks, watch_tasks, state_file)
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()
