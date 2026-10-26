#!/usr/bin/env python3
"""Paint the aircraft liveries (assets/liveries/<model>_<nation>.png).

Every aircraft's skin is unwrapped into one square atlas by scripts/models/livery.gd. This script fills that
atlas texel by texel, knowing where each texel sits on the airframe (tools/liveries/geo/, written by
tools/liveries/export_geo.tscn), the way a paint shop would: the camouflage scheme of the real aircraft and its
demarcation to the undersides, theatre bands, the national markings, stripes and codes (transferred from the
model's own marking geometry and code labels, so nothing is copied from anywhere else), then weathering:
exhaust soot, oil on the belly, chipped leading edges, scuffed wing roots and sun-faded paint.

Colours are the researched wartime paints (approximate sRGB of the standards: British BS 381C / MAP shades,
German RLM, US ANA / Bulletin 41). The PNGs are ordinary images: edit them by hand if you like, they are only
regenerated when this script is run.

Run:  python3 tools/liveries/paint_liveries.py [model ...]
Needs numpy and Pillow.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GEO = os.path.join(ROOT, "tools", "liveries", "geo")
OUT = os.path.join(ROOT, "assets", "liveries")
FONT = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-Bold.ttf")

# ---------------------------------------------------------------- paints (sRGB 0..1)
# RAF (BS 381C / MAP)
DARK_EARTH = (0.40, 0.33, 0.22)
DARK_GREEN = (0.25, 0.29, 0.18)
SKY = (0.73, 0.76, 0.62)
OCEAN_GREY = (0.37, 0.39, 0.40)
MED_SEA_GREY = (0.56, 0.58, 0.59)
NIGHT = (0.10, 0.10, 0.11)
# Luftwaffe (RLM)
RLM02 = (0.50, 0.49, 0.39)
RLM65 = (0.56, 0.65, 0.70)
RLM70 = (0.18, 0.23, 0.17)
RLM71 = (0.27, 0.31, 0.23)
RLM72 = (0.24, 0.27, 0.20)
RLM73 = (0.19, 0.24, 0.22)
RLM74 = (0.29, 0.32, 0.33)
RLM75 = (0.42, 0.42, 0.44)
RLM76 = (0.68, 0.72, 0.74)
RLM81 = (0.30, 0.27, 0.21)
RLM82 = (0.29, 0.35, 0.23)
RLM04 = (0.86, 0.64, 0.16)
# USAAF (ANA 613 / 603, Bulletin 41)
OLIVE_DRAB = (0.36, 0.34, 0.21)
NEUTRAL_GREY = (0.52, 0.53, 0.54)
MEDIUM_GREEN = (0.29, 0.35, 0.23)
ALUMINIUM = (0.72, 0.74, 0.75)
SILVER_DOPE = (0.70, 0.71, 0.72)
WHITE = (0.90, 0.90, 0.87)
BARE = (0.60, 0.62, 0.62)
SOOT = (0.07, 0.065, 0.06)

# ---------------------------------------------------------------- schemes
# pattern: flow (mat-edged / sprayed two-tone), splinter (straight-edged two-tone), plain, metal
# demarc: rel height on the fuselage side (-1 belly .. +1 spine) where the upper colours stop
# sides: "mottled" = Luftwaffe fighter: pale sides with soft sprayed mottles, fin painted as a side
# scale: size of the camouflage shapes (m); soft: edge width (m, 0 = masked)
BASE = dict(pattern="flow", top1=DARK_EARTH, top2=DARK_GREEN, under=SKY, demarc=-0.15, edge=0.05, soft=0.0,
            scale=1.7, sides=None, mot1=RLM02, mot2=RLM71, wear=0.6, fade=0.10, seed=1.0)
RAF_1940 = dict(BASE)
RAF_DAY_44 = dict(BASE, top1=OCEAN_GREY, top2=DARK_GREEN, under=MED_SEA_GREY)
LW_BOMBER = dict(BASE, pattern="splinter", top1=RLM70, top2=RLM71, under=RLM65, demarc=-0.05, scale=1.35)
LW_FIGHTER_40 = dict(BASE, pattern="splinter", top1=RLM71, top2=RLM02, under=RLM65, demarc=0.42, edge=0.08,
                     sides="mottled", mot1=RLM02, mot2=RLM71, scale=1.0, mottle=0.85)
USAAF_OD = dict(BASE, pattern="plain", top1=OLIVE_DRAB, top2=OLIVE_DRAB, under=NEUTRAL_GREY, demarc=-0.2,
                edge=0.12, soft=0.06, fade=0.20)

SCHEMES = {
    # RAF day fighters, summer 1940: Temperate Land Scheme (Dark Earth / Dark Green), Sky undersides
    "spitfire_raf": dict(RAF_1940, seed=1.0),
    "hurricane_raf": dict(RAF_1940, seed=2.0, wear=0.7),
    "blenheim_raf": dict(RAF_1940, seed=3.0, scale=2.4),
    # Defiant night fighter: Special Night overall
    "defiant_raf": dict(BASE, pattern="plain", top1=NIGHT, top2=NIGHT, under=NIGHT, demarc=-1.5, fade=0.05, seed=4.0),
    # 1944 Day Fighter Scheme (Ocean Grey / Dark Green over Medium Sea Grey), Sky tail band
    "typhoon_raf": dict(RAF_DAY_44, seed=5.0, sky_band=0.46, wear=0.75),
    "tempest_raf": dict(RAF_DAY_44, seed=6.0, sky_band=0.46),
    "mosquito_raf": dict(RAF_DAY_44, seed=7.0, scale=2.2),
    # Bomber Command: Dark Earth / Dark Green upper surfaces, Night sides and undersides, high wavy demarcation
    "lancaster_raf": dict(RAF_1940, under=NIGHT, demarc=0.62, edge=0.06, scale=3.0, night_sides=True, seed=8.0,
                          wear=0.7),
    # USAAF: Olive Drab over Neutral Grey; Medium Green blotches on the medium bombers' flying-surface edges
    "p47_usaaf": dict(USAAF_OD, seed=9.0, white_nose=0.62),
    # P-51B/C/D in the ETO, 1944: natural metal (the model's Olive Drab anti-glare panel is painted on the top only)
    "p51_usaaf": dict(BASE, pattern="metal", top1=ALUMINIUM, top2=ALUMINIUM, under=ALUMINIUM, demarc=-1.5,
                      fade=0.04, wear=0.4, seed=10.0),
    "b25_usaaf": dict(USAAF_OD, seed=11.0, green_blotch=1.0),
    "b26_usaaf": dict(USAAF_OD, seed=12.0, green_blotch=1.0),
    "a20_usaaf": dict(USAAF_OD, seed=13.0),
    "c47_usaaf": dict(USAAF_OD, seed=14.0),
    # P-38J/L: natural metal with an Olive Drab anti-glare panel ahead of the windscreen
    "p38_usaaf": dict(BASE, pattern="metal", top1=ALUMINIUM, top2=ALUMINIUM, under=ALUMINIUM, demarc=-1.5,
                      antiglare=OLIVE_DRAB, fade=0.04, wear=0.4, seed=15.0),
    # civil DH.89: silver dope
    "dh89_civil": dict(BASE, pattern="plain", top1=SILVER_DOPE, top2=SILVER_DOPE, under=SILVER_DOPE, demarc=-1.5,
                       fade=0.05, wear=0.3, seed=16.0),
    # Luftwaffe fighters
    "bf109_luftwaffe": dict(LW_FIGHTER_40, seed=17.0),     # yellow cowling and rudder come from the model
    "bf110_luftwaffe": dict(LW_FIGHTER_40, seed=18.0, scale=1.3, demarc=0.35),
    "fw190_luftwaffe": dict(LW_FIGHTER_40, top1=RLM74, top2=RLM75, under=RLM76, mot1=RLM74, mot2=RLM75,
                            mottle=0.7, seed=19.0),
    "me262_luftwaffe": dict(LW_FIGHTER_40, pattern="flow", top1=RLM81, top2=RLM82, under=RLM76, mot1=RLM81,
                            mot2=RLM82, soft=0.05, scale=1.3, seed=20.0),
    # Luftwaffe bombers / transports: 70 / 71 splinter over 65; the Condor in the maritime 72 / 73
    "he111_luftwaffe": dict(LW_BOMBER, seed=21.0, scale=1.8),
    "ju88_luftwaffe": dict(LW_BOMBER, seed=22.0, scale=1.6),
    "do17_luftwaffe": dict(LW_BOMBER, seed=23.0, scale=1.6),
    "ju87_luftwaffe": dict(LW_BOMBER, seed=24.0, scale=1.2, wear=0.75),
    "ju52_luftwaffe": dict(LW_BOMBER, seed=25.0, scale=1.9),
    "fw200_luftwaffe": dict(LW_BOMBER, top1=RLM72, top2=RLM73, seed=26.0, scale=2.2),
}

TONE = 0.84
FUS, WING, TAIL, FIN, NAC, OTHER = 0, 1, 2, 3, 4, 5


# ---------------------------------------------------------------- noise (same family as the game's shaders)
def fract(x):
    return x - np.floor(x)


def h13(p):
    p = fract(p * np.array([0.1031, 0.1030, 0.0973]))
    p = p + (p * (p[..., [1, 0, 2]] + 33.33)).sum(-1, keepdims=True)
    return fract((p[..., 0] + p[..., 1]) * p[..., 2])


def vn3(p):
    i = np.floor(p)
    f = p - i
    f = f * f * (3.0 - 2.0 * f)
    def h(dx, dy, dz):
        return h13(i + np.array([dx, dy, dz], dtype=np.float64))
    x0 = h(0, 0, 0) + (h(1, 0, 0) - h(0, 0, 0)) * f[..., 0]
    x1 = h(0, 1, 0) + (h(1, 1, 0) - h(0, 1, 0)) * f[..., 0]
    x2 = h(0, 0, 1) + (h(1, 0, 1) - h(0, 0, 1)) * f[..., 0]
    x3 = h(0, 1, 1) + (h(1, 1, 1) - h(0, 1, 1)) * f[..., 0]
    y0 = x0 + (x1 - x0) * f[..., 1]
    y1 = x2 + (x3 - x2) * f[..., 1]
    return y0 + (y1 - y0) * f[..., 2]


def fbm3(p, oct=4):
    w = [0.5, 0.27, 0.15, 0.08]
    s = [1.0, 2.03, 4.1, 8.3]
    o = [0.0, 3.1, 7.7, 1.3]
    r = 0.0
    for k in range(oct):
        r = r + vn3(p * s[k] + o[k]) * w[k]
    return r / sum(w[:oct]) * 0.5 + 0.25 if oct < 4 else r


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    t = np.asarray(t)
    if t.ndim == 1:
        t = t[:, None]
    return a + (np.asarray(b) - a) * t


def splinter(p, scale, seed):
    """Straight-edged two-tone: every cell of a 3D Voronoi field is one colour or the other."""
    q = p / scale + seed
    i = np.floor(q)
    best = np.full(len(p), 1e9)
    col = np.zeros(len(p))
    for dz in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                c = i + np.array([dx, dy, dz], dtype=np.float64)
                s = c + np.stack([h13(c), h13(c + 17.31), h13(c + 41.7)], -1) * 0.85
                d = ((q - s) ** 2).sum(-1)
                m = d < best
                best = np.where(m, d, best)
                col = np.where(m, (h13(c + 5.17) > 0.5).astype(np.float64), col)
    return col


def flowing(p, scale, soft, seed):
    """Large rounded two-tone shapes: warped noise cut at one level (a masked edge, or a sprayed one)."""
    q = p / scale + seed
    w = np.stack([vn3(q * 0.7 + 11.0), vn3(q * 0.7 + 23.0), vn3(q * 0.7 + 37.0)], -1) - 0.5
    n = fbm3(q + w * 1.2)
    e = max(soft / scale, 0.004) * 0.6
    return smooth(0.5 - e, 0.5 + e, n)


# ---------------------------------------------------------------- geometry
def load(key):
    meta = json.load(open(os.path.join(GEO, key + ".json")))
    sk = np.fromfile(os.path.join(GEO, key + ".skin.bin"), dtype=np.float32).reshape(-1, 9).astype(np.float64)
    dc = np.fromfile(os.path.join(GEO, key + ".decal.bin"), dtype=np.float32).reshape(-1, 10).astype(np.float64)
    return meta, sk, dc


def rasterize(sk, S):
    """Texel -> (triangle, barycentrics) by drawing every skin triangle into the atlas at its UVs."""
    T = len(sk) // 3
    tri = np.full((S, S), -1, np.int32)
    w1 = np.zeros((S, S), np.float32)
    w2 = np.zeros((S, S), np.float32)
    uv = sk[:, 6:8].reshape(T, 3, 2) * S
    for t in range(T):
        p = uv[t]
        x0 = max(int(math.floor(p[:, 0].min() - 1)), 0)
        x1 = min(int(math.ceil(p[:, 0].max() + 1)), S - 1)
        y0 = max(int(math.floor(p[:, 1].min() - 1)), 0)
        y1 = min(int(math.ceil(p[:, 1].max() + 1)), S - 1)
        if x1 < x0 or y1 < y0:
            continue
        d = (p[1, 0] - p[0, 0]) * (p[2, 1] - p[0, 1]) - (p[1, 1] - p[0, 1]) * (p[2, 0] - p[0, 0])
        if abs(d) < 1e-12:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        b1 = ((X - p[0, 0]) * (p[2, 1] - p[0, 1]) - (Y - p[0, 1]) * (p[2, 0] - p[0, 0])) / d
        b2 = ((p[1, 0] - p[0, 0]) * (Y - p[0, 1]) - (p[1, 1] - p[0, 1]) * (X - p[0, 0])) / d
        e = -1e-4
        m = (b1 >= e) & (b2 >= e) & (1.0 - b1 - b2 >= e)
        if not m.any():
            continue
        ys, xs = np.nonzero(m)
        tri[ys + y0, xs + x0] = t
        w1[ys + y0, xs + x0] = b1[m]
        w2[ys + y0, xs + x0] = b2[m]
    return tri, w1, w2


def profiles(meta, sk):
    """Fuselage centre / half height along its length, wing leading / trailing edge along the span."""
    part = sk[:, 8].astype(int)
    cls = np.array([p["class"] for p in meta["parts"]])[part]
    P = sk[:, :3]
    f = P[cls == FUS]
    if len(f) == 0:
        f = P
    z0, z1 = f[:, 2].min(), f[:, 2].max()
    zb = np.linspace(z0, z1, 64)
    cy = np.zeros(64)
    hh = np.zeros(64)
    hw = np.zeros(64)
    bi = np.clip(((f[:, 2] - z0) / max(z1 - z0, 1e-3) * 63).round().astype(int), 0, 63)
    for b in range(64):
        s = f[bi == b]
        if len(s):
            cy[b] = (s[:, 1].max() + s[:, 1].min()) * 0.5
            hh[b] = max((s[:, 1].max() - s[:, 1].min()) * 0.5, 0.02)
            hw[b] = max(np.abs(s[:, 0]).max(), 0.02)
        elif b:
            cy[b], hh[b], hw[b] = cy[b - 1], hh[b - 1], hw[b - 1]
    w = P[cls == WING]
    span = np.abs(w[:, 0]).max() if len(w) else 5.0
    xb = np.linspace(0, span, 32)
    le = np.zeros(32)
    te = np.zeros(32)
    if len(w):
        wi = np.clip((np.abs(w[:, 0]) / span * 31).round().astype(int), 0, 31)
        for b in range(32):
            s = w[wi == b]
            if len(s):
                le[b], te[b] = s[:, 2].min(), s[:, 2].max()
            elif b:
                le[b], te[b] = le[b - 1], te[b - 1]
    canopy = [p for p in meta["parts"] if p["class"] == OTHER and p["aabb"][4] > cy.mean() + hh.mean() * 0.5]
    wind_z = min(p["aabb"][2] for p in canopy) if canopy else z0 + (z1 - z0) * 0.3
    return dict(z0=z0, z1=z1, zb=zb, cy=cy, hh=hh, hw=hw, span=span, xb=xb, le=le, te=te, wind_z=wind_z)


# ---------------------------------------------------------------- painting
def paint(P, N, C, sc, pr, exh):
    """Colour of the paint at points P (normals N, part classes C)."""
    seed = sc["seed"]
    n = len(P)
    rel = (P[:, 1] - np.interp(P[:, 2], pr["zb"], pr["cy"])) / np.interp(P[:, 2], pr["zb"], pr["hh"])
    fus = (C == FUS)
    flat = (C == WING) | (C == TAIL)
    L = pr["z1"] - pr["z0"]
    top1 = np.array(sc["top1"])
    top2 = np.array(sc["top2"])
    under = np.array(sc["under"])

    # upper camouflage
    if sc["pattern"] == "splinter":
        t = splinter(P, sc["scale"], seed)
    elif sc["pattern"] == "flow":
        t = flowing(P, sc["scale"], sc["soft"], seed)
    else:
        t = np.zeros(n)
    top = mix(np.broadcast_to(top1, (n, 3)), top2, t)
    if sc["pattern"] == "metal":
        cell = np.floor(P / np.array([0.55, 0.42, 0.62]))
        top = top * (1.0 + (h13(cell + 2.0) - 0.5) * 0.10)[:, None]

    # where the upper scheme stops
    k = sc["demarc"]
    e = sc["edge"]
    wav = (vn3(P * np.array([0.0, 0.0, 1.7]) + seed) - 0.5) * (0.10 + sc["soft"] * 3.0)
    up_fus = smooth(k - e, k + e, rel + wav)
    lean = P[:, 1] * 0.0 + N[:, 1] + 0.18 * np.maximum(-N[:, 2], 0.0)
    up_flat = smooth(-0.14, 0.02, lean)
    up_nac = smooth(-0.5, -0.3, N[:, 1] + wav) if not sc.get("night_sides") else smooth(0.15, 0.35, N[:, 1] + wav)
    if k < -1.2:
        up_fus = np.ones(n)
        up_flat = np.ones(n)
        up_nac = np.ones(n)
    upper = np.where(fus, up_fus, np.where(flat, up_flat, np.where(C == NAC, up_nac, 1.0)))
    if sc.get("night_sides"):
        upper = np.where(C == FIN, 0.0, upper)        # Bomber Command fins and rudders: black
    if sc["sides"] == "mottled":
        upper = np.where(C == FIN, 0.0, upper)
        upper = np.where(C == NAC, smooth(0.25, 0.45, N[:, 1] + wav), upper)
    lower = np.broadcast_to(under, (n, 3)).copy()
    if sc["sides"] == "mottled":
        # soft sprayed mottles 15-30 cm across, densest just under the spine, sparse on the fin and lower down
        hi = np.where(C == FIN, 0.25, np.clip(rel * 0.5 + 0.5, 0.0, 1.0))
        q = P + seed
        m1 = smooth(0.62 - hi * 0.08, 0.68 - hi * 0.08, fbm3(q * 4.2 + 3.0))
        m2 = smooth(0.64 - hi * 0.08, 0.70 - hi * 0.08, fbm3(q * 3.6 + 19.0))
        zone = np.where(fus | (C == FIN) | (C == NAC), smooth(-0.55, -0.25, np.where(C == FIN, 0.5, rel)), 0.0)
        side = mix(lower, sc["mot1"], m1 * sc["mottle"] * zone)
        side = mix(side, sc["mot2"], m2 * sc["mottle"] * 0.9 * zone)
        lower = side
    col = mix(lower, top, upper)

    # US medium-green blotches scalloped along the flying-surface edges
    if sc.get("green_blotch"):
        ax = np.abs(P[:, 0])
        le = np.interp(ax, pr["xb"], pr["le"])
        te = np.interp(ax, pr["xb"], pr["te"])
        ed = np.where(C == WING, np.minimum(np.abs(P[:, 2] - le), np.abs(P[:, 2] - te)), 0.2)
        s = fbm3(P * 1.6 + seed + 4.0)
        # irregular scalloped patches about 0.3-0.6 m deep, sprayed free-hand along the leading and trailing edges
        b = (1.0 - smooth(0.30, 0.42, ed + (s - 0.5) * 0.9)) * smooth(0.40, 0.46, s) * ((C == WING) | (C == TAIL) | (C == FIN))
        col = mix(col, MEDIUM_GREEN, b * upper * sc["green_blotch"])
    # anti-glare panel on top of the nose ahead of the windscreen
    if sc.get("antiglare"):
        m = fus & (P[:, 2] < pr["wind_z"]) & (rel > 0.3)
        col = mix(col, sc["antiglare"], m * smooth(0.3, 0.45, rel))
        m2 = (C == NAC) & (N[:, 1] > 0.35) & (P[:, 2] < pr["wind_z"])
        col = mix(col, sc["antiglare"], m2 * 1.0)
    # theatre / identification colours
    if sc.get("yellow_nose"):
        col = mix(col, RLM04, fus & (P[:, 2] < pr["z0"] + sc["yellow_nose"]))
    if sc.get("white_nose"):
        col = mix(col, WHITE, fus & (P[:, 2] < pr["z0"] + sc["white_nose"]))
    if sc.get("sky_band"):
        zc = pr["z1"] - L * 0.16
        col = mix(col, SKY, fus & (np.abs(P[:, 2] - zc) < sc["sky_band"] * 0.5))

    # ---- weathering
    wear = sc["wear"]
    up = np.clip(N[:, 1], 0.0, 1.0)
    col = col * (1.0 + (fbm3(P * 0.9 + seed) - 0.5) * 2.0 * sc["fade"] * (0.4 + up))[:, None]
    # chalky sun fade on the upper surfaces
    col = mix(col, col * 1.06 + 0.01, up * 0.2 * wear)
    # exhaust soot streaked aft along the cowling
    if exh:
        s = np.zeros(n)
        for ex in exh:
            d = P - np.array(ex)
            along = d[:, 2]
            same = (np.sign(P[:, 0]) == np.sign(ex[0])) | (abs(ex[0]) < 0.05)
            spread = 0.05 + np.maximum(along, 0.0) * 0.07
            a = np.exp(-np.maximum(along, 0.0) / 1.5) * np.exp(-(d[:, 1] ** 2) / spread ** 2)
            a *= smooth(-0.06, 0.04, along) * same * (np.abs(d[:, 0]) < 0.22 + np.maximum(along, 0) * 0.08)
            s = np.maximum(s, a)
        streak = 0.75 + 0.5 * vn3(np.stack([P[:, 0] * 2.0, P[:, 1] * 30.0, P[:, 2] * 1.5], -1) + seed)
        col = mix(col, SOOT, np.clip(s * 0.8 * wear * streak, 0.0, 0.85))
    # oil and dirt dragged back along the belly
    st = vn3(np.stack([P[:, 0] * 9.0, P[:, 1] * 9.0, P[:, 2] * 0.35], -1) + seed)
    belly = fus & (rel < -0.3)
    col = col * (1.0 - smooth(0.55, 0.9, st) * 0.22 * wear * belly * np.clip(1.0 - (P[:, 2] - pr["z0"]) / L, 0.2, 1.0))[:, None]
    # chipped leading edges, scuffed walkway at the wing roots
    if sc["pattern"] != "metal":
        ax = np.abs(P[:, 0])
        le = np.interp(ax, pr["xb"], pr["le"])
        lem = (1.0 - smooth(0.02, 0.10, P[:, 2] - le)) * (C == WING)
        chip = (vn3(P * 38.0 + seed) > 0.80) * lem
        root = (C == WING) * (ax < np.interp(P[:, 2], pr["zb"], pr["hw"]) + 0.7) * (N[:, 1] > 0.4) * (P[:, 2] > le + 0.2)
        scuff = (vn3(P * 22.0 + seed + 9.0) > 0.70) * root
        col = mix(col, BARE, np.clip(chip * 0.8 + scuff * 0.3, 0.0, 1.0) * wear)
    # paint chips are judged in daylight against the sky; on the model under the game's lights the standard
    # shades read a step lighter than the real aircraft in photographs, so the whole scheme is taken down a little
    return np.clip(col * TONE, 0.0, 1.0)


# which skin parts each kind of marking may be painted on (so a wing band never lands on a nacelle beside it)
ONTO = [("DecalWing", (WING, TAIL, FIN)), ("DecalStripeFus", (FUS,)), ("DecalStripe", (WING,)), ("DecalLEStrip", (WING,)),
        ("DecalFus", (FUS,)), ("DecalFin", (FIN, FUS)), ("DecalRudder", (FIN,)), ("DecalBand", (FUS,)),
        ("DecalAntiGlare", (FUS,))]


def transfer_markings(P, N, C, col, dc, names, tol=0.05):
    """Paint the model's own marking meshes onto the skin: along each texel's normal, the outermost marking wins."""
    if len(dc) == 0:
        return col
    best = np.full(len(P), -np.inf)
    groups = dc[:, 9].astype(int)
    order = np.argsort(P[:, 2], kind="stable")
    zs = P[order, 2]
    for g in np.unique(groups):
        tris = dc[groups == g].reshape(-1, 3, 10)
        name = names[g] if g < len(names) else ""
        allow = None
        for pre, cl in ONTO:
            if name.startswith(pre):
                allow = cl
                break
        top_only = "AntiGlare" in name
        for tr in tris:
            a, b, c = tr[0, :3], tr[1, :3], tr[2, :3]
            fn = np.cross(b - a, c - a)
            ln = np.linalg.norm(fn)
            if ln < 1e-10:
                continue
            fn /= ln
            dn = tr[:, 3:6].sum(0)
            dn = dn / np.linalg.norm(dn) if np.linalg.norm(dn) > 1e-6 else fn
            if np.dot(fn, dn) < 0:
                fn = -fn
            lo = np.minimum(np.minimum(a, b), c) - tol
            hi = np.maximum(np.maximum(a, b), c) + tol
            i0, i1 = np.searchsorted(zs, [lo[2], hi[2]])
            if i1 <= i0:
                continue
            idx = order[i0:i1]
            p = P[idx]
            m = (p[:, 0] >= lo[0]) & (p[:, 0] <= hi[0]) & (p[:, 1] >= lo[1]) & (p[:, 1] <= hi[1])
            if allow is not None:
                m &= np.isin(C[idx], allow)
            if top_only:
                m &= N[idx, 1] > 0.45
            if not m.any():
                continue
            idx = idx[m]
            p = P[idx]
            nn = N[idx]
            face = nn @ dn
            den = nn @ fn
            ok = (face > 0.3) & (den > 0.2)
            t = ((a - p) @ fn) / np.where(ok, den, 1.0)
            ok &= np.abs(t) < tol
            q = p + nn * t[:, None]
            v0, v1, v2 = b - a, c - a, q - a
            d00, d01, d11 = v0 @ v0, v0 @ v1, v1 @ v1
            d20, d21 = v2 @ v0, v2 @ v1
            den2 = d00 * d11 - d01 * d01
            if abs(den2) < 1e-14:
                continue
            bv = (d11 * d20 - d01 * d21) / den2
            bw = (d00 * d21 - d01 * d20) / den2
            ok &= (bv >= -1e-4) & (bw >= -1e-4) & (bv + bw <= 1.0 + 1e-4)
            ok &= t >= best[idx] - 2e-4
            if not ok.any():
                continue
            j = idx[ok]
            best[j] = t[ok]
            col[j] = tr[0, 6:9]
    return col


def paint_labels(P, N, col, labels):
    """Codes: each Label3D rendered in its font and projected onto the fuselage side it was laid on."""
    for lb in labels:
        fs = int(lb["font_size"])
        font = ImageFont.truetype(FONT, fs)
        asc, desc = font.getmetrics()
        osz = int(lb["outline_size"])
        so = osz // 2
        w = int(math.ceil(font.getlength(lb["text"]))) + so * 2 + 4
        h = asc + desc + so * 2 + 4
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        dr = ImageDraw.Draw(img)
        fill = tuple(int(round(c * 255)) for c in lb["color"]) + (255,)
        if osz > 0:
            sf = tuple(int(round(c * 255)) for c in lb["outline"]) + (255,)
            dr.text((so + 2, so + 2), lb["text"], font=font, fill=fill, stroke_width=so, stroke_fill=sf, anchor="la")
        else:
            dr.text((2, 2), lb["text"], font=font, fill=fill, anchor="la")
        im = np.asarray(img).astype(np.float64) / 255.0
        O = np.array(lb["origin"])
        X, Y, Z = np.array(lb["x"]), np.array(lb["y"]), np.array(lb["z"])
        sx, sy = np.linalg.norm(X), np.linalg.norm(Y)
        zn = Z / np.linalg.norm(Z)
        ps = lb["pixel_size"]
        reach = max(w, h) * ps * max(sx, sy)
        d = P - O
        m = (np.abs(d) < reach).all(-1)
        idx = np.nonzero(m)[0]
        if len(idx) == 0:
            continue
        d = d[idx]
        depth = d @ zn
        facing = N[idx] @ zn
        px = (d @ (X / sx)) / sx / ps + w * 0.5
        py = h * 0.5 - (d @ (Y / sy)) / sy / ps
        ok = (np.abs(depth) < 0.18) & (facing > 0.4) & (px >= 0) & (px < w - 1) & (py >= 0) & (py < h - 1)
        if not ok.any():
            continue
        j = idx[ok]
        x, y = px[ok], py[ok]
        x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
        fx, fy = (x - x0)[:, None], (y - y0)[:, None]
        s = (im[y0, x0] * (1 - fx) * (1 - fy) + im[y0, x0 + 1] * fx * (1 - fy) +
             im[y0 + 1, x0] * (1 - fx) * fy + im[y0 + 1, x0 + 1] * fx * fy)
        a = s[:, 3:4]
        rgb = s[:, :3] / np.maximum(a, 1e-6)
        col[j] = col[j] * (1 - a) + rgb * a
    return col


def dilate(img, mask, steps):
    """Grow the painted charts outward so filtering and mipmaps never pull in the empty background."""
    img = img.copy()
    m = mask.copy()
    for _ in range(steps):
        acc = np.zeros_like(img)
        cnt = np.zeros(m.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            sm = np.roll(m, (dy, dx), (0, 1))
            acc += np.roll(img, (dy, dx), (0, 1)) * sm[..., None]
            cnt += sm
        grow = (~m) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        m = m | grow
    if (~m).any():
        img[~m] = img[m].mean(0)
    return img


def paint_one(key):
    sc = dict(SCHEMES[key])
    sc.setdefault("mottle", 0.0)
    meta, sk, dc = load(key)
    S = int(meta["size"])
    tri, w1, w2 = rasterize(sk, S)
    cov = tri >= 0
    ti = tri[cov].astype(np.int64)
    b1 = w1[cov].astype(np.float64)[:, None]
    b2 = w2[cov].astype(np.float64)[:, None]
    b0 = 1.0 - b1 - b2
    V = sk.reshape(-1, 3, 9)
    pr = profiles(meta, sk)
    cls_of = np.array([p["class"] for p in meta["parts"]])
    out = np.zeros((len(ti), 3))
    CH = 1_500_000
    for s0 in range(0, len(ti), CH):
        tt = ti[s0:s0 + CH]
        v = V[tt]
        bb0, bb1, bb2 = b0[s0:s0 + CH], b1[s0:s0 + CH], b2[s0:s0 + CH]
        P = v[:, 0, :3] * bb0 + v[:, 1, :3] * bb1 + v[:, 2, :3] * bb2
        Nn = v[:, 0, 3:6] * bb0 + v[:, 1, 3:6] * bb1 + v[:, 2, 3:6] * bb2
        Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-9)
        C = cls_of[v[:, 0, 8].astype(int)]
        c = paint(P, Nn, C, sc, pr, meta["exhausts"])
        c = transfer_markings(P, Nn, C, c, dc, meta["groups"])
        c = paint_labels(P, Nn, c, meta["labels"])
        out[s0:s0 + CH] = c
    img = np.zeros((S, S, 3))
    img[cov] = out
    img = dilate(img, cov, 10)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, key + ".png"), optimize=True)
    json.dump({"model": meta["model"], "nation": meta["nation"], "sig": meta["sig"], "size": S},
              open(os.path.join(OUT, key + ".json"), "w"), indent=1)
    imp = os.path.join(OUT, key + ".png.import")
    if not os.path.exists(imp):
        open(imp, "w").write(IMPORT % key)
    print("%s: %d px, %.1f%% of the atlas painted" % (key, S, cov.mean() * 100))


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/liveries/%s.png"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/normal_map=2
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=false
detect_3d/compress_to=0
"""


if __name__ == "__main__":
    want = sys.argv[1:]
    for f in sorted(os.listdir(GEO)):
        if not f.endswith(".json"):
            continue
        k = f[:-5]
        if want and k.split("_")[0] not in want and k not in want:
            continue
        if k not in SCHEMES:
            print("no scheme for", k)
            continue
        paint_one(k)
