import subprocess, sys, pathlib, csv
SCRIPT = pathlib.Path(__file__).parents[1] / "migrate_apply.py"

def _manifest(p, rows):
    with open(p, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["path", "action", "target"])
        w.writeheader(); w.writerows(rows)

def _run(man, *args):
    return subprocess.run([sys.executable, str(SCRIPT), "--manifest", str(man), *args],
                          capture_output=True, text=True)

def test_dry_run_makes_no_changes(tmp_path):
    src = tmp_path / "a.md"; src.write_text("x", encoding="utf-8")
    tgt = tmp_path / "Agents" / "Leads" / "bwbm" / "memory" / "a.md"
    man = tmp_path / "m.csv"
    _manifest(man, [{"path": str(src), "action": "move", "target": str(tgt)}])
    r = _run(man)
    assert r.returncode == 0 and "DRY-RUN" in r.stdout
    assert src.exists() and not tgt.exists()

def test_apply_agent_move_leaves_stub(tmp_path):
    src = tmp_path / "Agents" / "TAF" / "memory" / "bwbm-x.md"
    src.parent.mkdir(parents=True); src.write_text("real", encoding="utf-8")
    tgt = tmp_path / "Agents" / "Leads" / "bwbm" / "memory" / "taf__bwbm-x.md"
    man = tmp_path / "m.csv"
    _manifest(man, [{"path": str(src), "action": "move", "target": str(tgt)}])
    r = _run(man, "--apply")
    assert r.returncode == 0
    assert tgt.read_text() == "real"
    assert src.exists() and "MOVED ->" in src.read_text()   # forwarding stub

def test_apply_kb_move_no_stub(tmp_path):
    src = tmp_path / "kb" / "f.txt"; src.parent.mkdir(parents=True); src.write_text("d", encoding="utf-8")
    tgt = tmp_path / "AI-INFO - DO NOT DELETE" / "converted" / "f.txt"
    man = tmp_path / "m.csv"
    _manifest(man, [{"path": str(src), "action": "move", "target": str(tgt)}])
    r = _run(man, "--apply")
    assert r.returncode == 0
    assert tgt.read_text() == "d" and not src.exists()      # no stub in kb mode

def test_never_clobbers_existing_target(tmp_path):
    src = tmp_path / "a.md"; src.write_text("new", encoding="utf-8")
    tgt = tmp_path / "Agents" / "Leads" / "bwbm" / "memory" / "a.md"
    tgt.parent.mkdir(parents=True); tgt.write_text("EXISTING", encoding="utf-8")
    man = tmp_path / "m.csv"
    _manifest(man, [{"path": str(src), "action": "move", "target": str(tgt)}])
    r = _run(man, "--apply")
    assert r.returncode == 0 and "SKIP (target exists)" in r.stdout
    assert tgt.read_text() == "EXISTING" and src.exists()   # untouched
