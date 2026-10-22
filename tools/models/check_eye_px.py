#!/usr/bin/env python3
"""What is actually in an eye render? Colour histogram, so 'black background' and 'camera inside the
structure' can be told apart instead of guessed at."""
import glob, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
for name in ("hurricane", "spitfire", "he111"):
    p = os.path.join(ROOT, "tools", "shots", "models", "%s_eye.png" % name)
    if not os.path.exists(p):
        print(name, "MISSING"); continue
    im = Image.open(p).convert("RGB")
    a = np.asarray(im)
    print("\n=== %s_eye.png  %s  mode=%s ===" % (name, im.size, Image.open(p).mode))
    vals, counts = np.unique(a.reshape(-1, 3), axis=0, return_counts=True)
    order = counts.argsort()[::-1][:5]
    for i in order:
        print("   colour %-16s %6.2f%%" % (str(tuple(int(v) for v in vals[i])), 100 * counts[i] / a.shape[0] / a.shape[1]))
    print("   unique colours:", len(vals))
    print("   brightness: min %d max %d mean %.1f" % (a.min(), a.max(), a.mean()))
    edges = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    print("   top-row sample:", [tuple(int(x) for x in px) for px in a[0][::max(1, a.shape[1] // 6)]])

# and the ortho side sheet, for comparison
p = os.path.join(ROOT, "tools", "shots", "models", "hurricane_side.png")
if os.path.exists(p):
    a = np.asarray(Image.open(p).convert("RGB"))
    vals, counts = np.unique(a.reshape(-1, 3), axis=0, return_counts=True)
    order = counts.argsort()[::-1][:3]
    print("\n=== hurricane_side.png (ortho, for comparison) ===")
    for i in order:
        print("   colour %-16s %6.2f%%" % (str(tuple(int(v) for v in vals[i])), 100 * counts[i] / a.shape[0] / a.shape[1]))
