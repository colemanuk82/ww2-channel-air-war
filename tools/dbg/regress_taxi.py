#!/usr/bin/env python
"""Run the headless taxi scenario on every airfield style and fail on any analysis finding.
Not part of the TESTS OK gate (it needs ~10 s per style). Usage: python tools/dbg/regress_taxi.py [--wingmen 3] [styles...]"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import dbg

STYLES = ["raf_grass", "raf_bomber", "raf_fighter", "grass", "cross", "parallel", "night_fighter", "lw_fliegerhorst", "lw_field", "forward"]

ap = argparse.ArgumentParser()
ap.add_argument("--wingmen", type=int, default=3)
ap.add_argument("--secs", default="200")
ap.add_argument("styles", nargs="*", default=STYLES)
a = ap.parse_args()
bad = 0
for st in a.styles:
    try:
        name, wall, _ = dbg.run_sim(st, a.wingmen, a.secs, name="regress_" + st)
    except RuntimeError as e:
        print("%-16s ERROR %s" % (st, str(e).splitlines()[-1]))
        bad += 1
        continue
    fs = dbg.analyse(dbg.load(name))
    print("%-16s %4.1fs wall  %d finding(s)" % (st, wall, len(fs)))
    for f in fs[:6]:
        print("    t=%6.1f %-10s %s" % (f["t"], f["kind"], f["msg"]))
    bad += 1 if fs else 0
print("FAIL: %d style(s)" % bad if bad else "OK")
sys.exit(1 if bad else 0)
