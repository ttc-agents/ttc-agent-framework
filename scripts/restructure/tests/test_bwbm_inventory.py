import subprocess, sys, pathlib, csv
SCRIPT = pathlib.Path(__file__).parents[1] / "bwbm_inventory.py"

def test_inventory_lists_and_proposes_class(tmp_path):
    (tmp_path / "Agents" / "TAF" / "memory").mkdir(parents=True)
    (tmp_path / "Agents" / "TAF" / "memory" / "bwbm-yfbm.md").write_text("BwBm YFBM playwright", encoding="utf-8")
    (tmp_path / "Agents" / "SAP" / "memory").mkdir(parents=True)
    (tmp_path / "Agents" / "SAP" / "memory" / "generic.md").write_text("generic sap skill", encoding="utf-8")
    out = tmp_path / "inv.csv"
    r = subprocess.run([sys.executable, str(SCRIPT), "--root", str(tmp_path),
                        "--names", "bwbm,bundeswehr", "--out", str(out)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    rows = list(csv.DictReader(out.open()))
    paths = {pathlib.Path(x["path"]).name for x in rows}
    assert "bwbm-yfbm.md" in paths            # matched
    assert "generic.md" not in paths          # no BwBm mention → not in inventory
    row = next(x for x in rows if x["path"].endswith("bwbm-yfbm.md"))
    assert row["proposed_class"] in {"customer", "capability", "review"}
    assert row["agent"] == "TAF"
