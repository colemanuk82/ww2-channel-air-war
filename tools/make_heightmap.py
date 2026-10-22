#!/usr/bin/env python3
"""Build data/heightmap/region_height.png (16-bit, 65535 = 1000 m, sea = 0) + region_meta.json.

Sources, in order:
  1. AWS Terrain Tiles 'terrarium' (https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png)
  2. The same terrarium set through the virtual-host URL (elevation-tiles-prod.s3.amazonaws.com).
  3. Procedural fallback: hand-authored coastline polygon + fBm noise + chalk cliffs (offline).

Usage: python tools/make_heightmap.py [--force-procedural] [--zoom 9] [--width 2048] [--height 1024]
"""
import argparse
import io
import json
import math
import os
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "data", "heightmap")
CACHE_DIR = os.path.join(ROOT, "tools", "cache", "terrarium")
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0
MAX_ELEV = 1000.0

HOSTS = [
    "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png",
    "https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{z}/{x}/{y}.png",
]


# ---------------------------------------------------------------- DEM download
def merc_px(lat, lon, z):
    n = 256.0 * (2 ** z)
    x = (lon + 180.0) / 360.0 * n
    s = np.sin(np.radians(lat))
    y = (0.5 - np.log((1 + s) / (1 - s)) / (4 * np.pi)) * n
    return x, y


def fetch_tile(z, x, y):
    import requests
    path = os.path.join(CACHE_DIR, f"{z}_{x}_{y}.png")
    if os.path.exists(path) and os.path.getsize(path) > 100:
        return Image.open(path).convert("RGB")
    last = None
    for host in HOSTS:
        url = host.format(z=z, x=x, y=y)
        for attempt in range(3):
            try:
                r = requests.get(url, timeout=30)
                if r.status_code == 200:
                    os.makedirs(CACHE_DIR, exist_ok=True)
                    with open(path, "wb") as f:
                        f.write(r.content)
                    return Image.open(io.BytesIO(r.content)).convert("RGB")
                last = f"HTTP {r.status_code} {url}"
            except Exception as e:  # noqa: BLE001
                last = f"{type(e).__name__}: {e}"
    raise RuntimeError(last)


