#!/usr/bin/env python3
"""Why did the silhouette detector see nothing? Report the raw pixel facts for both inputs."""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

TARGETS = [
    ("render side", os.path.join(ROOT, "tools", "shots", "models", "hurricane_side.png"), None),
    ("render top", os.path.join(ROOT, "tools", "shots", "models", "hurricane_top.png"), None),
    ("drawing side crop", os.path.join(HERE, "reference", "hawker-hurricane-mkiid.gif"), (80, 40, 1900, 650)),
]

for name, path, box in TARGETS:
    print(f"\n=== {name}: {os.path.basename(path)} ===")
    if not os.path.exists(path):
        print("  MISSING"); continue
    im = Image.open(path)
    print("  mode", im.mode, "size", im.size)
    im = im.convert("RGB")
    if box:
        im = im.crop(box)
    a = np.asarray(im).astype(np.int16)
    print("  crop size", im.size)
    edges = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    vals, counts = np.unique(edges.reshape(-1, 3), axis=0, return_counts=True)
    bg = vals[counts.argmax()]
    print("  dominant edge colour", tuple(int(v) for v in bg), "share %.1f%%" % (100 * counts.max() / len(edges)))
    dist = np.abs(a - bg).sum(axis=2)
    for tol in (10, 28, 60, 120):
        print(f"    pixels differing by >{tol:3d}: {100 * (dist > tol).mean():5.2f}%")
    print("  unique colours:", len(np.unique(a.reshape(-1, 3), axis=0)))
