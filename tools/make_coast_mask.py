#!/usr/bin/env python3
"""Build data/heightmap/region_coast.png + region_coast_meta.json — an EXACT, anti-aliased
land/sea mask rasterised from the OpenStreetMap land polygons (osmddata.openstreetmap.de).

Why: HeightField used to derive land/sea from the DEM's own ~300-450 m/pixel land mask and
smooth it with a cubic B-spline, so complex inlets (Poole Harbour) and islands (Brownsea) could
not be represented and the coast read as a staircase. This tool rasterises the real vector
coastline at ~126 m/pixel with anti-aliased edges and islands as holes.

Output: L8 PNG, 255 = land, 0 = sea, intermediate = smooth 1-2 px edge.
        meta json { width, height, lat_min, lat_max, lon_min, lon_max }.

Source, in order (cached in tools/cache/):
  1. https://osmdata.openstreetmap.de/download/land-polygons-split-4326.zip   (primary)
  2. https://osmdata.openstreetmap.de/download/land-polygons-complete-4326.zip
  3. scrape https://osmdata.openstreetmap.de/data/land-polygons.html for the current zip URL
Fallback if no download is possible: natural=coastline from a Geofabrik .osm.pbf, then
rasterising data/osm/coast.json + COAST_STRIPS polylines (see --from-json). Reported on stdout.

Usage:
  PYTHONPATH=F:/ww2_dlss/tools/cache/pylibs python3 tools/make_coast_mask.py
  python3 -m pip install --target tools/cache/pylibs pyshp     # once

OSM data (c) OpenStreetMap contributors, ODbL.
"""
import argparse
import json
import mmap
import os
import re
import struct
import sys
import time
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PNG = os.path.join(ROOT, "data", "heightmap", "region_coast.png")
OUT_META = os.path.join(ROOT, "data", "heightmap", "region_coast_meta.json")
CACHE = os.path.join(ROOT, "tools", "cache")
SHP_DIR = os.path.join(CACHE, "landpolys")
ZIP_PRIMARY = "land-polygons-split-4326.zip"
ZIP_SECOND = "land-polygons-complete-4326.zip"

LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0
BASE = "https://osmdata.openstreetmap.de/download/"
PAGE = "https://osmdata.openstreetmap.de/data/land-polygons.html"

# metres per degree (matches WorldCoords; used only for reporting/edge-width)
M_LON = 111320.0 * np.cos(np.radians(50.3))
M_LAT = 110540.0


# --------------------------------------------------------------- download
def _download(url, dest):
    import requests

    part = dest + ".part"
    have = os.path.getsize(part) if os.path.exists(part) else 0
    headers = {"Range": "bytes=%d-" % have} if have else {}
    r = requests.get(url, stream=True, timeout=60, headers=headers)
    if r.status_code == 416:                       # already complete
        os.replace(part, dest)
        return
    if r.status_code not in (200, 206):
        raise RuntimeError("HTTP %s for %s" % (r.status_code, url))
    mode = "ab" if (have and r.status_code == 206) else "wb"
    if mode == "wb":
        have = 0
    total = int(r.headers.get("Content-Length", 0)) + have
    got = have
    t0 = time.time()
    with open(part, mode) as f:
        for chunk in r.iter_content(1 << 20):
            f.write(chunk)
            got += len(chunk)
            if total and got % (64 << 20) < (1 << 20):
                print("   %5.1f%%  %d MB / %d MB" % (100.0 * got / total, got >> 20, total >> 20))
    os.replace(part, dest)
    print("   downloaded %s (%.1f MB in %.0fs)" % (os.path.basename(dest), os.path.getsize(dest) / 1e6, time.time() - t0))


def _scrape_urls():
    import requests
    try:
        html = requests.get(PAGE, timeout=30).text
    except Exception as e:  # noqa: BLE001
        print("   scrape failed:", e)
        return []
    return sorted(set(re.findall(r'href="([^"]*land-polygons[^"]*\.zip)"', html)))


def ensure_zip():
    """Return the local path of a land-polygons zip, downloading it if needed."""
    for name in (ZIP_PRIMARY, ZIP_SECOND):
        p = os.path.join(CACHE, name)
        if os.path.exists(p) and os.path.getsize(p) > 100 << 20:
            print("   have cache/%s" % name)
            return p
    urls = [BASE + ZIP_PRIMARY, BASE + ZIP_SECOND]
    for u in _scrape_urls():
        full = u if u.startswith("http") else BASE + u.lstrip("/")
        if full not in urls:
            urls.append(full)
    last = ""
    for u in urls:
        name = u.rsplit("/", 1)[-1]
        dest = os.path.join(CACHE, name)
        try:
            print("[dl] %s" % u)
            _download(u, dest)
            return dest
        except Exception as e:  # noqa: BLE001
            last = "%s: %s" % (type(e).__name__, e)
            print("   failed:", last)
    raise RuntimeError("could not download land polygons (%s)" % last)


