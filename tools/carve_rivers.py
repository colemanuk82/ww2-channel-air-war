#!/usr/bin/env python3
"""Carve the real river network into data/heightmap/region_height.png (offline DEM pass).

Reads data/osm/rivers.json + data/heightmap/region_height.png + region_meta.json, backs the PRE-CARVE PNG up to
tools/cache/region_height_pre_rivers.png (once - the pristine DEM is never overwritten by a re-run), lowers the
DEM along each river polyline by a depth scaled by class (river deepest, stream shallowest), feathers the banks
so they read from 200-800 m up, and writes the PNG back.

Pipeline order: tools/fetch_osm.py (rivers) -> tools/make_heightmap.py -> **tools/carve_rivers.py** ->
tools/fetch_imagery.py / tools/make_urban_mask.py. Re-run the engine import afterwards
(HeightField reads the 16-bit PNG raw, but the .import sidecar must be refreshed).

In-engine fallback: RiverMesh.build_tile() drapes the ribbon on GroundKit.ground_y, so the game is fully playable
without running this tool - the rivers just sit on the un-carved ground instead of in a valley.

Usage: python tools/carve_rivers.py [--feather 1.6]
"""
import argparse
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEM_PATH = os.path.join(ROOT, "data", "heightmap", "region_height.png")
META_PATH = os.path.join(ROOT, "data", "heightmap", "region_meta.json")
RIVERS_PATH = os.path.join(ROOT, "data", "osm", "rivers.json")
CACHE_DIR = os.path.join(ROOT, "tools", "cache")
BACKUP_PATH = os.path.join(CACHE_DIR, "region_height_pre_rivers.png")

# Depth (metres) the channel is lowered, by waterway class: river deepest, stream shallowest.
DEPTHS = {"river": 8.0, "canal": 6.0, "stream": 3.0}
DEFAULT_DEPTH = 6.0
MIN_ELEV_M = 0.9          # never dig land below this (the ribbon skips raw_y < 0.4 world = 0.2 m)


def load_meta():
    with open(META_PATH, encoding="utf-8") as f:
        return json.load(f)


def to_px(lat, lon, meta):
    w, h = meta["width"], meta["height"]
    x = (lon - meta["lon_min"]) / (meta["lon_max"] - meta["lon_min"]) * (w - 1)
    y = (meta["lat_max"] - lat) / (meta["lat_max"] - meta["lat_min"]) * (h - 1)
    return x, y


def class_mask(lines, kind, meta):
    """255 along the polylines of one class, 0 elsewhere (drawn on a full-res 8-bit image)."""
    w, h = meta["width"], meta["height"]
    im = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(im)
    n = 0
    for ln in lines:
        if ln.get("k") != kind:
            continue
        pts = ln.get("pts", [])
        if len(pts) < 2:
            continue
        seq = []
        for la, lo in pts:
            x, y = to_px(la, lo, meta)
            if -2000.0 <= x <= w + 2000.0 and -2000.0 <= y <= h + 2000.0:
                seq.append((x, y))
        if len(seq) < 2:
            continue
        dr.line(seq, fill=255, width=1, joint="curve")
        n += 1
    return im, n


def norm_mask(im, feather_px):
    """Blur, then scale so the network core sits at 1.0 and the tails are cut, giving a feathered bank."""
    b = np.asarray(im.filter(ImageFilter.GaussianBlur(feather_px))).astype(np.float32) / 255.0
    nz = b[b > 0.02]
    if nz.size == 0:
        return None
    peak = float(np.percentile(nz, 99.0))
    if peak <= 0.0:
        return None
    w = np.clip((b - 0.08 * peak) / (0.92 * peak), 0.0, 1.0)
    return w


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--feather", type=float, default=1.6,
                    help="bank feather radius in DEM pixels (~300 m each at 3072x1500)")
    a = ap.parse_args()

    meta = load_meta()
    w, h = int(meta["width"]), int(meta["height"])
    max_elev = float(meta.get("max_elev_m", 1000.0))

    # 1) back up the pre-carve PNG FIRST (never clobber the pristine original on a re-run)
    os.makedirs(CACHE_DIR, exist_ok=True)
    if not os.path.exists(BACKUP_PATH):
        shutil.copy2(DEM_PATH, BACKUP_PATH)
        print(f"[backup] pre-carve DEM -> {os.path.relpath(BACKUP_PATH, ROOT)}")
    else:
        print(f"[backup] kept existing {os.path.relpath(BACKUP_PATH, ROOT)} (pre-carve original)")

    with open(RIVERS_PATH, encoding="utf-8") as f:
        lines = json.load(f).get("lines", [])

    arr = np.asarray(Image.open(DEM_PATH))
    if arr.dtype != np.uint16:
        print(f"ERROR: expected a 16-bit DEM, got {arr.dtype}", file=sys.stderr)
        return 1
    elev = arr.astype(np.float64) / 65535.0 * max_elev

    # 2) per-class feathered depression, combined with max()
    depression = np.zeros((h, w), np.float32)
    used = {}
    for kind, depth in DEPTHS.items():
        im, n = class_mask(lines, kind, meta)
        used[kind] = n
        m = norm_mask(im, a.feather) if n else None
        if m is not None:
            depression = np.maximum(depression, (m * depth).astype(np.float32))

    if not depression.any():
        print("ERROR: no river polylines fell inside the DEM bounds", file=sys.stderr)
        return 1

    # 3) carve only land, never below MIN_ELEV (sea cells are left untouched)
    land = elev > 0.0
    carved = elev.copy()
    carved[land] = np.maximum(elev[land] - depression[land], MIN_ELEV_M)
    delta = elev - carved

    km = 0.0
    for ln in lines:
        pts = ln.get("pts", [])
        for i in range(1, len(pts)):
            km += np.hypot((pts[i][0] - pts[i - 1][0]) * 110.5, (pts[i][1] - pts[i - 1][1]) * 71.0)

    changed = int((delta > 0.05).sum())
    print(f"[carve] classes drawn: {used}  feather {a.feather:.1f} px")
    print(f"[carve] {len(lines)} lines / {km:.0f} km; cells lowered {changed} ({100.0 * changed / (w * h):.2f}%), "
          f"max {delta.max():.1f} m, mean {delta[delta > 0.05].mean() if changed else 0.0:.1f} m")

    # 4) write the DEM back and note the carve in the meta "header"
    out = np.clip(carved / max_elev * 65535.0, 0, 65535).round().astype(np.uint16)
    Image.fromarray(out).save(DEM_PATH)
    meta["rivers_carved"] = True
    meta["rivers_carved_note"] = ("DEM lowered along data/osm/rivers.json by tools/carve_rivers.py "
                                  f"({len(lines)} lines / {km:.0f} km); pre-carve backup in tools/cache/region_height_pre_rivers.png")
    with open(META_PATH, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)

    # 5) sanity: same land/sea mask, Dover still land, Channel still sea (validate_data invariants)
    def sample(lat, lon):
        x, y = to_px(lat, lon, meta)
        xi, yi = int(x), int(y)
        return elev[yi, xi], carved[yi, xi]

    for name, lat, lon in (("Thames @ Greenwich", 51.49, 0.15), ("Seine @ Rouen", 49.44, 1.10),
                           ("Dover cliffs", 51.13, 1.35), ("mid-Channel", 50.5, 0.5)):
        before, after = sample(lat, lon)
        print(f"[check] {name:20s} {before:7.1f} m -> {after:7.1f} m")
    print(f"[out] wrote {os.path.relpath(DEM_PATH, ROOT)} ({os.path.getsize(DEM_PATH) / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
