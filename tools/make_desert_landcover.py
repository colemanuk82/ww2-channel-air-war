#!/usr/bin/env python3
"""Build the desert map's land-cover grid and urban mask (derived data, no satellite classification available).

Outputs (data/desert/):
  region_landcover.bin   raw bytes, row-major from the NW corner, one class id per cell   (format of scripts/land_cover.gd)
  region_landcover.json  {width,height,lat_min,lat_max,lon_min,lon_max,source,classes{...}}
  region_urban.png       8-bit grey town mask, soft edged (threshold ~0.5 = the town outline); same grid as the land cover
                         (--urban-scale 2 doubles it like the Channel one; 1 is plenty here, the towns are small)
  ../../build/desert_landcover_preview.png   colour preview (hillshade + classes)

Inputs: data/desert/region_height.png (+ region_meta.json max_elev_m), region_coast.png, osm/towns.json,
  locations.json (cities), landcover_zones.json (curated polygons / corridors / circles, oases, urban radii).
Derived layers: slope, curvature (relief against a 1.5 km blur), D8 drainage accumulation (at 1/4 resolution),
  distance to sea, a latitude/continentality/orography "wetness" index, seeded value noise for patchiness.

Class ids reuse ESA WorldCover numbers where the meaning is the same (so every existing LandCover consumer keeps working
and simply ignores ids it does not know):
  0 sea / no data   10 tree (real woodland only: Kroumirie, Anatolian pine)   20 shrub / maquis / steppe scrub
  30 grass (alfa steppe)   40 crop   50 built-up   60 bare (open sandy desert floor)   80 water   90 wetland
New desert ids (>= 110, not used by WorldCover):
  110 coastal sand   111 sabkha (coastal salt flat)   112 hamada (limestone / stony plateau)   113 reg (dark gravel plain)
  114 rock (escarpment, cliff, jebel)   115 erg (dune sand)   116 salt pan (chott / Qattara crust)   117 wadi bed
  118 limestone (Malta / Hyblaean honey stone)   119 basalt / volcanic (Pantelleria)   120 oasis (palm grove, irrigated)
  121 orchard (olive, citrus, almond)

Run from the project root:  python3 tools/make_desert_landcover.py [--width 7000] [--seed 7] [--urban-scale 1]
Deterministic for a given seed. Needs numpy + Pillow only."""
import argparse
import json
import math
import os
import sys
import time
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data", "desert")

CLASSES = {
    0: "sea", 10: "tree", 20: "shrub", 30: "grass", 40: "crop", 50: "built", 60: "bare", 80: "water", 90: "wetland",
    110: "coastal_sand", 111: "sabkha", 112: "hamada", 113: "reg", 114: "rock", 115: "erg", 116: "salt_pan",
    117: "wadi", 118: "limestone", 119: "basalt", 120: "oasis", 121: "orchard",
}
NAME2ID = {v: k for k, v in CLASSES.items()}
PREVIEW_RGB = {
    0: (40, 80, 120), 10: (40, 80, 40), 20: (110, 120, 70), 30: (150, 150, 90), 40: (120, 170, 70), 50: (230, 60, 60),
    60: (214, 188, 140), 80: (60, 120, 200), 90: (70, 150, 130), 110: (240, 228, 190), 111: (225, 215, 200),
    112: (205, 195, 170), 113: (110, 90, 75), 114: (140, 110, 90), 115: (235, 175, 90), 116: (250, 250, 250),
    117: (160, 120, 80), 118: (230, 200, 130), 119: (50, 45, 45), 120: (20, 200, 60), 121: (90, 140, 60),
}


def log(*a):
    print("[%6.1fs]" % (time.time() - T0), *a, flush=True)


T0 = time.time()


