import json
import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).parents[1] / "curator_audit.py"


def _run(tmp_path, *extra):
    r = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(tmp_path),
         "--capabilities", "TAF,Tender,SAP,Contracts", "--dry-run", *extra],
        capture_output=True, text=True,
    )
    assert r.returncode == 0, r.stderr
    return r.stdout


def test_customer_file_in_working_is_a_leak(tmp_path):
    # A customer-specific binary sitting directly in a capability working/ dir is
    # genuine scatter → LEAK (working/ is scanned, binaries matched by name).
    d = tmp_path / "Agents" / "Tender" / "working"
    d.mkdir(parents=True)
    (d / "ADNOC-Technical-Bid.docx").write_bytes(b"PK\x03\x04 binary")
    out = _run(tmp_path, "--customers", "ADNOC")
    assert "[LEAK]" in out
    assert "ADNOC-Technical-Bid.docx" in out


def test_customer_dir_is_rolled_up_to_one_finding(tmp_path):
    # A whole customer working-tree must be ONE finding (the dir), not one-per-file.
    d = tmp_path / "Agents" / "SAP" / "working" / "qatar-energy"
    d.mkdir(parents=True)
    (d / "a.pptx").write_bytes(b"PK")
    (d / "b.xlsx").write_bytes(b"PK")
    (d / ".DS_Store").write_bytes(b"\x00")
    out = _run(tmp_path, "--customers", "qatar-energy")
    assert out.count("[LEAK]") == 1          # rolled up, not 3
    assert "working/qatar-energy/" in out
    assert "a.pptx" not in out and ".DS_Store" not in out


def test_body_only_mention_in_reusable_file_is_mention_not_leak(tmp_path):
    # A reusable, generically-named capability file that merely names a customer as
    # an example is NOT misplaced → MENTION (informational), never LEAK.
    cap = tmp_path / "Agents" / "SAP" / "memory"
    cap.mkdir(parents=True)
    (cap / "sap-landscape.md").write_text(
        "Active engagements include BwBm and ENOC; reusable landscape notes.",
        encoding="utf-8",
    )
    out = _run(tmp_path, "--customers", "BwBm,ENOC")
    assert "[MENTION]" in out
    assert "[LEAK]" not in out


def test_sensitive_figure_still_flagged(tmp_path):
    cap = tmp_path / "Agents" / "TAF" / "memory"
    cap.mkdir(parents=True)
    (cap / "note.md").write_text("day rate EUR 1,250 for the work", encoding="utf-8")
    out = _run(tmp_path, "--customers", "BwBm")
    assert "[SENSITIVE]" in out


def test_alias_token_match_via_registry(tmp_path):
    # Abbreviations (DH, DIB) only appear in filenames; match them as path tokens via
    # the registry `aliases` field — and DON'T false-positive on substrings.
    reg = tmp_path / "registry.json"
    reg.write_text(json.dumps({"customers": {
        "dubai-holdings-leapwork": {"display_name": "Dubai Holdings Leapwork", "aliases": ["DH"]},
    }}), encoding="utf-8")
    d = tmp_path / "Agents" / "Tender" / "working"
    d.mkdir(parents=True)
    (d / "DH-QA-TOM-v0.7.docx").write_bytes(b"PK\x03\x04")
    # 'dh' embedded in a word must NOT trigger (token match, not substring):
    (d / "methodology-handbook.md").write_text("reusable, no customer", encoding="utf-8")
    out = _run(tmp_path, "--registry", str(reg))
    assert "[LEAK]" in out
    assert "DH-QA-TOM" in out
    assert "methodology-handbook" not in out


def test_match_keys_catch_naming_variants(tmp_path):
    # Registry slug is 'dubai-holdings-leapwork' but files use the variant 'dubai-holding'.
    # match_keys adds the variant as a substring key so the scatter is still caught.
    reg = tmp_path / "registry.json"
    reg.write_text(json.dumps({"customers": {
        "dubai-holdings-leapwork": {"display_name": "Dubai Holdings Leapwork",
                                    "match_keys": ["dubai-holding"]},
    }}), encoding="utf-8")
    cap = tmp_path / "Agents" / "Tender" / "memory"
    cap.mkdir(parents=True)
    (cap / "dubai-holding-qa-tom.md").write_text("DH QA TOM facts", encoding="utf-8")
    out = _run(tmp_path, "--registry", str(reg))
    assert "[LEAK]" in out
    assert "dubai-holding-qa-tom.md" in out


def test_allowlist_reclassifies_leak_to_accepted(tmp_path):
    # A triaged-by-policy scatter path (e.g. commercial in Contracts) listed in the
    # allowlist is reported as ACCEPTED, not LEAK, so weekly LEAK = un-triaged only.
    d = tmp_path / "Agents" / "Contracts" / "working" / "vkb"
    d.mkdir(parents=True)
    (d / "SoW-Extension.docx").write_bytes(b"PK")
    allow = tmp_path / "allow.txt"
    allow.write_text("Agents/Contracts/working/vkb  # commercial stays in Contracts\n", encoding="utf-8")
    out = _run(tmp_path, "--customers", "VKB", "--allow", str(allow))
    assert "[ACCEPTED]" in out
    assert "[LEAK]" not in out


def test_moved_stub_is_skipped(tmp_path):
    cap = tmp_path / "Agents" / "SAP" / "memory"
    cap.mkdir(parents=True)
    (cap / "qatar-energy-bph.md").write_text(
        "> MOVED -> Agents/Leads/qatar-energy/memory/qatar-energy-bph.md",
        encoding="utf-8",
    )
    out = _run(tmp_path, "--customers", "qatar-energy")
    # A MOVED tombstone is a forwarding pointer, not scatter — no LEAK.
    assert "[LEAK]" not in out
