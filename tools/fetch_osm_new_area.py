#!/usr/bin/env python3
"""Fetch roads and main rails for the part of the map added when the bounds grew (east of 4.7 E and north of 51.7 N),
and merge them with the original real Channel-area roads (tools/cache/roads_old_area.json).
Tiles are cached by bounding box (tools/cache/osm_new/), failed tiles are retried as four quarters, and re-running
resumes where it stopped. Output: data/osm/roads.json (old + new) and data/osm/rails.json (new area real rails; the old
synthetic network is kept for the Channel area).
Usage: python tools/fetch_osm_new_area.py [--layers roads,rails]"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_osm as fo  # noqa: E402

ROOT = fo.ROOT
CACHE = os.path.join(ROOT, "tools", "cache", "osm_new")
OLD = (48.9, -4.6, 51.7, 4.7)   # lat_min, lon_min, lat_max, lon_max of the original map
STEP_LAT, STEP_LON = 0.5, 1.0


def new_tiles():
    la = fo.LAT_MIN
    while la < fo.LAT_MAX - 1e-9:
        la2 = min(la + STEP_LAT, fo.LAT_MAX)
        lo = fo.LON_MIN
        while lo < fo.LON_MAX - 1e-9:
            lo2 = min(lo + STEP_LON, fo.LON_MAX)
            inside_old = la2 <= OLD[2] + 1e-9 and lo2 <= OLD[3] + 1e-9
            if not inside_old:
                yield (round(la, 4), round(lo, 4), round(la2, 4), round(lo2, 4))
            lo = lo2
        la = la2


def get_tile(layer, cfg, bb, depth=0):
    key = os.path.join(CACHE, "%s_%s_%s_%s_%s.json" % ((layer,) + tuple(bb)))
    if os.path.exists(key):
        return json.load(open(key)).get("elements", [])
    if os.environ.get("OSM_CACHE_ONLY"):       # merge whatever has been downloaded so far, no network
        return []
    try:
        data = fo.overpass(fo.tile_query(layer, cfg, bb))
        os.makedirs(CACHE, exist_ok=True)
        json.dump(data, open(key, "w"))
        time.sleep(1.2)
        return data.get("elements", [])
    except RuntimeError as e:
        if depth >= 2:
            print("   gave up on", bb, str(e)[:60], flush=True)
            return []
        s, w, n, e2 = bb
        ms, mw = (s + n) / 2, (w + e2) / 2
        els = []
        for sub in ((s, w, ms, mw), (s, mw, ms, e2), (ms, w, n, mw), (ms, mw, n, e2)):
            els += get_tile(layer, cfg, tuple(round(x, 4) for x in sub), depth + 1)
        return els


def run(layer):
    cfg = fo.LAYERS[layer]
    lines, seen = [], set()
    tl = list(new_tiles())
    for i, bb in enumerate(tl):
        els = get_tile(layer, cfg, bb)
        print("  [%s] %d/%d %s: %d elements" % (layer, i + 1, len(tl), bb, len(els)), flush=True)
        for el in els:
            if el.get("id") in seen or not el.get("geometry"):
                continue
            seen.add(el.get("id"))
            tags = el.get("tags", {})
            k = tags.get("highway") or tags.get("railway") or "x"
            for run_ in fo.split_geom(el["geometry"]):
                lines.append(dict(k=k, pts=fo.r4(fo.dp(run_, cfg["tol"]))))
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--layers", default="roads,rails")
    a = ap.parse_args()
    for layer in a.layers.split(","):
        new = run(layer)
        if layer == "roads":
            old = json.load(open(os.path.join(ROOT, "tools", "cache", "roads_old_area.json")))["lines"]
        else:
            old = json.load(open(os.path.join(ROOT, "data", "osm", "rails.json")))["lines"] if os.path.exists(os.path.join(ROOT, "data", "osm", "rails.json")) else []
        out = fo.fit_size(layer, dict(lines=old + new), limit=9_000_000)
        path = os.path.join(ROOT, "data", "osm", layer + ".json")
        json.dump(out, open(path, "w"), separators=(",", ":"))
        print("[%s] old %d + new %d -> %d lines, %.1f MB" % (layer, len(old), len(new), len(out["lines"]), os.path.getsize(path) / 1e6), flush=True)


if __name__ == "__main__":
    main()
