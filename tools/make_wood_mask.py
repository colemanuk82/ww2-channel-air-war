#!/usr/bin/env python3
"""Precompute the terrain shader's woodland mask (ESA WorldCover class 10 = tree cover, plus a little for class 20 scrub)
so field patchwork and hedges can be suppressed under forests. Output: data/heightmap/region_wood.png (8-bit grey, the
land-cover grid size, lightly blurred so the shader gets soft edges). Run after fetch_landcover.py:  python tools/make_wood_mask.py
then re-import in Godot (the .import must keep compress/mode=0)."""
import json
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H = os.path.join(ROOT, "data", "heightmap")
meta = json.load(open(os.path.join(H, "region_landcover.json")))
w, h = int(meta["width"]), int(meta["height"])
cls = np.fromfile(os.path.join(H, "region_landcover.bin"), dtype=np.uint8).reshape(h, w)
m = np.where(cls == 10, 255, np.where(cls == 20, 90, 0)).astype(np.uint8)
img = Image.fromarray(m, mode="L").filter(ImageFilter.GaussianBlur(0.8))
img.save(os.path.join(H, "region_wood.png"), optimize=True)
print("region_wood.png %dx%d, %.0f KB" % (w, h, os.path.getsize(os.path.join(H, "region_wood.png")) / 1024))