def ensure_shapefile(zpath):
    """Extract land_polygons.{shp,shx,dbf} into CACHE/landpolys; return the .shp path."""
    shp = os.path.join(SHP_DIR, "land_polygons.shp")
    if os.path.exists(shp) and os.path.getsize(shp) > 100 << 20:
        return shp
    os.makedirs(SHP_DIR, exist_ok=True)
    with zipfile.ZipFile(zpath) as z:
        names = [n for n in z.namelist() if n.lower().endswith((".shp", ".shx", ".dbf", ".prj"))]
        if not any(n.lower().endswith(".shp") for n in names):
            raise RuntimeError("no .shp inside %s" % zpath)
        for n in names:
            out = os.path.join(SHP_DIR, os.path.basename(n))
            print("[unzip] %s -> %.1f MB" % (os.path.basename(n), z.getinfo(n).file_size / 1e6))
            with z.open(n) as src, open(out, "wb") as dst:
                while True:
                    b = src.read(1 << 20)
                    if not b:
                        break
                    dst.write(b)
    return shp


# --------------------------------------------------------------- shapefile scan
def scan_candidates(shp):
    """Fast pass over the .shp record headers; return record indices whose bbox intersects
    the playable area (grown a little for the dataset's grid overlap)."""
    with open(shp, "rb") as f:
        mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        size = len(mm)
        off = 100
        idx = 0
        out = []
        eps = 0.05
        while off + 44 <= size:
            hdr = mm[off:off + 44]
            reclen = struct.unpack(">i", hdr[4:8])[0] * 2
            st = struct.unpack("<i", hdr[8:12])[0]
            if st == 5:                                  # polygon
                xmin, ymin, xmax, ymax = struct.unpack("<4d", hdr[12:44])
                if xmax >= LON_MIN - eps and xmin <= LON_MAX + eps and ymax >= LAT_MIN - eps and ymin <= LAT_MAX + eps:
                    out.append(idx)
            off += 8 + reclen
            idx += 1
    return out


def shape_rings(shape):
    """Return a list of numpy (n,2) float64 arrays (x=lon, y=lat) — one per ring."""
    parts = list(shape.parts) + [len(shape.points)]
    pts = np.asarray(shape.points, dtype=np.float64)
    rings = []
    for i in range(len(parts) - 1):
        r = pts[parts[i]:parts[i + 1]]
        if len(r) >= 3:
            rings.append(r)
    return rings


def rasterize(shp, W, H, ss):
    """Anti-aliased land mask: supersample ss x, XOR each shape's rings (even-odd -> holes),
    OR across shapes. Returns a bool array of shape (H*ss, W*ss)."""
    import shapefile

    cand = scan_candidates(shp)
    print("[scan] %d candidate polygons in the playable area" % len(cand))
    r = shapefile.Reader(shp)
    TW, TH = W * ss, H * ss
    canvas = np.zeros((TH, TW), dtype=bool)
    sx = TW / (LON_MAX - LON_MIN)
    sy = TH / (LAT_MAX - LAT_MIN)
    done = 0
    for i in cand:
        rings = shape_rings(r.shape(i))
        if not rings:
            continue
        px = []
        xmin = ymin = 1e18
        xmax = ymax = -1e18
        for ring in rings:
            X = (ring[:, 0] - LON_MIN) * sx
            Y = (LAT_MAX - ring[:, 1]) * sy
            px.append(np.stack([X, Y], axis=1))
            xmin = min(xmin, X.min()); xmax = max(xmax, X.max())
            ymin = min(ymin, Y.min()); ymax = max(ymax, Y.max())
        ix0 = max(0, int(np.floor(xmin))); ix1 = min(TW, int(np.ceil(xmax)) + 1)
        iy0 = max(0, int(np.floor(ymin))); iy1 = min(TH, int(np.ceil(ymax)) + 1)
        sw, sh = ix1 - ix0, iy1 - iy0
        if sw <= 0 or sh <= 0:
            continue
        sub = np.zeros((sh, sw), dtype=bool)
        buf = None
        for P in px:
            tmp = Image.new("L", (sw, sh), 0)
            ImageDraw.Draw(tmp).polygon([(float(a - ix0), float(b - iy0)) for a, b in P], fill=255)
            buf = np.frombuffer(tmp.tobytes(), dtype=np.uint8).reshape(sh, sw)
            sub ^= buf > 0
        canvas[iy0:iy1, ix0:ix1] |= sub
        done += 1
        if done % 500 == 0:
            print("   %d/%d" % (done, len(cand)), flush=True)
    return canvas


