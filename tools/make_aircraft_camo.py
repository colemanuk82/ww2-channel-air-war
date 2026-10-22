"""Procedural camouflage/finish textures for the aircraft skins (no third-party art anywhere).

Writes 1024x1024 PNGs into assets/models/camo/: a base paint plus the disruptive pattern, so the triplanar
shader in shaders/aircraft_pbr.gdshader can project them over the whole airframe without UV unwrapping.

  python3 tools/make_aircraft_camo.py

Add a scheme by adding an entry to SCHEMES. Everything is deterministic (fixed seed).
"""
import os
import struct
import zlib
import math

W = 1024
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models", "camo")


def _hash(x, y, s=0):
    h = (x * 374761393 + y * 668265263 + s * 1442695040888963407) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def value_noise(x, y, freq, seed=0):
    fx, fy = x * freq, y * freq
    ix, iy = math.floor(fx), math.floor(fy)
    tx, ty = fx - ix, fy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a = _hash(ix, iy, seed)
    b = _hash(ix + 1, iy, seed)
    c = _hash(ix, iy + 1, seed)
    d = _hash(ix + 1, iy + 1, seed)
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty


def fbm(x, y, octaves=5, freq=3.0, seed=0):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total += value_noise(x, y, freq * (2 ** o), seed + o * 17) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def warp(x, y, amount=0.35, seed=0):
    return (x + (fbm(x, y, 3, 1.7, seed + 5) - 0.5) * amount,
            y + (fbm(x, y, 3, 1.9, seed + 9) - 0.5) * amount)


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    hdr = struct.pack(">IIBBBBB", W, W, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


SCHEMES = {
    # RAF day fighter: dark green / ocean grey disruptive, soft edges
    "raf_day": {"base": (0.19, 0.25, 0.13), "patch": (0.33, 0.37, 0.40), "freq": 2.2, "hard": 0.22, "seed": 1},
    # RAF night fighter / intruder: overall dark green, low contrast
    "raf_night": {"base": (0.15, 0.18, 0.12), "patch": (0.20, 0.24, 0.15), "freq": 2.6, "hard": 0.35, "seed": 2},
    # Luftwaffe: RLM 70/71 splinter-ish - two dark greens with angular edges
    "lw_splinter": {"base": (0.16, 0.19, 0.14), "patch": (0.24, 0.28, 0.17), "freq": 6.0, "hard": 0.9, "seed": 3},
    # Luftwaffe desert / Mediterranean
    "lw_desert": {"base": (0.52, 0.44, 0.28), "patch": (0.40, 0.35, 0.24), "freq": 3.0, "hard": 0.3, "seed": 4},
    # USAAF: olive drab over neutral grey
    "usaaf_od": {"base": (0.25, 0.26, 0.17), "patch": (0.29, 0.30, 0.20), "freq": 2.4, "hard": 0.25, "seed": 5},
    # bare metal / silver
    "bare_metal": {"base": (0.62, 0.63, 0.62), "patch": (0.56, 0.57, 0.58), "freq": 2.0, "hard": 0.2, "seed": 6},
}


def build(name, spec):
    rows = []
    for j in range(W):
        y = j / float(W)
        row = []
        for i in range(W):
            x = i / float(W)
            wx, wy = warp(x, y, 0.45, spec["seed"]) if spec["hard"] < 0.5 else (x, y)
            # 3 octaves keeps the patches reading as patches; a 5-octave average washes them into one tone
            n = fbm(wx, wy, 3, spec["freq"], spec["seed"])
            if spec["hard"] >= 0.5:
                # angular patches (splinter): quantise the noise into straight-edged bands
                cells = 14
                cx, cy = int(x * cells), int(y * cells)
                n = (n * 0.45) + 0.55 * _hash(cx, cy, spec["seed"] + 3)
            band = 0.10 + spec["hard"] * 0.15
            t = smoothstep(0.5 - band, 0.5 + band, n)
            c = mix(spec["base"], spec["patch"], t)
            # gentle low-frequency unevenness only: per-texel noise gets magnified into white speckle
            # all over the airframe once the texture is projected in object space
            g = 0.96 + 0.07 * value_noise(x, y, 3.5, 7)
            row.extend(int(max(0.0, min(1.0, ch * g)) * 255) for ch in c)
        rows.append(row)
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name + ".png")
    write_png(p, rows)
    print("  %-14s %s (%.0f KB)" % (name, p, os.path.getsize(p) / 1024.0))


print("camo textures ->", OUT)
for nm, sp in SCHEMES.items():
    build(nm, sp)
