#!/usr/bin/env python3
"""Load every mission (every side) in the real game engine, headless and silent (no window, no sound), and report script
errors / warnings. Complements tools/validate_missions.py (data checks) with a runtime smoke test.
Usage: python tools/run_all_missions.py [--frames 900] [--jobs 3] [--only substring] [--godot <console exe>]
Each run: --headless --audio-driver Dummy --quit-after N -- --skip-menu --mode=historical --mission=ID --side=SIDE --wp-teleport
Exit code 1 if any mission printed a script error."""
import argparse
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"F:\godot-rtx\bin\godot.windows.editor.x86_64.console.exe"
BAD = re.compile(r"SCRIPT ERROR|Parse Error|Invalid call|Nonexistent function|Invalid access|Cannot call|Invalid get index|Invalid set index|Attempt to call", re.I)
WARN = re.compile(r"^WARNING: (?!.*(leaked|ObjectDB|DLSS|RID))|unknown mission|no targets|push_warning", re.I)


def run_one(godot, frames, mid, side):
    t0 = time.time()
    cmd = [godot, "--headless", "--audio-driver", "Dummy", "--path", ROOT, "--quit-after", str(frames), "--",
           "--skip-menu", "--mode=historical", "--mission=" + mid, "--side=" + side, "--wp-teleport", "--spawn-debug"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=600, encoding="utf-8", errors="replace")
        out = (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return mid, side, ["TIMEOUT (600 s)"], [], time.time() - t0, ""
    errs = [l.strip() for l in out.splitlines() if BAD.search(l)]
    warns = [l.strip() for l in out.splitlines() if WARN.search(l)]
    spawn = next((l.strip() for l in out.splitlines() if l.startswith("[spawn]")), "")
    return mid, side, errs, warns, time.time() - t0, spawn


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", type=int, default=900)
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--only", default="")
    ap.add_argument("--godot", default=GODOT)
    a = ap.parse_args()
    missions = json.load(open(os.path.join(ROOT, "data", "missions.json"), encoding="utf-8"))["missions"]
    jobs = [(m["id"], s["side"]) for m in missions if a.only in m["id"] for s in m["sides"]]
    print("running %d mission/side combinations, %d at a time, %d frames each" % (len(jobs), a.jobs, a.frames), flush=True)
    bad, warned, n = [], [], 0
    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = [ex.submit(run_one, a.godot, a.frames, mid, side) for mid, side in jobs]
        for f in cf.as_completed(futs):
            mid, side, errs, warns, dt, spawn = f.result()
            n += 1
            tag = "ERROR" if errs else ("warn " if warns else "ok   ")
            print("%3d/%d %s %-58s %-6s %3.0fs" % (n, len(jobs), tag, mid[:58], side, dt), flush=True)
            for e in errs[:3]:
                print("        " + e[:200], flush=True)
            if errs:
                bad.append((mid, side, errs))
            elif warns:
                warned.append((mid, side, warns))
    print("\ndone: %d combinations, %d with script errors, %d with warnings" % (len(jobs), len(bad), len(warned)))
    for mid, side, w in warned[:25]:
        print("  warn  %s (%s): %s" % (mid, side, w[0][:160]))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
