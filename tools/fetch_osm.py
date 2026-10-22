#!/usr/bin/env python3
"""Fetch simplified OSM vector data via Overpass -> data/osm/{roads,rails,rivers,coast,woods,towns}.json.

Each layer is tiled (non-overlapping bbox tiles, geometry clipped to the tile), retried over several
Overpass mirrors, Douglas-Peucker simplified and coordinate-rounded. If a layer cannot be fetched, a
synthetic fallback is generated from data/locations.json (+ the coastline polygons of make_heightmap).
data/osm/_source.json records, per layer, whether it is "overpass" or "fallback".

Formats (all lat/lon, [lat, lon] pairs):
  roads/rails/rivers/coast : {"lines":[{"k":"<class>","n":"<name?>","pts":[[lat,lon],...]}]}
  woods                    : {"polys":[{"pts":[[lat,lon],...]}]}   (closed rings)
  towns                    : {"towns":[{"name":..,"lat":..,"lon":..,"kind":"city|town|village"}]}

Usage: python tools/fetch_osm.py [--layers roads,rails,...] [--force-fallback]
"""
import argparse
import json
import math
import os
import random
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "osm")
CACHE = os.path.join(ROOT, "tools", "cache", "osm")
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
TILE_LAT, TILE_LON = 0.7, 1.55  # 4 x 6 tiles
TILE_SIZE = (TILE_LAT, TILE_LON)
LAYER_BUDGET_S = 3000  # give up on a layer (-> fallback) after 7 min or 8 failed tiles
STREAM_MIN_KM = 6.0    # rivers layer: drop waterway=stream pieces shorter than this (keeps the file loadable)

# layer -> (overpass filter lines, simplify tolerance deg, kind)
LAYERS = {
    "roads": dict(q=['way["highway"~"^(motorway|trunk|primary)$"]'], tol=0.0035, geom="line"),
    "rails": dict(q=['way["railway"="rail"]["usage"="main"]'], tol=0.0035, geom="line"),
    # broadened river network: rivers + canals + riverbank areas (outer ring) + streams (min-length filtered).
    # tol raised 0.003 -> 0.004 so the richer network still loads fast (SPEC <2 s) and stays well under 2 MB.
    "rivers": dict(q=['way["waterway"="river"]', 'way["waterway"="canal"]',
                      'way["waterway"="riverbank"]', 'way["waterway"="stream"]'], tol=0.004, geom="line"),
    "coast": dict(q=['way["natural"="coastline"]'], tol=0.0018, geom="line"),
    "woods": dict(q=['way["landuse"="forest"]', 'way["natural"="wood"]'], tol=0.004, geom="poly"),
    "towns": dict(q=['node["place"~"^(city|town)$"]'], geom="node"),
    # 1927-35 National Grid pylons + overhead lines (P5). High-voltage power=line ways; the per-record
    # voltage tag lets fit_size/the runtime keep only >= 132 kV (the period grid voltage).
    "power": dict(q=['way["power"="line"]'], tol=0.004, geom="line"),
}


# ---------------------------------------------------------------- helpers
def dp(pts, tol):
    """Iterative Douglas-Peucker on [(lat, lon)]; lon scaled by cos(lat) for isotropy."""
    n = len(pts)
    if n < 3:
        return pts
    k = math.cos(math.radians(50.3))
    P = [(p[0], p[1] * k) for p in pts]
    keep = [False] * n
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = P[a]
        bx, by = P[b]
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        best, bi = -1.0, -1
        for i in range(a + 1, b):
            px, py = P[i]
            if L2 == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
                d = math.hypot(px - ax - t * dx, py - ay - t * dy)
            if d > best:
                best, bi = d, i
        if best > tol:
            keep[bi] = True
            stack.append((a, bi))
            stack.append((bi, b))
    return [pts[i] for i in range(n) if keep[i]]


def r4(pts):
    return [[round(p[0], 4), round(p[1], 4)] for p in pts]


