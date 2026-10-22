#!/usr/bin/env python3
"""Download ESA WorldCover 10 m land cover for the game area and export a compact class grid.

Reads only the needed window from the public COGs on S3 (HTTP range requests, no multi-GB download)
and resamples to an equirectangular grid matching data/heightmap/region_meta.json.

Outputs:
  data/heightmap/region_landcover.bin   raw bytes, row-major from the NW corner, one class per cell
  data/heightmap/region_landcover.json  {width,height,lat_min,lat_max,lon_min,lon_max,classes{...}}
  data/heightmap/region_landcover.png   debug view (grayscale class values)

WorldCover v200 classes (https://esa-worldcover.org): 10 tree, 20 shrub, 30 grass, 40 crop,
50 built-up, 60 bare, 70 snow, 80 water, 90 wetland, 95 mangrove, 100 moss.

Run from the project root:  python tools/fetch_landcover.py [--width 2048] [--height 1024] [--year 2021]
"""
import argparse
import json
import math
import os
import sys

import numpy as np
import rasterio
from rasterio.enums import Resampling
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = os.path.join(ROOT, "data", "heightmap", "region_meta.json")
BIN = os.path.join(ROOT, "data", "heightmap", "region_landcover.bin")
JSN = os.path.join(ROOT, "data", "heightmap", "region_landcover.json")
PNG = os.path.join(ROOT, "data", "heightmap", "region_landcover.png")
BASE = "https://esa-worldcover.s3.eu-central-1.amazonaws.com"

CLASSES = {
    10: "tree", 20: "shrub", 30: "grass", 40: "crop", 50: "built",
    60: "bare", 70: "snow", 80: "water", 90: "wetland", 95: "mangrove", 100: "moss",
}


def tile_key(year, lat0, lon0):
    ns = "N%02d" % lat0 if lat0 >= 0 else "S%02d" % (-lat0)
    ew = "E%03d" % lon0 if lon0 >= 0 else "W%03d" % (-lon0)
    return "v200/%d/map/ESA_WorldCover_10m_%d_v200_%s%s_Map.tif" % (year, year, ns, ew)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--year", type=int, default=2021)
    ap.add_argument("--width", type=int, default=3072)
    ap.add_argument("--height", type=int, default=1500)
    args = ap.parse_args()

    meta = json.load(open(META))
    lon_min, lon_max = meta["lon_min"], meta["lon_max"]
    lat_min, lat_max = meta["lat_min"], meta["lat_max"]
    W, H = args.width, args.height
    out = np.zeros((H, W), np.uint8)

    lat0 = int(math.floor(lat_min / 3.0) * 3)
    lon0 = int(math.floor(lon_min / 3.0) * 3)
    tiles = []
    la = lat0
    while la < lat_max:
        lo = lon0
        while lo < lon_max:
            tiles.append((la, lo))
            lo += 3
        la += 3

    filled = 0
    for (la, lo) in tiles:
        key = tile_key(args.year, la, lo)
        url = "%s/%s" % (BASE, key)
        vsi = "/vsicurl/" + url
        try:
            src = rasterio.open(vsi)
        except Exception as ex:
            sys.stderr.write("skip %s (%s)\n" % (key, repr(ex)[:90]))
            continue
        b = src.bounds
        left = max(b.left, lon_min)
        right = min(b.right, lon_max)
        top = min(b.top, lat_max)
        bottom = max(b.bottom, lat_min)
        if left >= right or bottom >= top:
            src.close()
            continue
        col0 = int(round((left - lon_min) / (lon_max - lon_min) * W))
        col1 = int(round((right - lon_min) / (lon_max - lon_min) * W))
        row0 = int(round((lat_max - top) / (lat_max - lat_min) * H))
        row1 = int(round((lat_max - bottom) / (lat_max - lat_min) * H))
        col0, col1 = max(0, col0), min(W, col1)
        row0, row1 = max(0, row0), min(H, row1)
        ow, oh = col1 - col0, row1 - row0
        if ow <= 0 or oh <= 0:
            src.close()
            continue
        win = src.window(left, bottom, right, top)
        data = src.read(1, window=win, out_shape=(oh, ow), resampling=Resampling.nearest,
                        boundless=True, fill_value=0)
        out[row0:row1, col0:col1] = data
        filled += 1
        src.close()
        print("  %s -> rows %d:%d cols %d:%d" % (key, row0, row1, col0, col1))

    if filled == 0:
        print("ERROR: no WorldCover tiles read", file=sys.stderr)
        sys.exit(2)

    out.tofile(BIN)
    json.dump({
        "width": W, "height": H,
        "lat_min": lat_min, "lat_max": lat_max, "lon_min": lon_min, "lon_max": lon_max,
        "year": args.year, "source": "ESA WorldCover 10m v200 (CC-BY 4.0)",
        "classes": {str(k): v for k, v in CLASSES.items()},
    }, open(JSN, "w"), indent=1)
    Image.fromarray(out, mode="L").save(PNG)

    vals, counts = np.unique(out, return_counts=True)
    hist = {CLASSES.get(int(v), str(int(v))): int(c) for v, c in zip(vals, counts)}
    print("wrote", BIN, "tiles:", filled, "histogram:", hist)


if __name__ == "__main__":
    main()
