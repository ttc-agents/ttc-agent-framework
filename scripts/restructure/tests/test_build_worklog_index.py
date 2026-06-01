# scripts/restructure/tests/test_build_worklog_index.py
import subprocess, sys, pathlib, textwrap
SCRIPT = pathlib.Path(__file__).parents[1] / "build_worklog_index.py"

def _wl(p, text):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(textwrap.dedent(text), encoding="utf-8")

def test_index_aggregates_entries_by_customer_and_tag(tmp_path):
    _wl(tmp_path / "bwbm" / "worklog.md", """
        ## 2026-05-31 — Q02 regression
        - Capability: TAF
        - Tags: #sap #regression
        ## 2026-05-12 — STP chain
        - Capability: TAF
        - Tags: #playwright #stp
    """)
    out = tmp_path / "worklog-index.md"
    r = subprocess.run([sys.executable, str(SCRIPT), "--roots", str(tmp_path),
                        "--out", str(out)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    idx = out.read_text(encoding="utf-8")
    assert "bwbm" in idx
    assert "Q02 regression" in idx and "STP chain" in idx
    assert "#regression" in idx and "#playwright" in idx
    # newest first
    assert idx.index("Q02 regression") < idx.index("STP chain")
