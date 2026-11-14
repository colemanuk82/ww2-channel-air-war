"""Top-down SVG of an airfield's dressing check (tools/dbg/dress_check.gd output), airfield local frame.

    python tools/dbg/dress_svg.py build/dbg/dress_triangle.json [more.json ...]   -> writes .svg next to each

Grey: pavement; dark grey: runways; blue: taxi-out routes; green dots: parked aircraft; gold rings: reserved
taxi-flight pads; orange squares: crate stacks; red circles: drum stacks; purple lines: service-vehicle loops.
"""
import json
import sys


def svg_for(d):
    xs, zs = [], []
    for r in d["paved"] + d["runways"]:
        xs += [r[0], r[2]]
        zs += [r[1], r[3]]
    for s in d["stacks"]:
        xs.append(s[1]); zs.append(s[2])
    for v in d["vehicles"]:
        for p in v[1]:
            xs.append(p[0]); zs.append(p[1])
    pad = 80
    x0, x1, z0, z1 = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad
    w, h = x1 - x0, z1 - z0
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0} {z0} {w} {h}" width="100%" '
           f'style="background:#5d7a45">']
    out.append(f'<text x="{x0 + 20}" y="{z0 + 50}" font-size="40" fill="#fff">{d["style"]}</text>')
    for r in d["paved"]:
        out.append(f'<line x1="{r[0]}" y1="{r[1]}" x2="{r[2]}" y2="{r[3]}" stroke="#9a9a90" stroke-width="{r[4] * 2}" stroke-linecap="round"/>')
    for r in d["runways"]:
        out.append(f'<line x1="{r[0]}" y1="{r[1]}" x2="{r[2]}" y2="{r[3]}" stroke="#555" stroke-opacity="0.7" stroke-width="{r[4] * 2}"/>')
    for rt in d["routes"]:
        pts = " ".join(f"{p[0]},{p[1]}" for p in rt)
        out.append(f'<polyline points="{pts}" fill="none" stroke="#3060ff" stroke-width="4"/>')
    for v in d["vehicles"]:
        pts = " ".join(f"{p[0]},{p[1]}" for p in v[1])
        out.append(f'<polyline points="{pts}" fill="none" stroke="#b040d0" stroke-width="3" stroke-dasharray="12 6"/>')
    for p in d["flight_pads"]:
        out.append(f'<circle cx="{p[0]}" cy="{p[1]}" r="24" fill="none" stroke="#ffd000" stroke-width="4"/>')
    for p in d["parked"]:
        out.append(f'<circle cx="{p[0]}" cy="{p[1]}" r="7" fill="#1f3d14" stroke="#fff" stroke-width="1.5"/>')
    for s in d["stacks"]:
        if s[0] == "crates":
            out.append(f'<rect x="{s[1] - 5}" y="{s[2] - 5}" width="10" height="10" fill="#ff9020" stroke="#000"/>')
        else:
            out.append(f'<circle cx="{s[1]}" cy="{s[2]}" r="5.5" fill="#e02020" stroke="#000"/>')
    out.append("</svg>")
    return "\n".join(out)


for path in sys.argv[1:]:
    with open(path) as f:
        d = json.load(f)
    o = path.rsplit(".", 1)[0] + ".svg"
    with open(o, "w") as f:
        f.write(svg_for(d))
    print(o)