def _first_int(v, default=0):
    """First integer in an OSM tag value like '132000' or '132000; 33000' -> 132000."""
    if v is None:
        return default
    for part in str(v).replace(";", " ").split():
        try:
            return int(float(part))
        except ValueError:
            continue
    return default


def tiles():
    TILE_LAT, TILE_LON = TILE_SIZE
    la = LAT_MIN
    while la < LAT_MAX - 1e-9:
        lo = LON_MIN
        la2 = min(la + TILE_LAT, LAT_MAX)
        while lo < LON_MAX - 1e-9:
            lo2 = min(lo + TILE_LON, LON_MAX)
            yield (la, lo, la2, lo2)
            lo = lo2
        la = la2


def overpass(query, tries=1):
    import requests
    last = None
    for attempt in range(tries):
        for ep in ENDPOINTS:
            # POST first; some proxies/edge networks drop the POST body, so retry the same query as GET.
            try:
                r = requests.post(ep, data={"data": query}, timeout=75,
                                  headers={"User-Agent": "ww2-channel-air-war-tools/1.0"})
                if r.status_code == 200:
                    return r.json()
                last = f"{ep}: HTTP {r.status_code}"
            except Exception as e:  # noqa: BLE001
                last = f"{ep}: {type(e).__name__}: {str(e)[:80]}"
            try:
                r = requests.get(ep, params={"data": query}, timeout=75,
                                 headers={"User-Agent": "ww2-channel-air-war-tools/1.0"})
                if r.status_code == 200:
                    return r.json()
                last = f"{ep}: HTTP {r.status_code} (GET)"
            except Exception as e:  # noqa: BLE001
                last = f"{ep}: {type(e).__name__}: {str(e)[:80]}"
            time.sleep(2)
        time.sleep(5 * (attempt + 1))
    raise RuntimeError(last)


def tile_query(layer, cfg, bb):
    s, w, n, e = bb
    bbox = f"{s},{w},{n},{e}"
    if cfg["geom"] == "node":
        body = "".join(f"{q}({bbox});" for q in cfg["q"])
        return f"[out:json][timeout:90];({body});out;"
    body = "".join(f"{q}({bbox});" for q in cfg["q"])
    return f"[out:json][timeout:120];({body});out tags geom({bbox});"


def split_geom(geom):
    """geometry list with None for clipped-out nodes -> list of [(lat, lon)] runs."""
    runs, cur = [], []
    for g in geom:
        if g is None:
            if len(cur) > 1:
                runs.append(cur)
            cur = []
        else:
            cur.append((g["lat"], g["lon"]))
    if len(cur) > 1:
        runs.append(cur)
    return runs


def bbox_area_deg2(pts):
    la = [p[0] for p in pts]
    lo = [p[1] for p in pts]
    return (max(la) - min(la)) * (max(lo) - min(lo))


def run_length_km(run):
    """Approximate polyline length in km (equirectangular, ~51 deg N)."""
    tot = 0.0
    for i in range(1, len(run)):
        dlat = (run[i][0] - run[i - 1][0]) * 110.5
        dlon = (run[i][1] - run[i - 1][1]) * 71.0
        tot += math.hypot(dlat, dlon)
    return tot


