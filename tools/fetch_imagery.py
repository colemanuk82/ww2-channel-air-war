#!/usr/bin/env python3
"""Fetch real imagery tiles and stitch an equirectangular north-up colour map for the terrain.

Output: data/heightmap/region_color.png (aligned to data/heightmap/region_meta.json bounds;
row 0 = north, column 0 = west, so the terrain shader can sample it by world XZ).

Sources (--source):
  eox   Sentinel-2 cloudless 2020 (CC-BY EOX)   tiles.maps.eox.at  {z}/{y}/{x}.jpg
  esri  ESRI World Imagery                       arcgisonline.com   {z}/{y}/{x}
  osm   OpenStreetMap carto                     tile.openstreetmap.org  {z}/{x}/{y}.png

Run from the project root:
  python tools/fetch_imagery.py [--source eox] [--zoom 10] [--width 4096] [--height 2048]
Tiles cache in tools/cache/imagery/<source>/<z>/. Delete that folder to refetch.
"""
import argparse
import json
import math
import os
import sys
import time

import numpy as np
import requests
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = os.path.join(ROOT, "data", "heightmap", "region_meta.json")
OUT = os.path.join(ROOT, "data", "heightmap", "region_color.png")
CACHE = os.path.join(ROOT, "tools", "cache", "imagery")

SOURCES = {
    "eox": ("https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2020_3857/default/g/{z}/{y}/{x}.jpg", "jpg"),
    "esri": ("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", "jpg"),
    "osm": ("https://tile.openstreetmap.org/{z}/{x}/{y}.png", "png"),
}
HEADERS = {"User-Agent": "ww2-channel-air-war/0.1 (terrain imagery fetch)"}


def deg2tile_px(lat, lon, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n * 256.0
    lat_r = math.radians(lat)
    y = (1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n * 256.0
    return x, y


def fetch_tile(session, source, z, x, y):
    tmpl, ext = SOURCES[source]
    d = os.path.join(CACHE, source, str(z))
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "%d_%d.%s" % (x, y, ext))
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    url = tmpl.format(z=z, x=x, y=y)
    for attempt in range(4):
        try:
            r = session.get(url, headers=HEADERS, timeout=25)
            if r.status_code == 200 and r.content:
                with open(path, "wb") as f:
                    f.write(r.content)
                time.sleep(0.05)
                return path
            if r.status_code in (400, 404):
                return None
        except Exception:
            pass
        time.sleep(0.5 * (attempt + 1))
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default="eox", choices=list(SOURCES))
    ap.add_argument("--zoom", type=int, default=10)
    ap.add_argument("--width", type=int, default=6144)
    ap.add_argument("--height", type=int, default=3000)
    args = ap.parse_args()

    meta = json.load(open(META, "r"))
    lon_min, lon_max = float(meta["lon_min"]), float(meta["lon_max"])
    lat_min, lat_max = float(meta["lat_min"]), float(meta["lat_max"])
    z = args.zoom

    x0f, y0f = deg2tile_px(lat_max, lon_min, z)   # north-west corner
    x1f, y1f = deg2tile_px(lat_min, lon_max, z)   # south-east corner
    X0, X1 = int(math.floor(x0f / 256.0)), int(math.floor(x1f / 256.0))
    Y0, Y1 = int(math.floor(y0f / 256.0)), int(math.floor(y1f / 256.0))
    nx, ny = X1 - X0 + 1, Y1 - Y0 + 1
    print("source=%s zoom=%d tiles=%dx%d (%d)" % (args.source, z, nx, ny, nx * ny))

    mosaic = Image.new("RGB", (nx * 256, ny * 256), (24, 34, 44))
    session = requests.Session()
    got = 0
    for ty in range(Y0, Y1 + 1):
        for tx in range(X0, X1 + 1):
            p = fetch_tile(session, args.source, z, tx, ty)
            if p is None:
                continue
            try:
                im = Image.open(p).convert("RGB")
            except Exception:
                continue
            mosaic.paste(im, ((tx - X0) * 256, (ty - Y0) * 256))
            got += 1
    print("loaded tiles:", got, "/", nx * ny)
    if got == 0:
        print("ERROR: no tiles fetched (offline?)", file=sys.stderr)
        sys.exit(2)

    M = np.asarray(mosaic).astype(np.float32)
    H, W = args.height, args.width
    lons = lon_min + (np.arange(W, dtype=np.float64) + 0.5) / W * (lon_max - lon_min)
    lats = lat_max - (np.arange(H, dtype=np.float64) + 0.5) / H * (lat_max - lat_min)
    n = 2.0 ** z
    gx = (lons + 180.0) / 360.0 * n * 256.0
    lat_r = np.radians(lats)
    gy = (1.0 - np.log(np.tan(lat_r) + 1.0 / np.cos(lat_r)) / math.pi) / 2.0 * n * 256.0
    px = np.clip(gx - X0 * 256.0, 0.0, M.shape[1] - 1.001)
    py = np.clip(gy - Y0 * 256.0, 0.0, M.shape[0] - 1.001)
    x0i = np.floor(px).astype(np.int32)
    y0i = np.floor(py).astype(np.int32)
    x1i = np.clip(x0i + 1, 0, M.shape[1] - 1)
    y1i = np.clip(y0i + 1, 0, M.shape[0] - 1)
    fx = (px - x0i)[None, :, None]
    fy = (py - y0i)[:, None, None]
    a = M[y0i][:, x0i]
    b = M[y0i][:, x1i]
    c = M[y1i][:, x0i]
    d = M[y1i][:, x1i]
    top = a + (b - a) * fx
    bot = c + (d - c) * fx
    out = np.clip(top + (bot - top) * fy, 0.0, 255.0).astype(np.uint8)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(out).save(OUT)
    print("wrote", OUT, out.shape)


if __name__ == "__main__":
    main()