# ---------------------------------------------------------------- helpers
class Grid:
    def __init__(self, meta, width):
        self.lat_min, self.lat_max = meta["lat_min"], meta["lat_max"]
        self.lon_min, self.lon_max = meta["lon_min"], meta["lon_max"]
        self.W = int(width)
        self.H = int(round(width * meta["height"] / meta["width"]))
        self.dlat = (self.lat_max - self.lat_min) / self.H
        self.dlon = (self.lon_max - self.lon_min) / self.W
        lat_mid = 0.5 * (self.lat_min + self.lat_max)
        self.kx = self.dlon * 111.32 * math.cos(math.radians(lat_mid))   # km per px (x), at mid latitude
        self.ky = self.dlat * 110.57

    def rc(self, lat, lon):
        return ((self.lat_max - lat) / (self.lat_max - self.lat_min) * self.H,
                (lon - self.lon_min) / (self.lon_max - self.lon_min) * self.W)

    def inside(self, lat, lon):
        return self.lat_min <= lat <= self.lat_max and self.lon_min <= lon <= self.lon_max

    def lat_rows(self):
        return self.lat_max - (np.arange(self.H, dtype=np.float32) + 0.5) * self.dlat

    def lon_cols(self):
        return self.lon_min + (np.arange(self.W, dtype=np.float32) + 0.5) * self.dlon


def resize_f(a, w, h, method=Image.BILINEAR):
    return np.asarray(Image.fromarray(a.astype(np.float32), mode="F").resize((w, h), method), dtype=np.float32)


