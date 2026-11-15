"""Airfield grass detail texture - the tiling sheet shaders/grass_field.gdshader lays over a grass landing ground.

Writes one seamlessly tileable 1024x1024 8-bit RGB PNG to assets/textures/airfield_grass/airfield_grass.png.
It is generated here from seeded noise (nothing is copied from anywhere), so it is our own work.
Channels, all centred on 0.5 so the shader's `1.0 + (t - 0.5) * k` grade is neutral on average and the
mipmaps fade to "no change" with distance:

  R  blades:  short thin strokes leaning a few degrees either side of one direction (mown turf seen from above)
  G  clumps:  tufts a hand to a forearm across
  B  patches: slow lusher / thinner sward half a metre across

Every layer is white noise filtered in the frequency domain, so it is periodic over the tile by construction:
opposite edges match exactly. Deterministic (fixed seed): two runs write the same file.

  python tools/make_grass_texture.py [--out PATH] [--size N]        (needs numpy and Pillow, as tools/liveries does)
"""
import argparse
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "assets", "textures", "airfield_grass", "airfield_grass.png")
SEED = 19400815


def _filtered(rng, n, sig_long, sig_short, angle_deg):
    """White noise blurred by a Gaussian sig_long px along `angle_deg` and sig_short px across it (periodic)."""
    f = np.fft.fft2(rng.standard_normal((n, n)))
    k = np.fft.fftfreq(n) * 2.0 * np.pi
    kx, ky = np.meshgrid(k, k)
    a = np.deg2rad(angle_deg)
    ka = kx * np.cos(a) + ky * np.sin(a)
    kb = -kx * np.sin(a) + ky * np.cos(a)
    out = np.real(np.fft.ifft2(f * np.exp(-0.5 * ((ka * sig_long) ** 2 + (kb * sig_short) ** 2))))
    return out / (out.std() + 1e-9)


def _unit(x, spread):
    """Centre on 0.5 with `spread` standard deviations filling the 0..1 range (soft clip)."""
    x = (x - x.mean()) / (x.std() + 1e-9)
    return 0.5 + 0.5 * np.tanh(x / spread)


def build(n):
    rng = np.random.default_rng(SEED)
    s = n / 1024.0
    # blades: strokes at several leans; the brightest stroke wins at each pixel, so blades cross instead of blurring
    blades = None
    for ang in (90.0, 78.0, 102.0, 66.0, 114.0, 90.0, 84.0, 96.0):
        layer = _filtered(rng, n, rng.uniform(7.0, 13.0) * s, rng.uniform(0.75, 1.1) * s, ang)
        blades = layer if blades is None else np.maximum(blades, layer)
    blades = blades - 0.35 * _filtered(rng, n, 2.0 * s, 2.0 * s, 0.0)      # dark gaps between the blades
    clumps = _filtered(rng, n, 22.0 * s, 16.0 * s, 80.0) + 0.6 * _filtered(rng, n, 9.0 * s, 7.0 * s, 100.0)
    patches = _filtered(rng, n, 150.0 * s, 150.0 * s, 0.0) + 0.5 * _filtered(rng, n, 60.0 * s, 60.0 * s, 0.0)
    rgb = np.stack([_unit(blades, 1.6), _unit(clumps, 1.5), _unit(patches, 1.5)], axis=-1)
    return np.clip(np.rint(rgb * 255.0), 0, 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    img = build(a.size)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    Image.fromarray(img, "RGB").save(a.out, optimize=True)
    print("wrote %s  %dx%d  mean %s" % (a.out, a.size, a.size, np.round(img.reshape(-1, 3).mean(axis=0) / 255.0, 3)))


if __name__ == "__main__":
    main()
