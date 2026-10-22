#!/usr/bin/env python3
"""Fill the missing raw Overpass tiles in tools/cache/osm by splitting hard tiles into sub-tiles.

The big dense tiles (Pas-de-Calais, Flanders, Normandy) make Overpass time out on a single query. This
script retries each missing tile as 1, then 2x2, then 3x3, then 4x4 sub-queries, concatenates the elements
and stores them under the normal cache name, so `merge_osm_cache.py` / `fetch_osm.py` pick them up.

Usage: python tools/fetch_osm_fill.py [--layers roads,coast,rails,towns]
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_osm as fo  # noqa: E402


def sub_boxes(bb, n):
    s, w, nn, e = bb
    for i in range(n):
        for j in range(n):
            yield (s + (nn - s) * i / n, w + (e - w) * j / n, s + (nn - s) * (i + 1) / n, w + (e - w) * (j + 1) / n)


def fetch_split(layer, cfg, bb):
    for n in (1, 2, 3, 4, 6):
        elements, ok = [], True
        for sb in sub_boxes(bb, n):
            try:
                d = fo.overpass(fo.tile_query(layer, cfg, sb))
                elements.extend(d.get("elements", []))
                time.sleep(1.2)
            except RuntimeError as ex:
                print(f"    {layer} split {n}x{n} failed ({ex})", flush=True)
                ok = False
                break
        if ok:
            return {"elements": elements}
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--layers", default="roads,coast,rails,towns")
    ap.add_argument("--tiles", default="", help="comma list of tile indices to do, in this order (default: all missing)")
    ap.add_argument("--roads-query", default="", help="override the roads filter, e.g. way[\"highway\"~\"^(motorway|trunk)$\"] (lighter, for dense tiles)")
    args = ap.parse_args()
    if args.roads_query:
        fo.LAYERS["roads"]["q"] = [args.roads_query]
    os.makedirs(fo.CACHE, exist_ok=True)
    for layer in args.layers.split(","):
        cfg = fo.LAYERS[layer]
        all_tiles = list(fo.tiles())
        order = [int(t) for t in args.tiles.split(",") if t != ""] if args.tiles else list(range(len(all_tiles)))
        for ti in order:
            bb = all_tiles[ti]
            cpath = os.path.join(fo.CACHE, f"{layer}_{fo.TILE_SIZE[0]}x{fo.TILE_SIZE[1]}_{ti}.json")
            if os.path.exists(cpath):
                continue
            t0 = time.time()
            data = fetch_split(layer, cfg, bb)
            if data is None:
                print(f"[{layer}] tile {ti} {bb}: GAVE UP", flush=True)
                continue
            json.dump(data, open(cpath, "w"))
            print(f"[{layer}] tile {ti} {bb}: {len(data['elements'])} elements ({time.time() - t0:.0f}s)", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
