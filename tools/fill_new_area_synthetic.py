#!/usr/bin/env python3
"""Offline fallback for the part of the map added when the bounds grew: keep the original real roads
(tools/cache/roads_old_area.json) and add the synthetic road/rail network that links the cities of locations.json
(fetch_osm.py's fallback_network) for lines that lie outside the original bounds. Rails are the synthetic network
everywhere (they already were). Use when Overpass is too slow for fetch_osm_new_area.py."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_osm as fo  # noqa: E402

ROOT = fo.ROOT
OLD = (48.9, -4.6, 51.7, 4.7)


def outside_old(line):
    la = sum(p[0] for p in line["pts"]) / len(line["pts"])
    lo = sum(p[1] for p in line["pts"]) / len(line["pts"])
    return not (OLD[0] <= la <= OLD[2] and OLD[1] <= lo <= OLD[3])


old = json.load(open(os.path.join(ROOT, "tools", "cache", "roads_old_area.json")))["lines"]
syn = fo.fallback_network("roads", 11)["lines"]
add = [l for l in syn if outside_old(l)]
json.dump(dict(lines=old + add), open(os.path.join(ROOT, "data", "osm", "roads.json"), "w"), separators=(",", ":"))
rails = fo.fallback_network("rails", 23)
json.dump(rails, open(os.path.join(ROOT, "data", "osm", "rails.json"), "w"), separators=(",", ":"))
print("roads: %d real + %d synthetic (new area); rails: %d synthetic" % (len(old), len(add), len(rails["lines"])))
