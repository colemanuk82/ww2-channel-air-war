#!/usr/bin/env python
"""Render a taxi run log to a top-down PNG (no browser needed): pavement, taxi graph, dispersals, routes,
trails and final positions. Usage: python tools/dbg/png.py <name> [out.png] [--t T]"""
import os, sys, math
sys.path.insert(0, os.path.dirname(__file__))
import dbg
from PIL import Image, ImageDraw

COLS = [(230, 60, 60), (40, 140, 255), (40, 190, 80), (240, 160, 20), (170, 70, 220), (0, 190, 190)]


def render(name, out=None, t_at=None, size=1100):
    d = dbg.load(name)
    L = d["layout"]
    pts = [tuple(p) for p in L["taxi_nodes"]] + [tuple(p) for p in L["dispersals"]] + [tuple(L["hold"]), tuple(L["entry"])]
    for a in d["agents"]:
        pts += [tuple(p) for p in a["route"]]
    rl = L["runway"]["length"] * 0.5
    pts += [(0, -rl), (0, rl)]
    xs = [p[0] for p in pts]; zs = [p[1] for p in pts]
    x0, x1, z0, z1 = min(xs) - 40, max(xs) + 40, min(zs) - 40, max(zs) + 40
    s = size / max(x1 - x0, z1 - z0)
    W, H = int((x1 - x0) * s) + 1, int((z1 - z0) * s) + 1
    im = Image.new("RGB", (W, H), (60, 90, 50))
    dr = ImageDraw.Draw(im)
    P = lambda x, z: ((x - x0) * s, (z - z0) * s)
    for pv in L["paved"]:
        if len(pv) == 3 and isinstance(pv[0], list) and isinstance(pv[1], list):
            dr.line([P(*pv[0]), P(*pv[1])], fill=(105, 105, 100), width=max(1, int(pv[2] * 2 * s)))
        elif len(pv) >= 2 and isinstance(pv[0], list):
            r = float(pv[1]) * s
            c = P(*pv[0]); dr.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=(105, 105, 100))
    rw = L["runway"]["width"] * 0.5
    dr.rectangle([P(-rw, -rl), P(rw, rl)], fill=(80, 80, 78))
    nodes = L["taxi_nodes"]
    for e in L["taxi_edges"]:
        dr.line([P(*nodes[e[0]]), P(*nodes[e[1]])], fill=(200, 200, 120), width=1)
    for i, p in enumerate(nodes):
        c = P(*p); dr.ellipse([c[0] - 2, c[1] - 2, c[0] + 2, c[1] + 2], fill=(220, 220, 140))
    for pr in L.get("props", []):
        c = P(pr[0], pr[1]); hx, hz = pr[2] * s, pr[3] * s
        dr.rectangle([c[0] - hx, c[1] - hz, c[0] + hx, c[1] + hz], outline=(150, 60, 40))
    for i, p in enumerate(L["dispersals"]):
        c = P(*p); dr.ellipse([c[0] - 5, c[1] - 5, c[0] + 5, c[1] + 5], outline=(255, 255, 255))
        dr.text((c[0] + 6, c[1] - 6), str(i), fill=(255, 255, 255))
    for h in L.get("holds", []):
        c = P(*h); dr.rectangle([c[0] - 3, c[1] - 3, c[0] + 3, c[1] + 3], outline=(255, 140, 140))
    for nm, col in (("hold", (255, 80, 80)), ("entry", (255, 255, 255))):
        c = P(*L[nm]); dr.rectangle([c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4], outline=col)
    ser = dbg.series(d)
    for k, a in enumerate(d["agents"]):
        col = COLS[k % len(COLS)]
        r = a["route"]
        dr.line([P(*p) for p in r], fill=tuple(int(v * 0.55) for v in col), width=1)
        tr = [(x, z) for (t, x, z, *_r) in ser[a["id"]] if t_at is None or t <= t_at]
        if len(tr) > 1:
            dr.line([P(*p) for p in tr], fill=col, width=2)
        if tr:
            c = P(*tr[-1]); rr = a["radius"] * s
            dr.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=col, width=2)
            dr.text((c[0] + rr + 2, c[1]), a["id"], fill=col)
    dr.text((6, 6), "%s  %s  t<=%s  (take-off toward top)" % (L["style"], d["reason"], t_at if t_at is not None else d["sim_secs"]), fill=(255, 255, 255))
    out = out or os.path.join(dbg.RUNS, name + ".png")
    im.save(out)
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    t = None
    if "--t" in args:
        i = args.index("--t"); t = float(args[i + 1]); del args[i:i + 2]
    print(render(args[0], args[1] if len(args) > 1 else None, t))
