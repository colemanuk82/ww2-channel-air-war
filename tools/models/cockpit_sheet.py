#!/usr/bin/env python3
"""Tile labelled in-game cockpit frames into one sheet for review.

  python3 tools/models/cockpit_sheet.py build/cockpit_check build/cockpit_sheet.png [cols]
"""
import glob, os, subprocess, sys

FF = r"C:/Users/colem/AppData/Local/hermes/tools/ffmpeg-9.0.1-win32-x64/bin/ffmpeg.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

src = sys.argv[1] if len(sys.argv) > 1 else "build/cockpit_check"
out = sys.argv[2] if len(sys.argv) > 2 else "build/cockpit_sheet.png"
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 3

files = sorted(glob.glob(os.path.join(ROOT, src, "*.png")))
if not files:
    raise SystemExit("no frames in " + src)
files = [f for f in files if "overlay" not in f]

parts, inputs = [], []
for i, p in enumerate(files):
    name = os.path.basename(p).replace(".png", "")
    inputs += ["-i", p]
    parts.append("[%d:v]scale=620:-1,drawtext=fontfile=arialbd.ttf:text='%s':fontcolor=white:fontsize=24:"
                 "x=12:y=10:box=1:boxcolor=black@0.6:boxborderw=8[v%d]" % (i, name, i))
rows = (len(files) + cols - 1) // cols
fc = ";".join(parts) + ";" + "".join("[v%d]" % i for i in range(len(files))) + \
     "concat=n=%d:v=1:a=0,tile=%dx%d" % (len(files), cols, rows)

r = subprocess.run([FF, "-y"] + inputs + ["-filter_complex", fc, "-frames:v", "1", out],
                   capture_output=True, text=True)
print("exit", r.returncode, "->", out, os.path.getsize(out) if os.path.exists(out) else "MISSING")
if not os.path.exists(out):
    print((r.stderr or "")[-400:])