def vnoise(shape, cell, seed, octaves=1):
    """Smooth value noise in [0,1] (uniformised), lattice spacing `cell` px."""
    h, w = shape
    rng = np.random.default_rng(seed)
    acc = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = max(cell / (2 ** o), 2.0)
        lat = rng.random((int(h / c) + 3, int(w / c) + 3)).astype(np.float32)
        acc += amp * resize_f(lat, w, h, Image.BICUBIC)
        tot += amp
        amp *= 0.5
    acc /= tot
    flat = acc.ravel()
    sub = flat[:: max(1, flat.size // 200000)]
    q = np.quantile(sub, np.linspace(0, 1, 257))
    return np.interp(acc, q, np.linspace(0, 1, 257)).astype(np.float32)


def chamfer(sea, iters, cx, cy):
    """Distance (km) from every cell to the nearest True cell of `sea`, up to roughly iters cells; 1e9 beyond."""
    d = np.where(sea, 0.0, 1e9).astype(np.float32)
    cd = math.hypot(cx, cy)
    for it in range(iters):
        nd = d.copy()
        np.minimum(nd[:, 1:], d[:, :-1] + cx, out=nd[:, 1:])
        np.minimum(nd[:, :-1], d[:, 1:] + cx, out=nd[:, :-1])
        np.minimum(nd[1:, :], d[:-1, :] + cy, out=nd[1:, :])
        np.minimum(nd[:-1, :], d[1:, :] + cy, out=nd[:-1, :])
        np.minimum(nd[1:, 1:], d[:-1, :-1] + cd, out=nd[1:, 1:])
        np.minimum(nd[1:, :-1], d[:-1, 1:] + cd, out=nd[1:, :-1])
        np.minimum(nd[:-1, 1:], d[1:, :-1] + cd, out=nd[:-1, 1:])
        np.minimum(nd[:-1, :-1], d[1:, 1:] + cd, out=nd[:-1, :-1])
        if np.array_equal(nd, d):
            break
        d = nd
    return d


def flow_accumulation(elev, sea):
    """D8 steepest-descent flow accumulation (cells) on a coarse grid. Pits keep their flow (endorheic basins)."""
    h, w = elev.shape
    rng = np.random.default_rng(3)
    e = elev.astype(np.float64) + rng.random(elev.shape) * 0.05
    e[sea] = -50.0
    pad = np.pad(e, 1, constant_values=np.inf)
    best = np.zeros(e.shape)
    bdir = np.full(e.shape, -1, np.int64)
    offs = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    idx = np.arange(h * w).reshape(h, w)
    recv = idx.copy()
    for oy, ox in offs:
        nb = pad[1 + oy:1 + oy + h, 1 + ox:1 + ox + w]
        drop = (e - nb) / (1.414 if oy and ox else 1.0)
        better = drop > best
        best = np.where(better, drop, best)
        nbidx = np.clip(np.arange(h)[:, None] + oy, 0, h - 1) * w + np.clip(np.arange(w)[None, :] + ox, 0, w - 1)
        recv = np.where(better, nbidx, recv)
    order = np.argsort(-e.ravel(), kind="stable").tolist()
    rl = recv.ravel().tolist()
    acc = [1.0] * (h * w)
    for i in order:
        r = rl[i]
        if r != i:
            acc[r] += acc[i]
    return np.array(acc, np.float32).reshape(h, w)


def poly_window(g, pts_rc, pad):
    rs = [p[0] for p in pts_rc]
    cs = [p[1] for p in pts_rc]
    r0 = max(0, int(math.floor(min(rs))) - pad)
    r1 = min(g.H, int(math.ceil(max(rs))) + pad + 1)
    c0 = max(0, int(math.floor(min(cs))) - pad)
    c1 = min(g.W, int(math.ceil(max(cs))) + pad + 1)
    return r0, r1, c0, c1


def zone_mask(g, z):
    """Window (r0,r1,c0,c1) and a 0..1 float mask for a zone given as poly / line+width_km / circle."""
    feather = float(z.get("feather_km", 4.0)) / g.kx
    pad = int(feather * 2) + 3
    if "poly" in z:
        pts = [g.rc(p[0], p[1]) for p in z["poly"]]
        r0, r1, c0, c1 = poly_window(g, pts, pad)
        if r1 <= r0 or c1 <= c0:
            return None
        im = Image.new("L", (c1 - c0, r1 - r0), 0)
        ImageDraw.Draw(im).polygon([(c - c0, r - r0) for r, c in pts], fill=255)
    elif "line" in z:
        pts = [g.rc(p[0], p[1]) for p in z["line"]]
        wpx = max(1.0, float(z.get("width_km", 10.0)) / g.kx)
        r0, r1, c0, c1 = poly_window(g, pts, pad + int(wpx))
        if r1 <= r0 or c1 <= c0:
            return None
        im = Image.new("L", (c1 - c0, r1 - r0), 0)
        dr = ImageDraw.Draw(im)
        xy = [(c - c0, r - r0) for r, c in pts]
        dr.line(xy, fill=255, width=int(round(wpx)), joint="curve")
        for x, y in xy:
            dr.ellipse([x - wpx / 2, y - wpx / 2, x + wpx / 2, y + wpx / 2], fill=255)
    elif "circle" in z:
        cc = z["circle"]
        rr, cx = g.rc(cc["center"][0], cc["center"][1])
        rpx = float(cc["radius_km"]) / g.kx
        r0, r1, c0, c1 = poly_window(g, [(rr - rpx, cx - rpx), (rr + rpx, cx + rpx)], pad)
        if r1 <= r0 or c1 <= c0:
            return None
        im = Image.new("L", (c1 - c0, r1 - r0), 0)
        ImageDraw.Draw(im).ellipse([cx - c0 - rpx, rr - r0 - rpx, cx - c0 + rpx, rr - r0 + rpx], fill=255)
    else:
        return None
    if feather > 0.5:
        im = im.filter(ImageFilter.GaussianBlur(radius=feather * 0.5))
    return r0, r1, c0, c1, np.asarray(im, dtype=np.float32) / 255.0


# ---------------------------------------------------------------- main build
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=7000, help="output grid width (height follows the heightmap aspect)")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--urban-scale", type=int, default=1)
    ap.add_argument("--out", default=D, help="output folder (default data/desert)")
    ap.add_argument("--preview", default=os.path.join(ROOT, "build", "desert_landcover_preview.png"))
    ap.add_argument("--zones", default=os.path.join(D, "landcover_zones.json"))
    a = ap.parse_args()

    meta = json.load(open(os.path.join(D, "region_meta.json")))
    g = Grid(meta, a.width)
    W, H = g.W, g.H
    max_elev = float(meta.get("max_elev_m", 3000))
    log("grid %dx%d  %.3f km/px x, %.3f km/px y" % (W, H, g.kx, g.ky))

    # --- inputs
    hv = np.asarray(Image.open(os.path.join(D, "region_height.png")), dtype=np.float32)
    elev = hv * (max_elev / 65535.0)
    del hv
    if elev.shape != (H, W):
        elev = resize_f(elev, W, H, Image.BOX)
    coast = np.asarray(Image.open(os.path.join(D, "region_coast.png")).convert("L").resize((W, H), Image.BILINEAR))
    land = coast > 127
    sea = ~land
    log("land fraction %.3f, elev max %.0f m" % (land.mean(), elev.max()))
    zones_doc = json.load(open(a.zones))

    # --- derived layers
    lat_r = g.lat_rows()
    lon_c = g.lon_cols()
    dx_m = (g.dlon * 111320.0 * np.cos(np.radians(lat_r))).astype(np.float32)
    dy_m = g.dlat * 110574.0
    gy, gx = np.gradient(elev)
    slope = np.degrees(np.arctan(np.hypot(gx / dx_m[:, None], gy / dy_m))).astype(np.float32)
    del gx, gy
    blur = resize_f(resize_f(elev, max(8, W // 5), max(8, H // 5), Image.BOX), W, H, Image.BICUBIC)
    rel = (elev - blur).astype(np.float32)          # <0 = valley, >0 = ridge (1.5 km scale)
    del blur
    log("slope pct 50/90/99: %s" % np.percentile(slope[land][::50], [50, 90, 99]).round(2))

    fine = chamfer(sea, 7, g.kx, g.ky)
    f4 = 4
    sea_c = np.asarray(Image.fromarray(sea.astype(np.uint8) * 255).resize((W // f4, H // f4), Image.BOX)) > 127
    coarse = chamfer(sea_c, 120, g.kx * f4, g.ky * f4)
    coarse = np.minimum(coarse, 400.0)
    dist = np.where(fine < 2.0, fine, resize_f(coarse, W, H, Image.BILINEAR)).astype(np.float32)
    del fine, coarse
    dist[sea] = 0.0
    log("distance to sea done")

    elev_c = resize_f(elev, W // f4, H // f4, Image.BOX)
    acc_c = flow_accumulation(elev_c, sea_c)
    lacc = resize_f(np.log2(acc_c), W, H, Image.BILINEAR)
    log("flow accumulation done (max %d cells)" % acc_c.max())

    # --- wetness index (0 desert .. 1 green)
    lat2 = lat_r[:, None]
    lon2 = lon_c[None, :]
    east = np.clip((lon2 - 16.0) / 3.0, 0, 1)
    wet_lat = (1 - east) * (lat2 - 33.9) / 3.2 + east * (lat2 - 31.6) / 3.0
    wet = wet_lat + 0.12 * np.exp(-dist / 15.0) + 0.25 * np.clip((elev - 300.0) / 600.0, 0, 1) * (lat2 > 31.8)
    wet = np.clip(wet, 0, 1).astype(np.float32)
    del wet_lat, east

    # --- base classes
    n1 = vnoise((H, W), 70 * W / 7000.0, a.seed + 1, 2)
    n2 = vnoise((H, W), 18 * W / 7000.0, a.seed + 2, 2)
    n3 = vnoise((H, W), 9 * W / 7000.0, a.seed + 3, 1)
    cls = np.zeros((H, W), np.uint8)
    # desert floor: hamada on the high plateaus, reg in dark patches, plain sand low down
    hi = (elev + 50.0 * (n2 - 0.5)) >= 165.0
    base = np.where(hi & (slope < 8), 112, 60).astype(np.uint8)
    base = np.where((n1 + 0.25 * (n3 - 0.5) > 0.86) & (slope < 6) & (dist > 15.0), 113, base).astype(np.uint8)
    base = np.where((n1 + 0.2 * (n3 - 0.5) < 0.03) & (slope < 2.5) & (elev < 300) & (lat2 < 33.5), 115, base).astype(np.uint8)
    cls[land] = base[land]
    # steppe and green belts from the wetness index
    steppe = land & (wet >= 0.12) & (wet < 0.30)
    cls[steppe & (n2 < (wet - 0.12) / 0.18 * 0.6)] = 30
    cls[steppe & (n3 < (wet - 0.12) / 0.18 * 0.35) & (n1 > 0.4)] = 20
    mid = land & (wet >= 0.30) & (wet < 0.55)
    cls[mid] = 30
    cls[mid & ((n2 > 0.5) | (slope > 4))] = 20
    cls[mid & (slope < 3) & (elev < 350) & (n3 < (wet - 0.3) / 0.25 * 0.55)] = 40
    green = land & (wet >= 0.55)
    cls[green] = 20
    cls[green & (slope < 4) & (elev < 500) & (n3 < 0.62)] = 40
    cls[green & (slope < 5) & (elev < 400) & (n2 < 0.22) & (lat2 > 34.0)] = 121
    cls[green & (wet > 0.75) & (elev > 350) & (n1 > 0.55) & (slope < 25)] = 10
    # rock: steep ground
    desert_like = land & (wet < 0.30)
    cls[desert_like & (slope >= 4.0)] = 114
    cls[land & ~desert_like & (slope >= 13.0)] = 114
    # wadi beds: drainage lines in valley pixels, arid country only
    wadi = land & (lacc >= math.log2(40.0)) & (rel < -1.2) & (slope < 10) & (elev > 3) & (wet < 0.40) & (dist > 1.5)
    cls[wadi] = 117
    # coast: beach strip, rock where it is cliff
    beach = land & (dist <= 0.9) & (slope < 5) & (elev < 25)
    cls[beach] = 110
    cls[land & (dist <= 1.2) & (slope >= 9)] = 114
    cls[sea] = 0
    log("base classes done")

    # --- curated zones
    zid = {}
    for z in zones_doc.get("zones", []):
        zid[z["id"]] = z
    zs = sorted(zones_doc.get("zones", []), key=lambda z: int(z.get("priority", 50)))
    warn = 0
    for zi, z in enumerate(zs):
        if z.get("disabled"):
            continue
        res = zone_mask(g, z)
        if res is None:
            print("WARN zone %s: no shape / outside grid" % z["id"])
            warn += 1
            continue
        r0, r1, c0, c1, m = res
        sl = (slice(r0, r1), slice(c0, c1))
        shape = m.shape
        edge = vnoise(shape, max(3.0, float(z.get("edge_km", 2.5)) / g.kx), a.seed + 100 + zi, 1)
        paint = m > edge * 0.999
        wh = z.get("where", {})
        e, s, d = elev[sl], slope[sl], dist[sl]
        ok = land[sl] & paint
        if "elev_min" in wh: ok &= e >= wh["elev_min"]
        if "elev_max" in wh: ok &= e <= wh["elev_max"]
        if "slope_min" in wh: ok &= s >= wh["slope_min"]
        if "slope_max" in wh: ok &= s <= wh["slope_max"]
        if "coast_dist_max_km" in wh: ok &= d <= wh["coast_dist_max_km"]
        if "coast_dist_min_km" in wh: ok &= d >= wh["coast_dist_min_km"]
        if "rel_max" in wh: ok &= rel[sl] <= wh["rel_max"]
        dens = float(z.get("density", 1.0))
        if dens < 1.0:
            ok &= vnoise(shape, max(2.0, float(z.get("patch_km", 6.0)) / g.kx), a.seed + 500 + zi, 2) < dens
        if "classes_in" in z:
            allow = np.zeros(shape, bool)
            for c in z["classes_in"]:
                allow |= cls[sl] == (NAME2ID[c] if isinstance(c, str) else c)
            ok &= allow
        else:
            ok &= cls[sl] != 50
        cid = NAME2ID[z["class"]] if isinstance(z["class"], str) else int(z["class"])
        cls[sl][ok] = cid
        chk = z.get("check")
        inside = land[sl] & (m > 0.5)
        if inside.sum() > 0:
            me = float(e[inside].mean())
            lf = float(inside.sum()) / max(1.0, float((m > 0.5).sum()))
            msg = ""
            if chk:
                if "mean_elev_max" in chk and me > chk["mean_elev_max"]: msg += " mean elev %.0f > %s" % (me, chk["mean_elev_max"])
                if "mean_elev_min" in chk and me < chk["mean_elev_min"]: msg += " mean elev %.0f < %s" % (me, chk["mean_elev_min"])
                if "land_frac_min" in chk and lf < chk["land_frac_min"]: msg += " land frac %.2f < %s" % (lf, chk["land_frac_min"])
            if msg:
                print("WARN zone %s (%s):%s" % (z["id"], z.get("name", ""), msg))
                warn += 1
            print("  zone %-26s -> %-12s painted %8d px  (zone land %7d, mean elev %6.1f m)" % (z["id"], CLASSES[cid], int(ok.sum()), int(inside.sum()), me))
        else:
            print("WARN zone %s has no land under it" % z["id"])
            warn += 1

    # --- oases
    for o in zones_doc.get("oases", []):
        if not g.inside(o["lat"], o["lon"]):
            print("  oasis %-14s outside the map bounds (lat %.2f) - skipped" % (o["id"], o["lat"]))
            continue
        r = float(o["radius_km"])
        for part, (rad, cid, dens) in {"ring": (r, 40, 0.55), "core": (r * 0.55, 120, 0.9)}.items():
            z = {"circle": {"center": [o["lat"], o["lon"]], "radius_km": rad}, "feather_km": rad * 0.35, "edge_km": 0.8}
            res = zone_mask(g, z)
            if res is None:
                continue
            r0, r1, c0, c1, m = res
            sl = (slice(r0, r1), slice(c0, c1))
            edge = vnoise(m.shape, 3.0, a.seed + 900 + len(o["id"]), 1)
            ok = land[sl] & (m > edge) & (vnoise(m.shape, 2.5, a.seed + 910, 1) < dens) & (cls[sl] != 50)
            cls[sl][ok] = cid
        if not land[int(min(H - 1, g.rc(o["lat"], o["lon"])[0])), int(min(W - 1, g.rc(o["lat"], o["lon"])[1]))]:
            print("WARN oasis %s centre is in the sea mask" % o["id"])

    # --- towns -> urban mask
    towns = []
    ud = zones_doc.get("urban", {})
    base_r = ud.get("radius_km", {"city": 3.0, "town": 1.3, "village": 0.65})
    over = {k.lower(): v for k, v in ud.get("overrides", {}).items()}
    for t in json.load(open(os.path.join(D, "osm", "towns.json")))["towns"]:
        towns.append((t["name"], t["lat"], t["lon"], t.get("kind", "village")))
    for c in json.load(open(os.path.join(D, "locations.json"))).get("cities", []):
        towns.append((c.get("id", c.get("name", "")), c["lat"], c["lon"], "city"))
    for x in ud.get("extra", []):
        towns.append((x["name"], x["lat"], x["lon"], "extra:%s" % x["radius_km"]))
    placed = []
    for name, lat, lon, kind in towns:
        if not g.inside(lat, lon):
            continue
        if kind.startswith("extra:"):
            rad = float(kind[6:])
        else:
            rad = float(over.get(name.lower(), base_r.get(kind, 0.65)))
        # merge duplicates (same place in towns.json and locations.json): keep the larger
        dup = False
        for p in placed:
            if abs(p[1] - lat) < 0.06 and abs(p[2] - lon) < 0.06 and not kind.startswith("extra:"):
                p[3] = max(p[3], rad)
                dup = True
                break
        if not dup:
            placed.append([name, lat, lon, rad])
    urb = np.zeros((H, W), np.float32)
    for name, lat, lon, rad in placed:
        reff = rad / 0.75
        rr, cc = g.rc(lat, lon)
        rpx = reff / g.kx * 1.25
        r0, r1 = max(0, int(rr - rpx) - 2), min(H, int(rr + rpx) + 3)
        c0, c1 = max(0, int(cc - rpx) - 2), min(W, int(cc + rpx) + 3)
        if r1 <= r0 or c1 <= c0:
            continue
        yy, xx = np.mgrid[r0:r1, c0:c1].astype(np.float32)
        dd = np.hypot((xx - cc) * g.kx, (yy - rr) * g.ky)
        nz = vnoise(dd.shape, max(3.0, reff / g.kx * 0.5), (zlib.crc32(name.encode('utf-8')) & 0xffff) + a.seed, 2)
        re = reff * (0.78 + 0.44 * nz)
        t = np.clip((1.0 - dd / re) / 0.5, 0, 1)          # 1 inside half the radius, 0 at the edge
        v = t * t * (3 - 2 * t)
        np.maximum(urb[r0:r1, c0:c1], v, out=urb[r0:r1, c0:c1])
        ir, ic = int(min(H - 1, max(0, rr))), int(min(W - 1, max(0, cc)))
        if not land[ir, ic] and dist[max(0, ir - 3):ir + 4, max(0, ic - 3):ic + 4].size and sea[ir, ic]:
            print("WARN town %s centre is in the sea mask (NE coast coarse)" % name)
    urb[sea] = 0.0
    cls[(urb >= 0.5) & land] = 50
    log("towns placed: %d" % len(placed))

    # --- write
    out = a.out
    os.makedirs(out, exist_ok=True)
    cls.tofile(os.path.join(out, "region_landcover.bin"))
    json.dump({
        "width": W, "height": H, "lat_min": g.lat_min, "lat_max": g.lat_max, "lon_min": g.lon_min, "lon_max": g.lon_max,
        "source": "DERIVED by tools/make_desert_landcover.py from region_height.png, region_coast.png, osm/*.json, locations.json and "
                  "data/desert/landcover_zones.json (no satellite classification; curated + rule based)",
        "seed": a.seed,
        "classes": {str(k): v for k, v in CLASSES.items() if k},
        "worldcover_compatible_ids": [10, 20, 30, 40, 50, 60, 80, 90],
        "desert_extension_ids": [k for k in CLASSES if k >= 110],
    }, open(os.path.join(out, "region_landcover.json"), "w"), indent=1)
    s = a.urban_scale
    um = Image.fromarray(np.clip(urb * 255.0, 0, 255).astype(np.uint8), mode="L")
    if s != 1:
        um = um.resize((W * s, H * s), Image.BICUBIC)
    um.save(os.path.join(out, "region_urban.png"), optimize=True)
    log("wrote bin/json/urban")

    vals, counts = np.unique(cls, return_counts=True)
    print("CLASS HISTOGRAM (share of all cells / of land):")
    nland = int(land.sum())
    for v, c in zip(vals, counts):
        print("  %3d %-13s %9d  %5.2f%% of cells  %5.2f%% of land" % (v, CLASSES.get(int(v), "?"), c, 100.0 * c / cls.size, 100.0 * c / nland if v else 0.0))
    print("warnings:", warn)

    # --- preview (half size, hillshade modulated)
    ph, pw = H // 2, W // 2
    lut = np.zeros((256, 3), np.uint8)
    for k, rgb in PREVIEW_RGB.items():
        lut[k] = rgb
    sub = cls[::2, ::2][:ph, :pw]
    img = lut[sub].astype(np.float32)
    e2 = elev[::2, ::2][:ph, :pw]
    hs = 0.5 + 0.5 * np.clip(np.gradient(e2, axis=1) * 0.04 + np.gradient(e2, axis=0) * -0.03, -1, 1)
    img *= (0.72 + 0.5 * hs)[:, :, None]
    img[sub == 50] = (230, 40, 40)
    os.makedirs(os.path.dirname(a.preview), exist_ok=True)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(a.preview)
    log("preview", a.preview)


if __name__ == "__main__":
    main()
