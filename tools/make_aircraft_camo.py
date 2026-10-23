"""Procedural camouflage/finish textures for the aircraft skins (no third-party art anywhere).

Writes 2048x2048 PNGs into assets/models/camo/: a base paint plus the disruptive pattern, so the triplanar
shader in shaders/aircraft_pbr.gdshader can project them over the whole airframe without UV unwrapping.

  python3 tools/make_aircraft_camo.py

Add a scheme by adding an entry to SCHEMES. Everything is deterministic (fixed seed).
"""
import os
import struct
import zlib
import math


import numpy as np
from PIL import Image

W = 2048
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models", "camo")


def _lattice(n, seed):
    return np.random.RandomState(seed).rand(n, n)


def noise(freq, seed):
    """Seamlessly tiling value noise on a freq x freq lattice, sampled at WxW."""
    g = _lattice(freq, seed)
    t = np.arange(W) * (freq / float(W))
    i0 = np.floor(t).astype(int) % freq
    i1 = (i0 + 1) % freq
    f = t - np.floor(t)
    f = f * f * (3 - 2 * f)
    fx = f[None, :]
    fy = f[:, None]
    a = g[i0][:, i0]
    b = g[i0][:, i1]
    c = g[i1][:, i0]
    d = g[i1][:, i1]
    top = a + (b - a) * fx
    bot = c + (d - c) * fx
    return top + (bot - top) * fy


def fbm(freq, octaves, seed):
    tot = np.zeros((W, W))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        tot += noise(freq * (2 ** o), seed + o * 17) * amp
        norm += amp
        amp *= 0.5
    return tot / norm


def warped(field_fn, amount, seed):
    """Domain-warp by resampling with a tiling displacement field."""
    dx = (fbm(3, 3, seed + 5) - 0.5) * amount * W
    dy = (fbm(3, 3, seed + 9) - 0.5) * amount * W
    yy, xx = np.mgrid[0:W, 0:W]
    f = field_fn()
    return f[((yy + dy).astype(int)) % W, ((xx + dx).astype(int)) % W]


def voronoi_ids(cells, seed, wobble=0.0):
    """Tileable Voronoi: returns per-pixel cell id (angular patches for the Luftwaffe splinter)."""
    rs = np.random.RandomState(seed)
    pts = rs.rand(cells, 2) * W
    yy, xx = np.mgrid[0:W, 0:W]
    if wobble:
        xx = xx + (fbm(6, 3, seed + 3) - 0.5) * wobble * W
        yy = yy + (fbm(6, 3, seed + 4) - 0.5) * wobble * W
    best = np.full((W, W), 1e18)
    ids = np.zeros((W, W), dtype=np.int32)
    for k, (px, py) in enumerate(pts):
        for ox in (-W, 0, W):
            for oy in (-W, 0, W):
                d = (xx - (px + ox)) ** 2 + (yy - (py + oy)) ** 2
                m = d < best
                best[m] = d[m]
                ids[m] = k
    return ids


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# name: base colour, patch colour, optional third colour, style
SCHEMES = {
    # RAF temperate day scheme (1941-45): Dark Green / Ocean Grey, sprayed soft edges (colours as sRGB 0..1)
    "raf_day": {"base": (0.27, 0.30, 0.20), "patch": (0.37, 0.39, 0.40), "freq": 3, "edge": 0.016, "seed": 1, "style": "soft"},
    # RAF night: overall black with a faint sheen variation
    "raf_night": {"base": (0.10, 0.11, 0.11), "patch": (0.13, 0.14, 0.14), "freq": 3, "edge": 0.05, "seed": 2, "style": "soft"},
    # Luftwaffe bombers: RLM 70 Schwarzgruen / 71 Dunkelgruen angular splinter
    "lw_splinter": {"base": (0.17, 0.20, 0.16), "patch": (0.25, 0.29, 0.21), "cells": 46, "seed": 3, "style": "splinter"},
    # Luftwaffe fighters 1940-41: RLM 71 Dunkelgruen / 02 Grau splinter on the top surfaces
    "lw_fighter": {"base": (0.25, 0.29, 0.21), "patch": (0.43, 0.43, 0.36), "cells": 40, "seed": 7, "style": "splinter"},
    # Luftwaffe desert / Mediterranean
    "lw_desert": {"base": (0.55, 0.46, 0.29), "patch": (0.38, 0.33, 0.22), "freq": 3, "edge": 0.03, "seed": 4, "style": "soft"},
    # USAAF: Olive Drab 41 overall, faded unevenly
    "usaaf_od": {"base": (0.31, 0.31, 0.21), "patch": (0.35, 0.35, 0.24), "freq": 4, "edge": 0.08, "seed": 5, "style": "soft"},
    # bare metal / silver
    "bare_metal": {"base": (0.63, 0.64, 0.63), "patch": (0.55, 0.56, 0.57), "freq": 4, "edge": 0.10, "seed": 6, "style": "panels"},
}


def build(name, sp):
    seed = sp["seed"]
    if sp["style"] == "splinter":
        ids = voronoi_ids(sp["cells"], seed, 0.04)
        r = np.random.RandomState(seed + 11).rand(sp["cells"])
        sel = r[ids]
        base = np.array(sp["base"]); patch = np.array(sp["patch"]); third = np.array(sp.get("third", sp["patch"]))
        col = np.where((sel < 0.5)[..., None], base, np.where((sel < 0.82)[..., None], patch, third))
        # soften only the cell border by one pixel so mips stay clean
        col = col.astype(np.float64)
    else:
        n = warped(lambda: fbm(sp["freq"], 4, seed), 0.35, seed)
        # fine detail breaks the edge so it looks sprayed rather than a smooth blob
        n = n + (fbm(32, 3, seed + 40) - 0.5) * 0.06
        t = sstep(0.5 - sp["edge"], 0.5 + sp["edge"], n)
        col = np.array(sp["base"])[None, None, :] + (np.array(sp["patch"]) - np.array(sp["base"]))[None, None, :] * t[..., None]
        if sp["style"] == "panels":
            # bare-metal sheet panels: a grid of slightly differing tones
            g = 16
            yy, xx = np.mgrid[0:W, 0:W]
            pid = (xx * g // W) * 31 + (yy * g // W) * 17
            tone = (np.random.RandomState(seed + 2).rand(64)[pid % 64] - 0.5) * 0.06
            col = col + tone[..., None]
    # paint grain + subtle large-scale fade, all tileable
    grain = (fbm(256, 2, seed + 70) - 0.5) * 0.05
    mottling = (fbm(8, 3, seed + 80) - 0.5) * 0.10
    col = col * (1.0 + grain + mottling)[..., None]
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name + ".png")
    img.save(p, optimize=True)
    print("  %-14s %s (%.0f KB)" % (name, p, os.path.getsize(p) / 1024.0))


print("camo textures ->", OUT)
for nm, sp in SCHEMES.items():
    build(nm, sp)
