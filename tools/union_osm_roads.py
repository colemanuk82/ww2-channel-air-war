#!/usr/bin/env python3
"""Union data/osm/roads.json (freshly merged from the cache) with tools/cache/roads_old_area.json (the original real
Channel-area roads) and drop duplicate lines. Run after merge_osm_cache.py when the map bounds have grown."""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
new_p = os.path.join(ROOT, "data", "osm", "roads.json")
old_p = os.path.join(ROOT, "tools", "cache", "roads_old_area.json")
new = json.load(open(new_p))["lines"]
old = json.load(open(old_p))["lines"]
seen, out = set(), []
for ln in old + new:
    pts = ln["pts"]
    key = (pts[0][0], pts[0][1], pts[-1][0], pts[-1][1], len(pts))
    if key in seen:
        continue
    seen.add(key)
    out.append(ln)
json.dump({"lines": out}, open(new_p, "w"), separators=(",", ":"))
print("roads: old %d + new %d -> %d unique lines, %.1f MB" % (len(old), len(new), len(out), os.path.getsize(new_p) / 1e6))
