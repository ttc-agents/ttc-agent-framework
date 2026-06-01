#!/usr/bin/env python3
"""Apply the BwBm migration manifest. DRY-RUN by default; --apply performs moves.

Two modes (auto-detected from target):
  - kb    : target under '.../AI-INFO - DO NOT DELETE/converted/' -> bulk move, NO stub.
  - agent : target under 'Agents/Leads/' -> move + leave a forwarding stub at source.

Safety: never clobbers an existing target; skips+warns on missing source or existing target.
Only rows with action == 'move' are acted on.
"""
import argparse, csv, pathlib, shutil

def mode_of(target):
    return "kb" if "/AI-INFO - DO NOT DELETE/converted/" in target else "agent"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="scripts/restructure/bwbm_manifest.csv")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    with open(a.manifest, encoding="utf-8") as fh:
        rows = [r for r in csv.DictReader(fh) if r.get("action") == "move"]
    skipped = 0
    by_mode = {"kb": 0, "agent": 0}
    for r in rows:
        src = pathlib.Path(r["path"]); tgt = pathlib.Path(r["target"]); m = mode_of(r["target"])
        if not src.exists():
            print(f"SKIP (src missing): {src}"); skipped += 1; continue
        if tgt.exists():
            print(f"SKIP (target exists): {tgt}"); skipped += 1; continue
        if not a.apply:
            print(f"DRY-RUN [{m}] {src} -> {tgt}"); by_mode[m] += 1; continue
        tgt.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(tgt))
        if m == "agent":
            try:
                src.write_text(f"> MOVED -> {tgt}\n", encoding="utf-8")
            except OSError as e:
                print(f"ERROR (moved OK but stub failed) {src}: {e}")
        by_mode[m] += 1
    verb = "MOVED" if a.apply else "WOULD MOVE"
    print(f"\n--- {'APPLIED' if a.apply else 'DRY-RUN'}: {verb} {by_mode['kb']} kb + "
          f"{by_mode['agent']} agent = {by_mode['kb']+by_mode['agent']} ; skipped {skipped} ---")

if __name__ == "__main__":
    main()
