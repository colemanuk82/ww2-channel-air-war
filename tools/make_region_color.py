#!/usr/bin/env python3
"""Paint a map picture for a region that has no satellite imagery (the Desert map).

Output: <data-dir>/region_mapview.png  (RGB, north-up, equirectangular, same bounds as region_meta.json; Channel's
region_color.png convention). Used by the HUD minimap / map screen, bombsight chart, flight planner and mission editor
through WorldCoords.map_picture_path(). It is deliberately NOT named region_color.png: terrain_chunk_manager drapes
region_color.png over the terrain, which would switch off the desert ground shader.

Inputs (same folder): region_height.png (16-bit), region_meta.json, region_landcover.bin/.json, region_coast.png
(255 = land, soft edge), region_urban.png (soft town mask).
Sea = blue with shallow-water lightening near the coast; land = land-cover class colour + hillshade.

  python tools/make_region_color.py --data-dir data/desert [--width 6144] [--out name.png]
"""
import argparse, json, os
import numpy as np
from PIL import Image, ImageFilter

PAL = {  # class id -> RGB
    0: (36, 74, 112),
    10: (86, 104, 62), 20: (146, 142, 92), 30: (160, 156, 104), 40: (150, 150, 86), 50: (150, 140, 128),
    60: (206, 184, 140), 80: (60, 100, 140), 90: (110, 130, 96),
    110: (232, 214, 172), 111: (206, 196, 168), 112: (196, 172, 130), 113: (190, 156, 112), 114: (150, 126, 100),
    115: (224, 190, 130), 116: (232, 228, 214), 117: (176, 150, 104), 118: (206, 192, 164), 119: (84, 74, 68),
    120: (70, 112, 58), 121: (104, 124, 66),
}


def load_gray(path, w, h, mode):
    im = Image.open(path)
    if mode == "F":
        im = im.convert("F")
    return np.asarray(im.resize((w, h), Image.BILINEAR), dtype=np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default="data/desert")
    ap.add_argument("--width", type=int, default=6144)
    ap.add_argument("--out", default="region_mapview.png")
    ap.add_argument("--relief", type=float, default=5.0, help="vertical exaggeration of the hillshade")
    a = ap.parse_args()
    d = a.data_dir
    meta = json.load(open(os.path.join(d, "region_meta.json")))
    W0, H0 = meta["width"], meta["height"]
    maxe = float(meta.get("max_elev_m", 3000))
    W = a.width
    H = int(round(W * H0 / W0))
    lat_mid = 0.5 * (meta["lat_min"] + meta["lat_max"])
    mx = (meta["lon_max"] - meta["lon_min"]) * 111320.0 * np.cos(np.radians(lat_mid)) / W
    my = (meta["lat_max"] - meta["lat_min"]) * 110574.0 / H

    lc = np.fromfile(os.path.join(d, "region_landcover.bin"), np.uint8).reshape(H0, W0)
    cls = np.asarray(Image.fromarray(lc).resize((W, H), Image.NEAREST))
    elev = load_gray(os.path.join(d, "region_height.png"), W, H, "F") * (maxe / 65535.0)
    land = load_gray(os.path.join(d, "region_coast.png"), W, H, "L") / 255.0
    urban = load_gray(os.path.join(d, "region_urban.png"), W, H, "L") / 255.0

    rgb = np.zeros((H, W, 3), np.float32)
    for k, c in PAL.items():
        rgb[cls == k] = c
    rgb[~np.isin(cls, list(PAL))] = PAL[60]
    # soften class edges slightly
    rgb = np.asarray(Image.fromarray(rgb.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32)

    # elevation tint: higher ground a little darker / redder
    t = np.clip(elev / 1200.0, 0, 1)[..., None]
    rgb = rgb * (1.0 - 0.18 * t) + np.array([120, 90, 64], np.float32) * (0.18 * t)

    # hillshade, light from NW
    e = elev
    gy, gx = np.gradient(e, my, mx)
    nx, ny, nz = -gx * a.relief, gy * a.relief, np.ones_like(e)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    L = np.array([-0.5, 0.5, 0.7]); L = L / np.linalg.norm(L)
    sh = (nx * L[0] + ny * L[1] + nz * L[2]) / n
    sh = np.clip(sh / L[2], 0.0, 1.6)
    shade = (0.45 + 0.55 * sh)[..., None]
    rgb = rgb * shade

    # towns
    um = np.clip((urban - 0.35) / 0.3, 0, 1)[..., None]
    rgb = rgb * (1 - um) + np.array([178, 162, 140], np.float32) * (0.85 + 0.15 * shade) * um

    # sea: deeper colour with distance from coast, shallow turquoise near it
    m = Image.fromarray((land * 255).astype(np.uint8))
    near = np.asarray(m.filter(ImageFilter.GaussianBlur(max(2, W / 600))), np.float32) / 255.0
    far = np.asarray(m.filter(ImageFilter.GaussianBlur(max(6, W / 120))), np.float32) / 255.0
    sea = np.array([30, 66, 108], np.float32) + np.array([20, 40, 36], np.float32) * np.clip(far * 2.2, 0, 1)[..., None] \
        + np.array([22, 36, 24], np.float32) * np.clip(near * 1.6, 0, 1)[..., None]
    l3 = land[..., None]
    out = rgb * l3 + sea * (1 - l3)
    Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGB").save(os.path.join(d, a.out), optimize=True)
    print("wrote", os.path.join(d, a.out), W, H)


if __name__ == "__main__":
    main()