# ---------------------------------------------------------------- fetch
def fetch_layer(layer):
    cfg = LAYERS[layer]
    os.makedirs(CACHE, exist_ok=True)
    lines, polys, towns = [], [], []
    seen_nodes = set()
    t_start, fails = time.time(), 0
    for ti, bb in enumerate(tiles()):
        if time.time() - t_start > LAYER_BUDGET_S:
            raise RuntimeError(f"time budget ({LAYER_BUDGET_S}s) exceeded at tile {ti}")
        cpath = os.path.join(CACHE, f"{layer}_{TILE_SIZE[0]}x{TILE_SIZE[1]}_{ti}.json")
        if os.path.exists(cpath):
            data = json.load(open(cpath))
        else:
            try:
                data = overpass(tile_query(layer, cfg, bb))
            except RuntimeError:
                fails += 1
                if fails >= 8:
                    raise
                continue
            json.dump(data, open(cpath, "w"))
            time.sleep(1.5)
        els = data.get("elements", [])
        print(f"  [{layer}] tile {ti} {bb}: {len(els)} elements", flush=True)
        for el in els:
            tags = el.get("tags", {})
            if cfg["geom"] == "node":
                if el["id"] in seen_nodes or "name" not in tags:
                    continue
                seen_nodes.add(el["id"])
                towns.append(dict(name=tags["name"], lat=round(el["lat"], 4), lon=round(el["lon"], 4),
                                  kind=tags.get("place", "village")))
                continue
            geom = el.get("geometry")
            if not geom:
                continue
            for run in split_geom(geom):
                if cfg["geom"] == "poly":
                    if len(run) < 4 or bbox_area_deg2(run) < 0.0006:  # drop small woods (<~6 km^2 bbox)
                        continue
                    run = dp(run, cfg["tol"])
                    if len(run) >= 4:
                        polys.append(dict(pts=r4(run)))
                else:
                    k = (tags.get("waterway") or tags.get("highway") or tags.get("railway")
                         or tags.get("natural") or tags.get("power") or "x")
                    # streams are only worth keeping when they run a decent distance (size/loading guard)
                    if layer == "rivers" and k == "stream" and run_length_km(run) < STREAM_MIN_KM:
                        continue
                    rec = dict(k=k, pts=r4(dp(run, cfg["tol"])))
                    if layer == "rivers" and tags.get("name"):
                        rec["n"] = tags["name"]
                    if layer == "power":
                        rec["v"] = _first_int(tags.get("voltage"))
                    lines.append(rec)
    if layer == "towns":
        return dict(towns=towns)
    if cfg["geom"] == "poly":
        return dict(polys=polys)
    return dict(lines=lines)


def fit_size(layer, out, limit=4_500_000):
    """Shrink payload if it exceeds the limit (drop minor classes / short pieces)."""
    if layer == "rivers":
        limit = min(limit, 1_800_000)  # keep rivers.json well under ~2 MB
    def size():
        return len(json.dumps(out, separators=(",", ":")))
    if layer == "roads" and size() > limit:
        out["lines"] = [l for l in out["lines"] if l["k"] != "secondary"]
    if layer == "towns" and size() > limit:
        out["towns"] = [t for t in out["towns"] if t["kind"] != "village"]
    # power: the period grid is 132 kV, so drop the lower-voltage distribution lines first; this keeps
    # power.json small and the runtime only ever instantiates pylons for >= 132 kV lines.
    if layer == "power":
        out["lines"] = [l for l in out["lines"] if int(l.get("v", 0)) == 0 or int(l.get("v", 0)) >= 132000]
    # rivers: keep the payload well under ~2 MB by dropping the thinnest class (streams) first
    if layer == "rivers" and size() > 1_800_000:
        out["lines"] = [l for l in out["lines"] if l["k"] != "stream"]
    tol = 0.006
    while size() > limit and layer != "towns" and tol < 0.05:
        key = "lines" if "lines" in out else "polys"
        for rec in out[key]:
            rec["pts"] = r4(dp(rec["pts"], tol))
        tol *= 1.6
    return out


# ---------------------------------------------------------------- fallback
def load_locations():
    return json.load(open(os.path.join(ROOT, "data", "locations.json"), encoding="utf-8"))


