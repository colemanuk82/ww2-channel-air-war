#!/usr/bin/env python3
"""Derive a plausible piste / track network for the desert map -> data/desert/tracks.json (same schema as osm/roads.json).

NOT surveyed data: it is generated. Nodes are the airfields and cities of data/desert/locations.json, the desert towns of
osm/towns.json, the in-bounds oases of landcover_zones.json and a few named war places. A minimum spanning tree plus a
couple of nearest-neighbour links joins them; each link is routed with A* over a cost grid built from the derived land
cover (data/desert/region_landcover.bin) and slope (sea impassable, salt pans / escarpments / dunes expensive, wadis
slightly dear). Links that mostly follow an existing road in osm/roads.json are dropped (those are drawn already).
Output lines: {"k": "track", "pts": [[lat, lon], ...], "n": name, "derived": true}; top level "source" says derived.
Run after make_desert_landcover.py:  python3 tools/make_desert_tracks.py"""
import heapq
import json
import math
import os

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data", "desert")
F = 6                                    # cost-grid block size in land-cover cells

meta = json.load(open(os.path.join(D, "region_meta.json")))
lc = json.load(open(os.path.join(D, "region_landcover.json")))
W0, H0 = lc["width"], lc["height"]
cls0 = np.fromfile(os.path.join(D, "region_landcover.bin"), np.uint8).reshape(H0, W0)
LAT0, LAT1, LON0, LON1 = lc["lat_min"], lc["lat_max"], lc["lon_min"], lc["lon_max"]
hv = np.asarray(Image.open(os.path.join(D, "region_height.png")), np.float32) * (meta["max_elev_m"] / 65535.0)
elev0 = np.asarray(Image.fromarray(hv, "F").resize((W0, H0), Image.BOX), np.float32)
W, H = W0 // F, H0 // F
cls = cls0[:H * F, :W * F].reshape(H, F, W, F)[:, 0, :, 0]       # nearest block sample
el = elev0[:H * F, :W * F].reshape(H, F, W, F).mean(axis=(1, 3))
kx = (LON1 - LON0) / W0 * 111.32 * math.cos(math.radians(33.75)) * F
ky = (LAT1 - LAT0) / H0 * 110.57 * F
gy, gx = np.gradient(el)
slope = np.degrees(np.arctan(np.hypot(gx / (kx * 1000), gy / (ky * 1000))))
COST = {0: 1e9, 10: 3.0, 20: 1.3, 30: 1.1, 40: 1.25, 50: 1.0, 60: 1.0, 80: 1e9, 90: 4.0, 110: 1.2, 111: 3.0, 112: 1.0,
        113: 1.0, 114: 6.0, 115: 2.6, 116: 12.0, 117: 1.6, 118: 1.1, 119: 3.0, 120: 1.0, 121: 1.3}
cost = np.ones((H, W), np.float32)
for k, v in COST.items():
    cost[cls == k] = v
cost += np.clip(slope, 0, 25).astype(np.float32) * 0.55
cost[cls == 0] = 1e9


def to_rc(lat, lon):
    return (LAT1 - lat) / (LAT1 - LAT0) * H, (lon - LON0) / (LON1 - LON0) * W


def to_ll(r, c):
    return LAT1 - (r + 0.5) / H * (LAT1 - LAT0), LON0 + (c + 0.5) / W * (LON1 - LON0)


def snap(lat, lon):
    r, c = to_rc(lat, lon)
    r, c = int(min(H - 1, max(0, r))), int(min(W - 1, max(0, c)))
    if cost[r, c] < 1e8:
        return r, c
    for rad in range(1, 8):
        best = None
        for dr in range(-rad, rad + 1):
            for dc in range(-rad, rad + 1):
                rr, cc = r + dr, c + dc
                if 0 <= rr < H and 0 <= cc < W and cost[rr, cc] < 1e8:
                    d = dr * dr + dc * dc
                    if best is None or d < best[0]:
                        best = (d, rr, cc)
        if best:
            return best[1], best[2]
    return None


