#!/usr/bin/env python3
"""Precompute the terrain shader's built-up mask (ESA WorldCover class 50) so the game does not rebuild it on every load.
Output: data/heightmap/region_urban.png (8-bit grey, 2x the land-cover grid, bicubic like LandCover.urban_mask()).
Run after fetch_landcover.py:  python tools/make_urban_mask.py   then re-import in Godot (the .import must keep compress/mode=0)."""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H = os.path.join(ROOT, "data", "heightmap")
meta = json.load(open(os.path.join(H, "region_landcover.json")))
w, h = int(meta["width"]), int(meta["height"])
cls = np.fromfile(os.path.join(H, "region_landcover.bin"), dtype=np.uint8).reshape(h, w)
mask = Image.fromarray(((cls == 50) * 255).astype(np.uint8), mode="L").resize((w * 2, h * 2), Image.BICUBIC)
mask.save(os.path.join(H, "region_urban.png"), optimize=True)
print("region_urban.png %dx%d, %.0f KB" % (w * 2, h * 2, os.path.getsize(os.path.join(H, "region_urban.png")) / 1024))