# --------------------------------------------------------------- json fallback
def rings_from_coast_json():
    """Last-resort fallback: rasterise data/osm/coast.json line stubs as an implicit
    polygon (only meaningful if the caller accepts the deficiency)."""
    p = os.path.join(ROOT, "data", "osm", "coast.json")
    lines = []
    try:
        d = json.load(open(p))
        for ln in d.get("lines", []):
            pts = ln.get("pts", [])
            if len(pts) >= 2:
                lines.append(pts)
    except Exception as e:  # noqa: BLE001
        print("   coast.json unreadable:", e)
    return lines


# --------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=7680)
    ap.add_argument("--height", type=int, default=3616)
    ap.add_argument("--ss", type=int, default=2, help="supersample factor for anti-aliasing")
    ap.add_argument("--blur", type=float, default=0.7, help="final gaussian blur radius (px)")
    ap.add_argument("--from-json", action="store_true", help="skip the vector download, use data/osm/coast.json")
    a = ap.parse_args()

    W, H = a.width, a.height
    print("[out] %dx%d  (%.0f x %.0f m/px)" % (W, H, (LON_MAX - LON_MIN) * M_LON / W, (LAT_MAX - LAT_MIN) * M_LAT / H))

    fallback = ""
    if a.from_json:
        fallback = "data/osm/coast.json + COAST_STRIPS (deficient, England missing)"
        canvas = rasterize_json(W, H, a.ss)
    else:
        try:
            z = ensure_zip()
            shp = ensure_shapefile(z)
            canvas = rasterize(shp, W, H, a.ss)
        except Exception as e:  # noqa: BLE001
            print("[error] vector source failed (%s)" % e, file=sys.stderr)
            fallback = "data/osm/coast.json + COAST_STRIPS (deficient, England missing)"
            print("[fallback]", fallback)
            canvas = rasterize_json(W, H, a.ss)

    ss = a.ss
    down = canvas.reshape(H, ss, W, ss).sum(axis=(1, 3), dtype=np.float32) / float(ss * ss)
    img = Image.fromarray(np.round(np.clip(down, 0.0, 1.0) * 255.0).astype(np.uint8), "L")
    if a.blur > 0:
        img = img.filter(ImageFilter.GaussianBlur(a.blur))

    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    img.save(OUT_PNG, optimize=True)

    arr = np.asarray(img).astype(np.float32) / 255.0
    meta = dict(width=W, height=H, lat_min=LAT_MIN, lat_max=LAT_MAX, lon_min=LON_MIN, lon_max=LON_MAX,
                source="OSM land polygons (osmddata.openstreetmap.de land-polygons-split-4326), ODbL",
                land_fraction=round(float((arr > 0.5).mean()), 4),
                metres_per_px_x=round((LON_MAX - LON_MIN) * M_LON / W, 1),
                metres_per_px_y=round((LAT_MAX - LAT_MIN) * M_LAT / H, 1))
    if fallback:
        meta["source"] = "FALLBACK: " + fallback
        meta["fallback"] = fallback
    with open(OUT_META, "w") as f:
        json.dump(meta, f, indent=1)

    def s(lat, lon):
        x = int((lon - LON_MIN) / (LON_MAX - LON_MIN) * W)
        y = int((LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * H)
        return float(arr[y, x])

    print("[out] %s  %.2f MB" % (OUT_PNG, os.path.getsize(OUT_PNG) / 1e6))
    print("[meta] %s" % json.dumps(meta))
    checks = [("Poole Harbour (sea)", 50.695, -2.005, 0), ("Brownsea Is (land)", 50.690, -1.960, 1),
              ("Bournemouth (land)", 50.720, -1.870, 1), ("Dover (land)", 51.130, 1.320, 1),
              ("mid-Channel (sea)", 50.500, 0.500, 0), ("London (land)", 51.500, -0.120, 1),
              ("Isle of Wight (land)", 50.680, -1.300, 1), ("Poole Bay (sea)", 50.700, -1.750, 0)]
    ok = 0
    for name, lat, lon, want in checks:
        v = s(lat, lon)
        got = 1 if v >= 0.5 else 0
        flag = "ok " if got == want else "FAIL"
        if got == want:
            ok += 1
        print("[check] %-4s %-24s %6.3f m" % (flag, name, v))
    print("[check] %d/%d geography checks passed" % (ok, len(checks)))


def rasterize_json(W, H, ss):
    lines = rings_from_coast_json()
    TW, TH = W * ss, H * ss
    canvas = np.zeros((TH, TW), dtype=bool)
    if not lines:
        return canvas
    im = Image.new("L", (TW, TH), 0)
    dr = ImageDraw.Draw(im)
    for pts in lines:
        P = [((lon - LON_MIN) / (LON_MAX - LON_MIN) * TW, (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * TH) for lat, lon in pts]
        if len(P) >= 3:
            dr.polygon(P, fill=255)
    return np.frombuffer(im.tobytes(), dtype=np.uint8).reshape(TH, TW) > 0


if __name__ == "__main__":
    main()
