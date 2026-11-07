#!/usr/bin/env python3
"""Carve hand-placed harbours / inlets (data/desert/harbours.json) into the Desert coast mask as SEA.

Natural Earth 10 m land does not resolve Tobruk, Benghazi, Tripoli, Grand Harbour, Bizerte, Alexandria ... so the
mask reads them as land. Each harbour is a centreline of [lat, lon, half_width_m] points; it is rasterised as a
capsule chain (supersampled, anti-aliased) and the mask is lowered to min(mask, 255 - coverage). Only ever lowers
the mask, so the script is idempotent. Run:  python3 tools/make_harbours.py [--dry]
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data", "desert")
SS = 4


def main():
    meta = json.load(open(os.path.join(D, "region_coast_meta.json")))
    W, H = meta["width"], meta["height"]
    lat0, lat1, lon0, lon1 = meta["lat_max"], meta["lat_min"], meta["lon_min"], meta["lon_max"]
    img = Image.open(os.path.join(D, "region_coast.png")).convert("L")
    assert img.size == (W, H)
    mlat = 110540.0
    def to_px(lat, lon):
        return ((lon - lon0) / (lon1 - lon0) * W * SS, (lat0 - lat) / (lat0 - lat1) * H * SS)
    def rpx(m, lat):  # metres -> supersampled px (x, y)
        return (m / (111320.0 * np.cos(np.radians(lat))) / (lon1 - lon0) * W * SS,
                m / mlat / (lat0 - lat1) * H * SS)
    hs = json.load(open(os.path.join(D, "harbours.json")))["harbours"]
    # work on a bbox per harbour to keep memory small
    arr = np.array(img, dtype=np.float32)
    for h in hs:
        pts = h["line"]
        lats = [p[0] for p in pts]; lons = [p[1] for p in pts]
        pad = 0.08
        x0, y0 = to_px(max(lats) + pad, min(lons) - pad)
        x1, y1 = to_px(min(lats) - pad, max(lons) + pad)
        ix0, iy0 = max(int(x0 // SS), 0), max(int(y0 // SS), 0)
        ix1, iy1 = min(int(x1 // SS) + 1, W), min(int(y1 // SS) + 1, H)
        cov = Image.new("L", ((ix1 - ix0) * SS, (iy1 - iy0) * SS), 0)
        dr = ImageDraw.Draw(cov)
        def loc(p):
            x, y = to_px(p[0], p[1]); return (x - ix0 * SS, y - iy0 * SS)
        for a, b in zip(pts[:-1], pts[1:]):
            pa, pb = loc(a), loc(b)
            for t in np.linspace(0, 1, 24):   # capsule chain: circles along the segment, width interpolated
                lat = a[0] + (b[0] - a[0]) * t; lon = a[1] + (b[1] - a[1]) * t
                wm = a[2] + (b[2] - a[2]) * t
                cx, cy = loc((lat, lon)); rx, ry = rpx(wm, lat)
                dr.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
        cov = cov.resize((ix1 - ix0, iy1 - iy0), Image.BOX).filter(ImageFilter.GaussianBlur(0.5))
        c = np.array(cov, dtype=np.float32)
        sub = arr[iy0:iy1, ix0:ix1]
        new = np.minimum(sub, 255.0 - c)
        print("%-28s carved %6d px (%.1f km2)" % (h["name"], int(((sub - new) > 64).sum()),
              ((sub - new) > 64).sum() * 0.2975 * 0.2993))
        arr[iy0:iy1, ix0:ix1] = new
    if "--dry" in sys.argv:
        return
    Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "L").save(os.path.join(D, "region_coast.png"))
    print("wrote region_coast.png")
    # sea-side distance for the water shader (shallows -> deep): R8, 0 = land, 1..255 = 1 + metres_from_shore / SEA_MAX_M * 254
    from scipy import ndimage
    sea = arr < 127.5
    d = ndimage.distance_transform_edt(sea, sampling=(meta["metres_per_px_y"], meta["metres_per_px_x"]))
    SEA_MAX_M = 8000.0
    v = np.where(sea, 1.0 + np.clip(d / SEA_MAX_M, 0.0, 1.0) * 254.0, 0.0)
    im = Image.fromarray(np.round(v).astype(np.uint8), "L").resize((W // 2, H // 2), Image.BILINEAR)
    im.save(os.path.join(D, "region_seadist.png"))
    print("wrote region_seadist.png", im.size)


if __name__ == "__main__":
    main()