# existing roads rasterised so duplicates can be dropped
road_mask = np.zeros((H, W), bool)
for ln in json.load(open(os.path.join(D, "osm", "roads.json")))["lines"] + json.load(open(os.path.join(D, "osm", "rails.json")))["lines"]:
    p = ln["pts"]
    for a, b in zip(p[:-1], p[1:]):
        n = int(max(abs(a[0] - b[0]) / (LAT1 - LAT0) * H, abs(a[1] - b[1]) / (LON1 - LON0) * W)) + 2
        for t in np.linspace(0, 1, n):
            r, c = to_rc(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            if 0 <= int(r) < H and 0 <= int(c) < W:
                road_mask[int(r), int(c)] = True
road_near = road_mask.copy()
for dr in (-1, 0, 1):
    for dc in (-1, 0, 1):
        road_near |= np.roll(np.roll(road_mask, dr, 0), dc, 1)

NB = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0), (-1, -1, 1.414), (-1, 1, 1.414), (1, -1, 1.414), (1, 1, 1.414)]


def astar(a, b):
    h = lambda r, c: math.hypot(r - b[0], c - b[1]) * 1.0
    g = {a: 0.0}
    prev = {}
    pq = [(h(*a), a)]
    while pq:
        f, cur = heapq.heappop(pq)
        if cur == b:
            path = [cur]
            while cur in prev:
                cur = prev[cur]
                path.append(cur)
            return path[::-1]
        if f - h(*cur) > g[cur] + 1e-6:
            continue
        for dr, dc, w in NB:
            r, c = cur[0] + dr, cur[1] + dc
            if not (0 <= r < H and 0 <= c < W):
                continue
            cc = cost[r, c]
            if cc > 1e8:
                continue
            ng = g[cur] + w * 0.5 * (cc + cost[cur[0], cur[1]])
            if ng < g.get((r, c), 1e18):
                g[(r, c)] = ng
                prev[(r, c)] = cur
                heapq.heappush(pq, (ng + h(r, c), (r, c)))
    return None


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    dmax, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        p = pts[i]
        t = ((p[0] - a[0]) * (b[0] - a[0]) + (p[1] - a[1]) * (b[1] - a[1])) / max(1e-9, (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2)
        t = min(1, max(0, t))
        d = math.hypot(p[0] - (a[0] + t * (b[0] - a[0])), p[1] - (a[1] + t * (b[1] - a[1])))
        if d > dmax:
            dmax, idx = d, i
    if dmax > eps:
        return rdp(pts[:idx + 1], eps)[:-1] + rdp(pts[idx:], eps)
    return [a, b]


# ---- nodes
nodes = []     # (id, name, lat, lon)
loc = json.load(open(os.path.join(D, "locations.json")))


def allowed(lat, lon):
    if lon < 12.5:
        return lat <= 35.6
    if lon < 16.0:
        return lat <= 33.6                # Tripolitania, not Malta / Sicily
    return lat <= 33.6 and not (lon >= 22.5 and lat >= 34.0)


for a in loc.get("airfields", []):
    if allowed(a["lat"], a["lon"]):
        nodes.append((a["id"], a["name"], a["lat"], a["lon"]))
for c in loc.get("cities", []):
    if allowed(c["lat"], c["lon"]):
        nodes.append((c["id"], c.get("name", c["id"]).title(), c["lat"], c["lon"]))
for t in json.load(open(os.path.join(D, "osm", "towns.json")))["towns"]:
    if t.get("kind") in ("town", "city") and allowed(t["lat"], t["lon"]):
        if all(abs(t["lat"] - n[2]) > 0.12 or abs(t["lon"] - n[3]) > 0.12 for n in nodes):
            nodes.append(("t_" + t["name"].lower().replace(" ", "_"), t["name"], t["lat"], t["lon"]))
zdoc = json.load(open(os.path.join(D, "landcover_zones.json")))
for o in zdoc.get("oases", []):
    if LAT0 <= o["lat"] <= LAT1 and allowed(o["lat"], o["lon"]) and "out of bounds" not in o["name"]:
        nodes.append(("o_" + o["id"], o["name"], o["lat"], o["lon"]))
for nid, nm, la, lo in [("bir_hakeim", "Bir Hakeim", 31.594, 23.480), ("fort_capuzzo", "Fort Capuzzo", 31.585, 25.050),
                        ("halfaya", "Halfaya Pass", 31.470, 25.200), ("kasserine_pass", "Kasserine Pass", 35.180, 8.680),
                        ("sidi_rezegh", "Sidi Rezegh", 31.900, 24.390), ("qaret_himeimat", "Qaret el Himeimat", 30.560, 28.840)]:
    nodes.append((nid, nm, la, lo))
nodes = [n for n in nodes if snap(n[2], n[3]) is not None]
print("nodes:", len(nodes))

# ---- graph: MST + 2 nearest links
def dkm(a, b):
    return math.hypot((a[2] - b[2]) * 110.57, (a[3] - b[3]) * 111.32 * math.cos(math.radians((a[2] + b[2]) / 2)))


cand = sorted((dkm(a, b), i, j) for i, a in enumerate(nodes) for j, b in enumerate(nodes) if i < j and dkm(a, b) < 150)
par = list(range(len(nodes)))


def find(x):
    while par[x] != x:
        par[x] = par[par[x]]
        x = par[x]
    return x


edges = set()
for d, i, j in cand:
    if find(i) != find(j):
        par[find(i)] = find(j)
        edges.add((i, j))
near = {i: [] for i in range(len(nodes))}
for d, i, j in cand:
    near[i].append((d, j))
    near[j].append((d, i))
for i, lst in near.items():
    for d, j in sorted(lst)[:2]:
        if d < 90:
            edges.add((min(i, j), max(i, j)))
print("candidate links:", len(edges))

lines = []
dropped = 0
for i, j in sorted(edges):
    a, b = nodes[i], nodes[j]
    pa, pb = snap(a[2], a[3]), snap(b[2], b[3])
    path = astar(pa, pb)
    if path is None:
        continue
    on_road = sum(1 for r, c in path if road_near[r, c]) / len(path)
    if on_road > 0.6:
        dropped += 1
        continue
    ll = [to_ll(r, c) for r, c in path]
    ll[0] = (a[2], a[3]) if cost[pa] < 1e8 and np.hypot(pa[0] - to_rc(a[2], a[3])[0], pa[1] - to_rc(a[2], a[3])[1]) < 1.5 else ll[0]
    pts = rdp([list(p) for p in ll], 0.0035)
    # light smoothing (Chaikin, one pass) so the A* grid zig-zags do not show
    if len(pts) > 2:
        sm = [pts[0]]
        for p, q in zip(pts[:-1], pts[1:]):
            sm.append([0.75 * p[0] + 0.25 * q[0], 0.75 * p[1] + 0.25 * q[1]])
            sm.append([0.25 * p[0] + 0.75 * q[0], 0.25 * p[1] + 0.75 * q[1]])
        sm.append(pts[-1])
        pts = sm
    lines.append({"k": "track", "pts": [[round(p[0], 4), round(p[1], 4)] for p in pts], "n": "%s - %s" % (a[1], b[1]), "derived": True})
print("tracks:", len(lines), "dropped as duplicate of roads:", dropped,
      "total km ~ %d" % sum(sum(dkm((0, 0, p[0][0], p[0][1]), (0, 0, p[1][0], p[1][1])) for p in zip(l["pts"][:-1], l["pts"][1:])) for l in lines))
json.dump({
    "source": "DERIVED by tools/make_desert_tracks.py (A* pistes between airfields, towns, oases and war places over the derived land cover); not surveyed, not OSM",
    "derived": True,
    "note": "Same schema as osm/roads.json; kind 'track'. Road meshing should draw these narrow (3-4 m) and pale; HeightField._load_dune_roads already reads data/desert/tracks.json to keep dunes off them.",
    "lines": lines,
}, open(os.path.join(D, "tracks.json"), "w"), separators=(",", ":"))
print("wrote data/desert/tracks.json", os.path.getsize(os.path.join(D, "tracks.json")) // 1024, "KB")
