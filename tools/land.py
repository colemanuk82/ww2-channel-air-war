"""Heightmap helpers shared by the mission importers: is a lat/lon on land, snap a point to the nearest land, and pick a
convoy direction that stays on land (a column whose midpoint is over water would be built as ships by the game)."""
import math
import os

import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0
HORIZ_COMPRESSION = 1.0       # real metres per game unit; keep equal to WorldCoords.HORIZ_COMPRESSION
_h = None


def _hm():
    global _h
    if _h is None:
        _h = cv2.imread(os.path.join(ROOT, "data", "heightmap", "region_height.png"), cv2.IMREAD_UNCHANGED)
    return _h


def elev(lat, lon):
    h = _hm()
    H, W = h.shape[:2]
    x = int((lon - LON_MIN) / (LON_MAX - LON_MIN) * (W - 1))
    y = int((LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * (H - 1))
    return float(h[min(max(y, 0), H - 1), min(max(x, 0), W - 1)]) / 65535.0 * 1000.0


def is_land(lat, lon, margin=1.0):
    return elev(lat, lon) >= margin


def snap_to_land(lat, lon, max_deg=0.12):
    """Nearest land point (>= 3 m) to (lat, lon), searching outwards in rings; returns the input if it is already land."""
    if is_land(lat, lon, 0.8):
        return lat, lon
    step = 0.004
    r = step
    while r <= max_deg:
        best = None
        for i in range(24):
            a = 2 * math.pi * i / 24
            la, lo = lat + math.cos(a) * r, lon + math.sin(a) * r / math.cos(math.radians(lat))
            if is_land(la, lo, 0.8):
                best = (la, lo)
                break
        if best:
            return best
        r += step
    return lat, lon


def land_path(lat, lon, length_deg=0.035):
    """Two points starting at (lat, lon) and heading inland: the first direction whose midpoint and end are on land."""
    dirs = [(0.3, 1.0), (-0.3, 1.0), (1.0, 0.3), (-1.0, 0.3), (0.3, -1.0), (-0.3, -1.0), (1.0, -0.3), (-1.0, -0.3), (1.0, 1.0), (-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0)]
    for dy, dx in dirs:
        n = math.hypot(dy, dx)
        end = (lat + dy / n * length_deg * 0.8, lon + dx / n * length_deg)
        mid = ((lat + end[0]) / 2, (lon + end[1]) / 2)
        if is_land(mid[0], mid[1], 0.8) and is_land(end[0], end[1], 0.8):
            return [(lat, lon), end]
    return [(lat, lon), (lat + 0.008, lon + 0.025)]


def max_speed(aircraft_id):
    import re
    p = os.path.join(ROOT, "data", "aircraft", aircraft_id + ".tres")
    try:
        return float(re.search(r"(?m)^max_speed = (.+)$", open(p, encoding="utf-8").read()).group(1))
    except Exception:  # noqa: BLE001
        return 110.0


def time_limit(route_km, aircraft_id, floor=1500):
    """Mission time limit (s) for a route of route_km real km (start -> objective -> home) flown at 75 % of top speed, with
    margin for take-off, the target run and the approach. Game distances are half the real ones (1 unit = 2 m)."""
    v = max_speed(aircraft_id) * 0.75
    t = (route_km * 1000.0 / HORIZ_COMPRESSION) / v
    return int(max(floor, math.ceil((1.35 * t + 300.0) / 60.0) * 60))