def build_from_dem(zoom, W, H):
    x0f, y0f = merc_px(LAT_MAX, LON_MIN, zoom)  # top-left
    x1f, y1f = merc_px(LAT_MIN, LON_MAX, zoom)  # bottom-right
    tx0, tx1 = int(x0f // 256), int((x1f - 1e-6) // 256)
    ty0, ty1 = int(y0f // 256), int((y1f - 1e-6) // 256)
    tiles = [(tx, ty) for ty in range(ty0, ty1 + 1) for tx in range(tx0, tx1 + 1)]
    print(f"[dem] zoom {zoom}: {len(tiles)} tiles ({tx1 - tx0 + 1} x {ty1 - ty0 + 1})")
    with ThreadPoolExecutor(8) as ex:
        imgs = list(ex.map(lambda t: fetch_tile(zoom, t[0], t[1]), tiles))
    mosaic = np.zeros(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256), dtype=np.float32)
    for (tx, ty), im in zip(tiles, imgs):
        a = np.asarray(im).astype(np.float32)
        h = a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0
        mosaic[(ty - ty0) * 256:(ty - ty0 + 1) * 256, (tx - tx0) * 256:(tx - tx0 + 1) * 256] = h
    # resample (equirectangular output) with 2x supersampling
    S = 2
    lats = LAT_MAX - (np.arange(H * S) + 0.5) / (H * S) * (LAT_MAX - LAT_MIN)
    lons = LON_MIN + (np.arange(W * S) + 0.5) / (W * S) * (LON_MAX - LON_MIN)
    _, py = merc_px(lats, np.zeros_like(lats), zoom)
    px, _ = merc_px(np.zeros_like(lons), lons, zoom)
    py = py - ty0 * 256 - 0.5
    px = px - tx0 * 256 - 0.5
    iy = np.clip(np.floor(py).astype(int), 0, mosaic.shape[0] - 2)
    ix = np.clip(np.floor(px).astype(int), 0, mosaic.shape[1] - 2)
    fy = np.clip(py - iy, 0, 1)[:, None]
    fx = np.clip(px - ix, 0, 1)[None, :]
    a = mosaic[iy][:, ix]
    b = mosaic[iy][:, ix + 1]
    c = mosaic[iy + 1][:, ix]
    d = mosaic[iy + 1][:, ix + 1]
    hi = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    hi = np.maximum(hi, 0.0)  # clamp sea / below-zero to 0
    lo = hi.reshape(H, S, W, S).mean(axis=(1, 3))
    return lo


# ------------------------------------------------------- procedural fallback
# polygons are (lat, lon) rings
ENGLAND = [
    (51.7, -2.55), (51.50, -2.65), (51.35, -2.98), (51.24, -3.0), (51.21, -3.47), (51.21, -4.12),
    (51.10, -4.55), (51.0, -4.6), (50.33, -4.6), (50.33, -4.15), (50.22, -3.64), (50.46, -3.5),
    (50.62, -3.4), (50.72, -2.95), (50.62, -2.45), (50.60, -1.95), (50.68, -1.95), (50.71, -1.55),
    (50.80, -1.30), (50.78, -1.05), (50.72, -0.79), (50.80, -0.54), (50.82, -0.14), (50.78, 0.05),
    (50.745, 0.15), (50.73, 0.24), (50.77, 0.29), (50.85, 0.57), (50.92, 0.77), (50.915, 0.975),
    (51.07, 1.08), (51.08, 1.19), (51.12, 1.36), (51.14, 1.40), (51.22, 1.42), (51.30, 1.38),
    (51.33, 1.43), (51.38, 1.45), (51.39, 1.38), (51.37, 1.13), (51.36, 1.02), (51.40, 0.9),
    (51.44, 0.7), (51.52, 0.72), (51.60, 0.95), (51.7, 1.1),
]
WALES = [(51.7, -4.6), (51.7, -2.7), (51.55, -2.75), (51.50, -3.2), (51.40, -3.40), (51.46, -3.7),
         (51.60, -3.95), (51.55, -4.25), (51.65, -4.4)]
WIGHT = [(50.58, -1.58), (50.66, -1.30), (50.74, -1.20), (50.72, -1.05), (50.60, -1.10), (50.57, -1.30)]
FRANCE = [
    (48.9, -1.57), (49.0, -1.60), (49.2, -1.62), (49.37, -1.79), (49.55, -1.86), (49.72, -1.95),
    (49.70, -1.78), (49.67, -1.62), (49.70, -1.26), (49.42, -1.18), (49.35, -1.15), (49.39, -1.05),
    (49.37, -0.85), (49.35, -0.75), (49.34, -0.62), (49.33, -0.46), (49.29, -0.25), (49.29, -0.11),
    (49.36, 0.07), (49.42, 0.23), (49.44, 0.28), (49.47, 0.30), (49.49, 0.17), (49.49, 0.11),
    (49.50, 0.10), (49.69, 0.16), (49.76, 0.37), (49.93, 1.08), (50.06, 1.37), (50.19, 1.50),
    (50.23, 1.58), (50.40, 1.55), (50.52, 1.58), (50.73, 1.59), (50.87, 1.58), (50.89, 1.66),
    (50.92, 1.71), (50.97, 1.85), (51.0, 2.1), (51.05, 2.37), (51.15, 2.72), (51.23, 2.92),
    (51.33, 3.2), (51.35, 3.37), (51.38, 3.45), (51.57, 3.45), (51.7, 3.6), (51.7, 4.7), (48.9, 4.7),
]
# coast stretches with high chalk/limestone cliffs: (polyline, cliff height m, inland reach km)
CLIFFS = [
    ([(51.07, 1.12), (51.08, 1.19), (51.12, 1.36), (51.14, 1.40), (51.22, 1.42)], 105, 2.0),   # Dover
    ([(50.77, 0.05), (50.745, 0.15), (50.73, 0.24)], 150, 1.8),                                  # Seven Sisters
    ([(50.87, 1.58), (50.89, 1.66), (50.92, 1.71)], 130, 1.5),                                   # Gris/Blanc-Nez
    ([(49.69, 0.16), (49.76, 0.37), (49.93, 1.08), (50.06, 1.37)], 95, 2.5),                     # Alabaster coast
    ([(49.34, -0.62), (49.37, -0.85)], 40, 1.0),                                                 # Longues/Hoc
    ([(49.396, -0.99), (49.40, -0.97)], 30, 0.8),
]
# broad uplands: (lat, lon, radius_km, height_m)
HILLS = [
    (50.60, -3.90, 35, 380), (50.35, -4.50, 30, 180), (51.10, -3.60, 30, 250),    # Dartmoor, Cornwall, Exmoor
    (50.93, -0.60, 45, 160), (50.90, 0.05, 30, 120),                              # South Downs
    (51.28, 0.50, 55, 150), (51.25, -0.30, 35, 140),                              # North Downs
    (51.0, -1.4, 40, 80), (51.15, -2.7, 40, 90),
    (49.0, 4.0, 50, 200), (49.95, 4.60, 45, 330), (50.15, 4.65, 30, 280),         # Champagne, Ardennes
    (49.1, -1.0, 50, 150), (48.95, -0.4, 40, 180), (49.2, 0.9, 50, 130),          # Bocage, Pays d'Auge
    (50.35, 2.5, 40, 130), (50.75, 2.55, 15, 120), (50.70, 2.0, 25, 190),         # Artois, Mont Cassel, Boulonnais
    (50.40, 1.9, 40, 110), (49.7, 1.5, 50, 140), (49.80, 2.9, 40, 110),
    (50.8, 3.6, 25, 100), (50.55, 4.2, 35, 120),
]


def value_noise(H, W, cells, rng):
    g = rng.random((cells + 2, int(cells * W / H) + 2)).astype(np.float32)
    im = Image.fromarray(g, mode="F").resize((W, H), Image.BICUBIC)
    return np.asarray(im)


def fbm(H, W, rng, octaves=6, base=4):
    out = np.zeros((H, W), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * value_noise(H, W, base * 2 ** o, rng)
        tot += amp
        amp *= 0.5
    return out / tot


def build_procedural(W, H, seed=1944):
    rng = np.random.default_rng(seed)
    sx = lambda lon: (lon - LON_MIN) / (LON_MAX - LON_MIN) * W
    sy = lambda lat: (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * H
    ring = lambda pts: [(sx(lo), sy(la)) for la, lo in pts]
    img = Image.new("L", (W * 2, H * 2), 0)
    dr = ImageDraw.Draw(img)
    for poly in (ENGLAND, WALES, WIGHT, FRANCE):
        dr.polygon([(x * 2, y * 2) for x, y in ring(poly)], fill=255)
    land = np.asarray(img.resize((W, H), Image.BOX)).astype(np.float32) / 255.0
    # distance-from-coast proxy: blurred land mask
    km_px = 111.32 * math.cos(math.radians(50.3)) * (LON_MAX - LON_MIN) / W  # km per pixel (x)
    def blur_km(arr, km):
        im = Image.fromarray((arr * 255).astype(np.uint8))
        return np.asarray(im.filter(ImageFilter.GaussianBlur(km / km_px))).astype(np.float32) / 255.0
    inland = np.clip((blur_km(land, 12.0) - 0.5) * 2.0, 0, 1)
    # hills
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lat = LAT_MAX - (yy + 0.5) / H * (LAT_MAX - LAT_MIN)
    lon = LON_MIN + (xx + 0.5) / W * (LON_MAX - LON_MIN)
    elev = np.zeros((H, W), np.float32)
    n_big = fbm(H, W, rng, 6, 5)
    for hlat, hlon, rkm, hm in HILLS:
        dy = (lat - hlat) * 110.54
        dx = (lon - hlon) * 111.32 * math.cos(math.radians(hlat))
        d2 = (dx * dx + dy * dy) / (rkm * rkm)
        elev += hm * np.exp(-d2 * 1.5) * (0.55 + 0.9 * n_big)
    # general rolling terrain
    rolling = 15 + 85 * fbm(H, W, rng, 7, 6) ** 1.5
    elev = (elev + rolling * (0.3 + 0.7 * inland)) * land
    elev = np.maximum(elev, 6.0 * land)
    # chalk cliffs: strong rise within reach of the cliff segments, hard drop at the sea edge
    cl = Image.new("L", (W, H), 0)  # cliff heights (<=255 m) drawn as 8-bit
    cd = ImageDraw.Draw(cl)
    for pts, hm, reach in CLIFFS:
        wpx = max(2, int(reach / km_px * 2))
        cd.line(ring(pts), fill=hm, width=wpx)
    clf = np.asarray(cl.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32)
    clf = clf *(0.85 + 0.3 * fbm(H, W, rng, 4, 8))
    elev = np.where(land > 0.5, np.maximum(elev, clf), elev)
    elev *= (land > 0.5)
    return np.clip(elev, 0, MAX_ELEV)


# ------------------------------------------------------------------ output
def sample(h, lat, lon):
    H, W = h.shape
    x = int((lon - LON_MIN) / (LON_MAX - LON_MIN) * W)
    y = int((LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * H)
    return float(h[y, x])


def write_outputs(elev, source, W, H):
    os.makedirs(OUT_DIR, exist_ok=True)
    v = np.clip(elev / MAX_ELEV * 65535.0, 0, 65535).round().astype(np.uint16)
    Image.fromarray(v).save(os.path.join(OUT_DIR, "region_height.png"))
    meta = dict(width=W, height=H, lat_min=LAT_MIN, lat_max=LAT_MAX, lon_min=LON_MIN, lon_max=LON_MAX,
                max_elev_m=1000, sea_level_value=0, source=source)
    with open(os.path.join(OUT_DIR, "region_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print(f"[out] {W}x{H}  min {elev.min():.1f} m  max {elev.max():.1f} m  land {(elev > 0).mean() * 100:.1f}%")
    print(f"[check] Dover cliffs (51.13,1.35): {sample(elev, 51.13, 1.35):.0f} m")
    print(f"[check] mid-Channel (50.5,0.5):    {sample(elev, 50.5, 0.5):.0f} m")
    print(f"[check] Ardennes (50.1,4.6):       {sample(elev, 50.1, 4.6):.0f} m")
    print(f"[check] London (51.5,-0.12):       {sample(elev, 51.5, -0.12):.0f} m")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force-procedural", action="store_true")
    ap.add_argument("--zoom", type=int, default=9)
    ap.add_argument("--width", type=int, default=3072)
    ap.add_argument("--height", type=int, default=1500)
    a = ap.parse_args()
    elev, source = None, None
    if not a.force_procedural:
        try:
            elev = build_from_dem(a.zoom, a.width, a.height)
            source = f"AWS terrain tiles (terrarium) z{a.zoom}"
        except Exception as e:  # noqa: BLE001
            print(f"[dem] failed ({e}); using procedural fallback", file=sys.stderr)
    if elev is None:
        elev = build_procedural(a.width, a.height)
        source = "PROCEDURAL FALLBACK (hand-authored coastline + noise)"
    print("[source]", source)
    write_outputs(elev, source, a.width, a.height)


if __name__ == "__main__":
    main()
