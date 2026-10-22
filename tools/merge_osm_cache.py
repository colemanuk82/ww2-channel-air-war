#!/usr/bin/env python3
"""Build data/osm/<layer>.json from whatever raw Overpass tiles are already cached in tools/cache/osm,
without touching the network. Use it when `fetch_osm.py` aborts part-way (Overpass is slow for the dense
tiles): the cache keeps every tile that did arrive, so this produces the best data available right now.

Usage: python tools/merge_osm_cache.py [--layers roads,rails,coast,towns]
Missing tiles are simply skipped (that area has no roads yet); re-run fetch_osm.py later to fill them in.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_osm as fo  # noqa: E402


def merge(layer):
    cfg = fo.LAYERS[layer]
    lines, polys, towns, seen = [], [], [], set()
    got = 0
    for ti, bb in enumerate(fo.tiles()):
        cpath = os.path.join(fo.CACHE, f"{layer}_{fo.TILE_SIZE[0]}x{fo.TILE_SIZE[1]}_{ti}.json")
        if not os.path.exists(cpath):
            continue
        got += 1
        data = json.load(open(cpath))
        for el in data.get("elements", []):
            tags = el.get("tags", {})
            if cfg["geom"] == "node":
                if el["id"] in seen or "name" not in tags:
                    continue
                seen.add(el["id"])
                towns.append(dict(name=tags["name"], lat=round(el["lat"], 4), lon=round(el["lon"], 4),
                                  kind=tags.get("place", "village")))
                continue
            geom = el.get("geometry")
            if not geom:
                continue
            for run in fo.split_geom(geom):
                if cfg["geom"] == "poly":
                    continue
                k = (tags.get("waterway") or tags.get("highway") or tags.get("railway")
                     or tags.get("natural") or "x")
                # rivers: keep only streams that run a decent distance (same rule as fetch_osm.py)
                if layer == "rivers" and k == "stream" and fo.run_length_km(run) < fo.STREAM_MIN_KM:
                    continue
                rec = dict(k=k, pts=fo.r4(fo.dp(run, cfg["tol"])))
                if layer == "rivers" and tags.get("name"):
                    rec["n"] = tags["name"]
                lines.append(rec)
    # Areas whose tile is not cached yet get the synthetic city-to-city network instead, so no region is bare.
    # Rivers likewise get the hand-drawn RIVERS_FB course for any tile we have no real geometry for.
    if layer in ("roads", "rails", "rivers"):
        missing = [bb for ti, bb in enumerate(fo.tiles())
                   if not os.path.exists(os.path.join(fo.CACHE, f"{layer}_{fo.TILE_SIZE[0]}x{fo.TILE_SIZE[1]}_{ti}.json"))]
        if missing:
            if layer == "rivers":
                fb = fo.fallback_rivers()["lines"]
            else:
                fb = fo.fallback_network(layer, 11 if layer == "roads" else 23)["lines"]
            added = 0
            for ln in fb:
                pts = ln["pts"]
                mid = pts[len(pts) // 2]
                for (s0, w0, n0, e0) in missing:
                    if s0 <= mid[0] < n0 and w0 <= mid[1] < e0:
                        lines.append(ln)
                        added += 1
                        break
            print(f"[{layer}] {len(missing)} tiles missing: added {added} fallback lines for them")
    print(f"[{layer}] merged {got} cached tiles")
    if layer == "towns":
        return dict(towns=towns), got
    return dict(lines=lines), got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--layers", default="roads,rails,coast,towns")
    args = ap.parse_args()
    src_path = os.path.join(fo.OUT, "_source.json")
    src = json.load(open(src_path)) if os.path.exists(src_path) else {}
    for layer in args.layers.split(","):
        out, got = merge(layer)
        if got == 0 or not (out.get("lines") or out.get("towns")):
            print(f"[{layer}] nothing cached, keeping existing file")
            continue
        out = fo.fit_size(layer, out)
        with open(os.path.join(fo.OUT, f"{layer}.json"), "w") as f:
            json.dump(out, f, separators=(",", ":"))
        src[layer] = "overpass"
        n = len(out.get("lines", out.get("towns", [])))
        print(f"[{layer}] wrote {n} records")
    json.dump(src, open(src_path, "w"))


if __name__ == "__main__":
    main()
