#!/usr/bin/env python3
"""Batch the per-aircraft cockpit frames into labelled review sheets.

  python3 tools/models/cockpit_batches.py [src_dir] [out_dir] [per_sheet]

Writes JPGs sized for reading on a phone (each cell ~900 px wide) so the framing, eye height and
interior can actually be judged, plus a plain list of which frame sits in which position.
"""
import glob, os, subprocess, sys

FF = r"C:/Users/colem/AppData/Local/hermes/tools/ffmpeg-9.0.1-win32-x64/bin/ffmpeg.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

src = os.path.join(ROOT, sys.argv[1] if len(sys.argv) > 1 else "build/cockpit_all")
outdir = os.path.join(ROOT, sys.argv[2] if len(sys.argv) > 2 else "build/share")
per = int(sys.argv[3]) if len(sys.argv) > 3 else 6
cols = 3

files = sorted(f for f in glob.glob(os.path.join(src, "*.png")))
if not files:
    raise SystemExit("no frames in " + src)

os.makedirs(outdir, exist_ok=True)
sheets = 0
for b in range(0, len(files), per):
    batch = files[b:b + per]
    rows = (len(batch) + cols - 1) // cols
    parts, inputs = [], []
    for i, p in enumerate(batch):
        name = os.path.basename(p).replace(".png", "")
        inputs += ["-i", p]
        parts.append("[%d:v]scale=880:-1,drawtext=fontfile=arialbd.ttf:text='%s':fontcolor=white:"
                     "fontsize=34:x=18:y=14:box=1:boxcolor=black@0.65:boxborderw=10[v%d]" % (i, name, i))
    fc = ";".join(parts) + ";" + "".join("[v%d]" % i for i in range(len(batch))) + \
         "concat=n=%d:v=1:a=0,tile=%dx%d" % (len(batch), cols, rows)
    png = os.path.join(outdir, "cockpit_page%d.png" % (sheets + 1))
    jpg = os.path.join(outdir, "cockpit_page%d.jpg" % (sheets + 1))
    r = subprocess.run([FF, "-y"] + inputs + ["-filter_complex", fc, "-frames:v", "1", png],
                       capture_output=True, text=True)
    if not os.path.exists(png):
        print("sheet failed:", (r.stderr or "")[-300:]); continue
    subprocess.run([FF, "-y", "-i", png, "-vf", "scale=1600:-1", "-q:v", "3", jpg],
                   capture_output=True, text=True)
    os.remove(png)
    ids = " | ".join(os.path.basename(x).replace(".png", "") for x in batch)
    print("page%d: %s" % (sheets + 1, ids), "->", jpg, os.path.getsize(jpg), "bytes")
    sheets += 1

print("\ntotal frames:", len(files), "pages:", sheets)
missing = {"a20","b25","b26","bf109","bf110","blenheim","c47","defiant","do17","fw190","fw200","he111",
           "hurricane","ju52","ju87","ju88","lancaster","me262","mosquito","p38","p47","p51","spitfire",
           "tempest","typhoon"} - {os.path.basename(f).replace(".png", "") for f in files}
if missing:
    print("still missing:", sorted(missing))
