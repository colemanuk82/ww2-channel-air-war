#!/usr/bin/env python3
"""Contact sheet of the per-aircraft 'view from the pilot's seat' renders, with names burned in.

Reads the *_eye.png sheets that `build_all.py --eye` writes (a camera at each aircraft's CockpitEye
looking forward over the nose) and tiles them so all 25 can be checked in one look.
"""
import glob, os, subprocess

FF = r"C:/Users/colem/AppData/Local/hermes/tools/ffmpeg-9.0.1-win32-x64/bin/ffmpeg.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHEETS = os.path.join(ROOT, "tools", "shots", "models")
OUT = os.path.join(ROOT, "build", "eye_sheet.png")

files = sorted(glob.glob(os.path.join(SHEETS, "*_eye.png")))
if not files:
    raise SystemExit("no eye renders found - run: blender --background --python tools/models/build_all.py -- <ids> --eye")

lst = os.path.join(ROOT, "build", "eye_list.txt")
with open(lst, "w") as f:
    for p in files:
        f.write("file '%s'\nduration 0.05\n" % p.replace("\\", "/"))
    f.write("file '%s'\n" % files[-1].replace("\\", "/"))

# label each frame with its aircraft id, then tile. Each image is its own input, so the filter can
# reference [0:v]..[N-1:v]; the concat demuxer would collapse them into a single stream.
parts = []
inputs = []
for i, p in enumerate(files):
    name = os.path.basename(p).replace("_eye.png", "")
    inputs += ["-i", p]
    parts.append(
        "[%d:v]scale=320:-1,drawtext=fontfile=arialbd.ttf:text='%s':fontcolor=black:fontsize=20:"
        "x=8:y=8:box=1:boxcolor=white@0.85:boxborderw=6[v%d]" % (i, name, i))
filter_complex = ";".join(parts) + ";" + "".join("[v%d]" % i for i in range(len(files))) + "concat=n=%d:v=1:a=0,tile=5x5" % len(files)

cmd = [FF, "-y"] + inputs + ["-filter_complex", filter_complex, "-frames:v", "1", OUT]
print("inputs:", len(files))
r = subprocess.run(cmd, capture_output=True, text=True)
print("exit", r.returncode)
if os.path.exists(OUT):
    print("sheet:", OUT, os.path.getsize(OUT), "bytes")
else:
    print((r.stderr or "")[-600:])
