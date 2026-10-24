#!/usr/bin/env python3
"""Bake the farming-region map (data/regions_1940.json -> data/heightmap/region_types.png).

RGBA, one channel per region type, 0..255 membership, blurred so the edges blend over a couple of km:
  R = bocage (small hedged enclosures: Normandy, the Cotentin, the Pays d'Auge)
  G = open field (big hedgeless arable / chalk downland: Picardy, Artois, Caux, Vexin, Champagne, the Caen plain,
      Salisbury Plain and the downs)
  B = polder / fen (long drained parcels with ditches: Holland, Zeeland, the Flemish coast, the Fens)
  A = Weald (small fields, many shaws and woods: Kent, Sussex, Surrey)

The image covers WorldCoords bounds (lat 48.9..53.0, lon -4.6..9.0) in plate carree, the same rect as region_color.png,
so the terrain shader samples it with map_rect and Scatter (CPU) with the same mapping.

Usage: python tools/bake_regions.py   (writes the PNG and prints a hash that tests compare)
"""
import json, hashlib, os, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'data', 'regions_1940.json')
OUT = os.path.join(ROOT, 'data', 'heightmap', 'region_types.png')
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0
W, H = 1024, 512
CH = {"bocage": 0, "open": 1, "polder": 2, "weald": 3}


def px(lat, lon):
    return ((lon - LON_MIN) / (LON_MAX - LON_MIN) * W, (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * H)


def main():
    d = json.load(open(SRC, encoding='utf-8'))
    layers = [Image.new('L', (W, H), 0) for _ in range(4)]
    draws = [ImageDraw.Draw(l) for l in layers]
    for r in d['regions']:
        c = CH[r['type']]
        draws[c].polygon([px(p[0], p[1]) for p in r['poly']], fill=255)
    layers = [l.filter(ImageFilter.GaussianBlur(1.6)) for l in layers]
    img = Image.merge('RGBA', layers)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, optimize=True)
    h = hashlib.sha1(img.tobytes()).hexdigest()[:12]
    print('baked', OUT, img.size, 'hash', h)
    meta = os.path.join(ROOT, 'data', 'heightmap', 'region_types.json')
    json.dump({"lat_min": LAT_MIN, "lat_max": LAT_MAX, "lon_min": LON_MIN, "lon_max": LON_MAX, "w": W, "h": H, "hash": h,
               "channels": ["bocage", "open", "polder", "weald"], "source": "data/regions_1940.json"}, open(meta, 'w'), indent=1)


if __name__ == '__main__':
    main()