def land_sampler():
    """returns f(lat, lon)->bool land, from the heightmap if available else polygons."""
    try:
        import numpy as np
        from PIL import Image
        a = np.asarray(Image.open(os.path.join(ROOT, "data", "heightmap", "region_height.png")))
        H, W = a.shape

        def f(lat, lon):
            x = int((lon - LON_MIN) / (LON_MAX - LON_MIN) * W)
            y = int((LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * H)
            if not (0 <= x < W and 0 <= y < H):
                return False
            return a[y, x] > 0
        return f
    except Exception:  # noqa: BLE001
        return lambda lat, lon: True


def wiggle(a, b, rng, land, step_km=8.0):
    """curved polyline a->b; returns None if it crosses water."""
    n = max(2, int(math.hypot((b[0] - a[0]) * 110.5, (b[1] - a[1]) * 71.0) / step_km))
    dx, dy = b[1] - a[1], b[0] - a[0]
    L = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / L, dx / L
    ph = rng.random() * 6.28
    amp = L * 0.06
    pts = []
    for i in range(n + 1):
        t = i / n
        off = math.sin(t * math.pi) * amp * math.sin(ph + t * 5.0)
        p = (a[0] + dy * t + ny * off, a[1] + dx * t + nx * off)
        if not land(*p):
            return None
        pts.append(p)
    return pts


def mst_edges(nodes, extra=0.35, rng=None):
    n = len(nodes)
    d = lambda i, j: math.hypot((nodes[i][0] - nodes[j][0]) * 110.5, (nodes[i][1] - nodes[j][1]) * 71.0)
    inT, edges = {0}, []
    while len(inT) < n:
        e = min(((d(i, j), i, j) for i in inT for j in range(n) if j not in inT))
        edges.append((e[1], e[2]))
        inT.add(e[2])
    pairs = sorted((d(i, j), i, j) for i in range(n) for j in range(i + 1, n))
    have = set(edges) | {(b, a) for a, b in edges}
    for dist, i, j in pairs[: int(n * 2.5)]:
        if (i, j) not in have and rng.random() < extra and dist < 150:
            edges.append((i, j))
            have.add((i, j))
    return edges


def fallback_network(kind, seed):
    rng = random.Random(seed)
    land = land_sampler()
    loc = load_locations()
    cities = [c for c in loc["cities"] if c.get("in_bounds", True) and c["size"] >= (2 if kind == "rails" else 1)
              and land(c["lat"], c["lon"])]
    nodes = [(c["lat"], c["lon"]) for c in cities]
    lines = []
    for i, j in mst_edges(nodes, 0.35 if kind == "roads" else 0.2, rng):
        p = wiggle(nodes[i], nodes[j], rng, land)
        if p:
            k = "primary" if kind == "roads" else "rail"
            if kind == "roads" and max(cities[i]["size"], cities[j]["size"]) >= 4:
                k = "motorway"
            lines.append(dict(k=k, pts=r4(p)))
    return dict(lines=lines)


# ---------------------------------------------------------------- rivers fallback
# Hand-drawn courses (approximate, lat/lon) for the Channel-theatre rivers so a no-network run still reads right.
# ~50 real rivers of England, Normandy/Picardy/Flanders and the Rhine-Meuse delta/Ruhr. Each list is source->mouth
# (or a representative reach); points are deliberately coarse — this is a fallback, not a survey.
RIVERS_FB = {
    # --- England: Thames estuary + south coast ---
    "Thames": [(51.75, -1.62), (51.65, -1.30), (51.55, -1.05), (51.46, -0.70), (51.47, -0.40),
               (51.505, -0.12), (51.495, 0.03), (51.46, 0.25), (51.45, 0.45), (51.48, 0.70)],
    "Medway": [(51.02, 0.10), (51.15, 0.35), (51.27, 0.50), (51.40, 0.60)],
    "Swale": [(51.30, 0.72), (51.35, 0.85), (51.40, 0.95)],
    "Great Stour": [(51.10, 0.80), (51.22, 0.90), (51.30, 1.00), (51.38, 1.12)],
    "Rother": [(51.06, 0.52), (50.98, 0.60), (50.88, 0.68), (50.83, 0.74)],
    "Arun": [(51.06, -0.58), (50.98, -0.57), (50.88, -0.55), (50.81, -0.54)],
    "Adur": [(51.02, -0.22), (50.92, -0.26), (50.84, -0.28)],
    "Ouse": [(51.06, -0.06), (50.95, -0.05), (50.86, -0.01), (50.83, 0.02)],
    "Mole": [(51.32, -0.34), (51.26, -0.30), (51.19, -0.25), (51.14, -0.20)],
    "Wey": [(51.20, -0.62), (51.27, -0.63), (51.33, -0.60), (51.37, -0.55)],
    "Trent": [(52.85, -1.92), (52.88, -1.55), (52.90, -1.20), (52.95, -0.95)],
    "Severn": [(52.70, -2.72), (52.30, -2.25), (51.95, -2.25), (51.65, -2.55), (51.55, -2.70)],
    "Avon": [(52.30, -1.62), (52.20, -1.72), (52.10, -1.95), (52.00, -2.10)],
    "Great Ouse": [(52.22, -0.62), (52.30, -0.40), (52.40, -0.25), (52.55, -0.20)],
    # --- France: Seine + Picardy/Pas-de-Calais ---
    "Seine": [(48.92, 1.85), (48.99, 1.70), (49.09, 1.48), (49.33, 1.20), (49.44, 1.10),
              (49.40, 0.85), (49.44, 0.60), (49.43, 0.35), (49.42, 0.10)],
    "Somme": [(49.80, 2.90), (49.90, 2.30), (49.95, 2.10), (50.05, 1.90), (50.10, 1.83), (50.20, 1.60)],
    "Bresle": [(49.85, 1.78), (49.95, 1.68), (50.03, 1.55), (50.06, 1.47)],
    "Canche": [(50.32, 1.88), (50.42, 1.72), (50.49, 1.62), (50.54, 1.58)],
    "Authie": [(50.24, 2.22), (50.30, 2.05), (50.35, 1.90), (50.37, 1.85)],
    "Lys": [(50.58, 2.45), (50.66, 2.72), (50.66, 3.00), (50.70, 3.10)],
    "Scarpe": [(50.28, 2.70), (50.42, 2.85), (50.55, 3.02), (50.63, 3.07)],
    "Deule": [(50.48, 2.85), (50.58, 2.92), (50.67, 3.04), (50.70, 3.07)],
    "Aa": [(50.58, 2.08), (50.70, 2.08), (50.80, 2.12)],
    "Aisne": [(49.45, 3.00), (49.36, 2.88), (49.40, 2.62)],
    "Risle": [(48.95, 0.55), (49.18, 0.55), (49.33, 0.58)],
    "Eure": [(48.90, 1.00), (49.10, 0.98), (49.18, 1.05)],
    # --- Normandy ---
    "Orne": [(48.95, -0.12), (49.05, -0.35), (49.18, -0.38), (49.29, -0.22)],
    "Dives": [(48.95, 0.00), (49.10, -0.05), (49.22, -0.08), (49.30, -0.10)],
    "Touques": [(49.00, 0.25), (49.20, 0.20), (49.35, 0.12)],
    "Vire": [(48.95, -0.92), (49.12, -0.92), (49.28, -1.05), (49.35, -1.12)],
    "Rance": [(48.92, -2.02), (49.00, -2.00), (49.12, -1.95), (49.20, -1.90)],
    # --- Belgium / Netherlands / Germany (Scheldt-Meuse-Rhine delta + Ruhr) ---
    "Escaut": [(50.28, 3.25), (50.55, 3.45), (50.83, 3.60), (51.05, 3.72), (51.12, 4.00),
               (51.22, 4.38), (51.38, 4.20), (51.40, 3.60)],
    "Leie": [(50.70, 3.10), (50.82, 3.22), (50.95, 3.35), (51.05, 3.58)],
    "Dender": [(50.58, 3.88), (50.78, 3.95), (50.95, 4.05)],
    "Dyle": [(50.70, 4.58), (50.85, 4.52), (50.97, 4.48)],
    "Senne": [(50.58, 4.15), (50.72, 4.28), (50.85, 4.35)],
    "Gete": [(50.68, 5.08), (50.80, 5.05), (50.92, 5.08)],
    "Sambre": [(50.25, 4.00), (50.41, 4.44), (50.47, 4.87)],
    "Meuse": [(49.95, 4.70), (50.20, 4.85), (50.47, 4.87), (50.52, 5.24), (50.63, 5.58), (50.85, 5.69),
              (51.19, 5.99), (51.37, 6.17), (51.60, 5.95), (51.77, 5.74), (51.73, 5.14), (51.80, 4.67), (51.92, 4.40)],
    "Waal": [(51.85, 5.85), (51.88, 5.60), (51.90, 5.25), (51.92, 4.95)],
    "Rhine": [(50.00, 8.27), (50.36, 7.60), (50.73, 7.10), (50.94, 6.96), (51.23, 6.77), (51.44, 6.73),
              (51.66, 6.62), (51.83, 6.12), (51.85, 5.85), (51.81, 5.25), (51.83, 4.97), (51.90, 4.45), (51.98, 4.12)],
    "Nederrijn": [(51.85, 5.95), (51.98, 5.91), (51.97, 5.45), (51.96, 5.00)],
    "Moselle": [(49.76, 6.64), (49.92, 7.05), (50.15, 7.40), (50.36, 7.59)],
    "Main": [(50.10, 8.95), (50.10, 8.68), (50.03, 8.45), (50.00, 8.27)],
    "Ruhr": [(51.37, 8.00), (51.40, 7.60), (51.43, 7.00), (51.45, 6.75)],
    "IJssel": [(51.98, 6.12), (52.25, 6.17), (52.52, 6.06)],
    "Lippe": [(51.65, 8.40), (51.67, 7.80), (51.64, 7.20), (51.65, 6.62)],
    "Emscher": [(51.52, 7.52), (51.52, 7.20), (51.48, 6.92)],
    "Wupper": [(51.20, 7.22), (51.26, 7.10), (51.18, 6.96)],
    "Sieg": [(50.80, 7.60), (50.82, 7.42), (50.80, 7.18)],
    "Lahn": [(50.60, 8.22), (50.46, 8.06), (50.36, 7.92)],
    "Nahe": [(49.80, 7.62), (49.85, 7.50), (49.90, 7.36)],
    "Neckar": [(49.50, 8.92), (49.46, 8.70), (49.48, 8.52)],
    "Chiers": [(49.45, 5.35), (49.55, 5.18), (49.70, 4.95)],
    "Semois": [(49.80, 5.05), (49.83, 4.90), (49.86, 4.75)],
    "Ourthe": [(50.35, 5.60), (50.50, 5.62), (50.62, 5.60)],
    "Dommel": [(51.28, 5.35), (51.45, 5.40), (51.55, 5.33)],
    "Niers": [(51.55, 6.30), (51.65, 6.18), (51.75, 6.12)],
}


def fallback_rivers():
    return dict(lines=[dict(k="river", n=n, pts=r4(p)) for n, p in RIVERS_FB.items()])


def fallback_coast():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import make_heightmap as mh
    lines = []
    for ring in (mh.ENGLAND, mh.WALES, mh.WIGHT, mh.FRANCE):
        pts = [p for p in ring if LAT_MIN < p[0] < LAT_MAX and LON_MIN < p[1] < LON_MAX]
        lines.append(dict(k="coastline", pts=r4(pts)))
    # drop the straight "world boundary" closers that run along the bounds edge
    out = []
    for l in lines:
        seg, cur = [], []
        for p in l["pts"]:
            edge = p[0] >= LAT_MAX - 0.001 or p[1] >= LON_MAX - 0.001 or p[0] <= LAT_MIN + 0.001
            if edge:
                if len(cur) > 1:
                    seg.append(cur)
                cur = []
            else:
                cur.append(p)
        if len(cur) > 1:
            seg.append(cur)
        out += [dict(k="coastline", pts=s) for s in seg]
    return dict(lines=out)


def fallback_woods(seed=5):
    rng = random.Random(seed)
    loc = load_locations()
    polys = []
    forests = [f for f in loc["features"] if f["type"] == "forest"]
    extra = [(50.88, -1.55, 9), (51.10, 0.20, 8), (49.30, 1.80, 10), (49.60, 0.90, 9), (50.10, 4.00, 12)]
    for f in forests:
        extra.append((f["lat"], f["lon"], f["radius_m"] / 1000.0))
    for lat, lon, rk in extra:
        if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
            continue
        rk = min(rk, 20.0)
        n = 18
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            r = rk * (0.7 + 0.5 * rng.random())
            pts.append((min(LAT_MAX, max(LAT_MIN, lat + math.sin(a) * r / 110.5)),
                        min(LON_MAX, max(LON_MIN, lon + math.cos(a) * r / 71.0))))
        pts.append(pts[0])
        polys.append(dict(pts=r4(pts)))
    return dict(polys=polys)


def fallback_towns():
    loc = load_locations()
    kind = {5: "city", 4: "city", 3: "town", 2: "town", 1: "village"}
    return dict(towns=[dict(name=c["name"], lat=c["lat"], lon=c["lon"], kind=kind[c["size"]])
                       for c in loc["cities"] if c.get("in_bounds", True)])


def fallback_power():
    """Curated period-grid fallback (P5): reuse data/pylons_1940.json when present, else a small
    straight-line stitch of the big London/South-East grid points."""
    path = os.path.join(ROOT, "data", "pylons_1940.json")
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
            lines = []
            for l in d.get("lines", []):
                lines.append(dict(k="line", v=int(l.get("v", 132000)), pts=r4(l["pts"])))
            if lines:
                return dict(lines=lines)
        except Exception:  # noqa: BLE001
            pass
    nodes = [(51.5468, -0.2295), (51.4817, -0.1447), (51.4400, 0.3400), (51.3714, -0.1038)]
    return dict(lines=[dict(k="line", v=132000, pts=r4([nodes[i], nodes[i + 1]])) for i in range(len(nodes) - 1)])


FALLBACKS = {
    "roads": lambda: fallback_network("roads", 11),
    "rails": lambda: fallback_network("rails", 23),
    "rivers": fallback_rivers,
    "coast": fallback_coast,
    "woods": fallback_woods,
    "towns": fallback_towns,
    "power": fallback_power,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--layers", default=",".join(LAYERS))
    ap.add_argument("--force-fallback", action="store_true")
    ap.add_argument("--tile", default="", help="tile size 'dlat,dlon' in degrees (smaller = fewer timeouts)")
    a = ap.parse_args()
    global TILE_SIZE
    if a.tile:
        TILE_SIZE = tuple(float(v) for v in a.tile.split(","))
    os.makedirs(OUT, exist_ok=True)
    spath = os.path.join(OUT, "_source.json")
    src = json.load(open(spath)) if os.path.exists(spath) else {}
    for layer in a.layers.split(","):
        out, source = None, None
        if not a.force_fallback:
            print(f"[{layer}] fetching from Overpass ...", flush=True)
            try:
                out = fit_size(layer, fetch_layer(layer))
                source = "overpass"
            except Exception as e:  # noqa: BLE001
                print(f"[{layer}] Overpass failed: {e}", file=sys.stderr)
        if out is None:
            print(f"[{layer}] using FALLBACK (synthetic)")
            out, source = FALLBACKS[layer](), "fallback"
        path = os.path.join(OUT, f"{layer}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(out, f, separators=(",", ":"), ensure_ascii=False)
        src[layer] = source
        print(f"[{layer}] {source}: {os.path.getsize(path) / 1024:.0f} KB")
    json.dump(src, open(spath, "w"), indent=1)


if __name__ == "__main__":
    main()
