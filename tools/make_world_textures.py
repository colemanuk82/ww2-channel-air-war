"""Procedural world surface textures (no third-party art anywhere).

Writes 20 seamlessly tileable 1024x1024 PNGs into assets/textures/world/ plus
manifest.json. Pure stdlib (struct/zlib/math/os/json/random) - the same
no-dependency approach as tools/make_aircraft_camo.py, so it runs anywhere.

  python3 tools/make_world_textures.py

Everything is generated here: value-noise/fbm made *periodic* so the tiles wrap,
analytic bond / plank / course layouts, jittered-grid Voronoi (pebbles, galvanised
spangle) and element stamping (grass blades, tree leaves, straw). Determinism: all
randomness comes from fixed seeds and coordinate hashing - there is no time, OS or
entropy input, so two runs produce byte-identical files.

Design rules kept throughout:
  * every noise octave wraps modulo its own lattice period  -> opposite edges match
  * per-pixel detail samples wrapped fields, never a raw index hash, so the grain
    stays continuous across the seam
  * periodic layouts (brick courses, tile/slate courses) are phase-shifted half a
    course so the seam falls in the middle of a course, not on a joint
  * layout periods divide 1024 (courses/planks/panels) and element stamping writes
    through modulo W                                          -> edges match
  * features that must not straddle the seam (formwork / panel lines) are offset
"""
import os
import math
import json
import random
import struct
import zlib

W = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "world")
SEED = 20240510


# ----------------------------------------------------------------------------- noise
def _hash(x, y, s=0):
    """Deterministic 24-bit value in [0,1) from integer coords + salt.

    Used only for *structural* jitter (which brick / tile / pebble this is); the
    per-pixel grain uses the sampled wrapped fields below instead."""
    h = (x * 374761393 + y * 668265263 + s * 1442695040888963407) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def vnoise2(x, y, fx, fy, seed=0):
    """Periodic value noise. Lattice indices wrap modulo (fx,fy) so the field is
    exactly periodic over the unit tile - this is what makes every tiling seamless."""
    f1 = max(1, int(fx + 0.5))
    f2 = max(1, int(fy + 0.5))
    ax, ay = x * f1, y * f2
    ix, iy = math.floor(ax), math.floor(ay)
    tx, ty = ax - ix, ay - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    ix = int(ix)
    iy = int(iy)
    x0, x1 = ix % f1, (ix + 1) % f1
    y0, y1 = iy % f2, (iy + 1) % f2
    a = _hash(x0, y0, seed)
    b = _hash(x1, y0, seed)
    c = _hash(x0, y1, seed)
    d = _hash(x1, y1, seed)
    ab = a + (b - a) * tx
    cd = c + (d - c) * tx
    return ab + (cd - ab) * ty


def fbm2(x, y, octaves, fx, fy, seed, gain=0.5):
    total, amp, norm = 0.0, 1.0, 0.0
    f1, f2 = float(fx), float(fy)
    for o in range(octaves):
        total += vnoise2(x, y, f1, f2, seed + o * 31) * amp
        norm += amp
        amp *= gain
        f1 *= 2.0
        f2 *= 2.0
    return total / norm


def fbm(x, y, octaves=4, freq=4.0, seed=0):
    return fbm2(x, y, octaves, freq, freq, seed)


def build_field(res, octaves, fx, fy, seed, gain=0.5):
    """Precompute a tileable fbm field on a res x res lattice; sample() interpolates.
    Cuts per-pixel noise cost enormously (the expensive fbm runs res^2 times)."""
    inv = 1.0 / float(res)
    out = []
    for j in range(res):
        v = j * inv
        row = [0.0] * res
        for i in range(res):
            row[i] = fbm2(i * inv, v, octaves, fx, fy, seed, gain)
        out.append(row)
    return out


def sample(g, u, v):
    """Bilinear sample of a tileable field (wraps at the edges)."""
    res = len(g)
    fu, fv = u * res, v * res
    ix, iy = math.floor(fu), math.floor(fv)
    tx, ty = fu - ix, fv - iy
    ix = int(ix)
    iy = int(iy)
    x0, x1 = ix % res, (ix + 1) % res
    y0, y1 = iy % res, (iy + 1) % res
    a = g[y0][x0]
    b = g[y0][x1]
    c = g[y1][x0]
    d = g[y1][x1]
    ab = a + (b - a) * tx
    cd = c + (d - c) * tx
    return ab + (cd - ab) * ty


def voronoi2(u, v, cells, jitter, seed):
    """Nearest of a jittered grid of sites, wrapped. Returns (dist, (cx,cy), du, dv)
    with dist measured in cell units. Tileable because site indices wrap mod cells."""
    fu, fv = u * cells, v * cells
    cu, cv = int(math.floor(fu)), int(math.floor(fv))
    best = 1e9
    bx = by = 0
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            gx, gy = cu + ox, cv + oy
            wx, wy = gx % cells, gy % cells
            sx = gx + 0.5 + (_hash(wx, wy, seed) - 0.5) * jitter
            sy = gy + 0.5 + (_hash(wx, wy, seed + 7) - 0.5) * jitter
            du, dv = fu - sx, fv - sy
            dd = du * du + dv * dv
            if dd < best:
                best = dd
                bx, by = wx, wy
    return math.sqrt(best), (bx, by), 0.0, 0.0


# ----------------------------------------------------------------------------- colour
def clamp8(v):
    if v <= 0:
        return 0
    if v >= 255:
        return 255
    return int(v + 0.5)


def mixc(c1, c2, t):
    if t < 0.0:
        t = 0.0
    elif t > 1.0:
        t = 1.0
    return (c1[0] + (c2[0] - c1[0]) * t,
            c1[1] + (c2[1] - c1[1]) * t,
            c1[2] + (c2[2] - c1[2]) * t)


def smoothstep(e0, e1, x):
    if e1 == e0:
        return 0.0 if x < e0 else 1.0
    t = (x - e0) / (e1 - e0)
    if t < 0.0:
        t = 0.0
    elif t > 1.0:
        t = 1.0
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# Fine tileable detail fields. Sampling these (rather than hashing the pixel index)
# keeps the grain continuous across the tile seam, so the edge checks are as small
# as the interior variation instead of being a hard edge.
GRAIN_A = build_field(512, 2, 170.0, 170.0, SEED + 900)   # ~6 px mottle
GRAIN_B = build_field(512, 2, 320.0, 320.0, SEED + 901)   # ~3 px grain


def g01(x, y, g=GRAIN_A):
    v = (sample(g, x, y) - 0.07) * (1.0 / 0.86)
    if v < 0.0:
        return 0.0
    if v > 1.0:
        return 1.0
    return v


# ----------------------------------------------------------------------------- image io
def new_rows():
    return [bytearray(W * 3) for _ in range(W)]


def fill(rows, col):
    r, g, b = int(col[0]), int(col[1]), int(col[2])
    pat = bytes((r, g, b)) * W
    for j in range(W):
        rows[j][:] = pat


def render_field(rows, fn):
    for j in range(W):
        v = j / float(W)
        row = rows[j]
        o = 0
        for i in range(W):
            r, g, b = fn(i, j, i / float(W), v)
            row[o] = r
            row[o + 1] = g
            row[o + 2] = b
            o += 3


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    hdr = struct.pack(">IIBBBBB", W, W, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr)
           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    return len(png)


# ============================================================================ TEXTURES

# ---- brick -------------------------------------------------------------------------
# Running bond. 16 courses of 64 px, 5 bricks per course of 204.8 px.
# Real brick 215 x 65 mm -> 5 bricks = 1.075 m wide, 16 courses = 1.04 m tall;
# tile ~= 1.06 m of wall => scale_hint 0.94. Mortar joint 7 px (~0.73 cm).
def _gen_brick(base, dark, light, mortar, seed):
    RH = 64
    BW = W / 5.0
    M = 3.5                              # half of the 7 px mortar joint
    HALF = RH // 2                       # phase shift: seam lands mid-course
    fw = build_field(64, 3, 4.0, 4.0, seed + 40)

    def f(i, j, x, y):
        course = ((j + HALF) // RH) % (W // RH)
        yl = (j + HALF) % RH
        off = (course & 1) * (BW * 0.5)
        u = (i + 0.5 + off) % W
        bx = int(u // BW)
        xl = u - bx * BW
        dx = xl if xl < BW - xl else BW - xl
        dy = yl if yl < RH - 1 - yl else RH - 1 - yl
        dm = dx if dx < dy else dy
        if dm < M:
            # recessed mortar: deepest (and darkest) in the middle of the joint
            msh = 1.0 - 0.24 * smoothstep(0.0, M, dm)
            mg = (0.93 + 0.05 * _hash(i, j, seed + 21)
                  + 0.06 * (g01(x, y, GRAIN_A) - 0.5)) * msh
            return (clamp8(mortar[0] * mg), clamp8(mortar[1] * mg), clamp8(mortar[2] * mg))
        hj = _hash(bx, course, seed)
        col = mixc(base, dark, hj * 0.85)
        col = mixc(col, light, _hash(bx, course, seed + 3) * 0.55)
        wsh = sample(fw, x, y) - 0.5
        col = (col[0] * (1 + 0.20 * wsh), col[1] * (1 + 0.20 * wsh), col[2] * (1 + 0.20 * wsh))
        sh = 1.0
        if yl < M + 3:
            sh = 1.07                       # top arris catches light
        elif yl > RH - M - 3:
            sh = 0.87                       # shadow under the brick
        gate = smoothstep(M, M + 18.0, dm)  # ->0 at the joint, 1 away from it
        grime = 0.70 + 0.30 * gate
        gn = 0.95 + 0.10 * _hash(i, j, seed + 11)   # fine brick tooth
        k = sh * grime * gn
        return (clamp8(col[0] * k), clamp8(col[1] * k), clamp8(col[2] * k))

    rows = new_rows()
    render_field(rows, f)
    return rows


def gen_brick_red():
    return _gen_brick((152, 72, 54), (116, 52, 40), (178, 98, 76), (178, 172, 158), SEED + 1)


def gen_brick_brown():
    return _gen_brick((128, 84, 60), (96, 62, 44), (156, 108, 80), (170, 162, 146), SEED + 2)


# ---- render / stucco ---------------------------------------------------------------
def _gen_render(base, damp, soot, seed, dash):
    fcoarse = build_field(48, 4, 3.0, 3.0, seed + 1)
    fmid = build_field(256, 3, 90.0, 90.0, seed + 2)   # pebbly grain (~4 px features)

    def f(i, j, x, y):
        c = sample(fcoarse, x, y)
        mid = sample(fmid, x, y)
        col = mixc(base, damp, smoothstep(0.55, 0.78, c) * 0.55)   # damp/discolouration
        col = mixc(col, soot, smoothstep(0.30, 0.10, c) * 0.35)
        g = 0.965 + 0.05 * (mid - 0.5)
        if dash:                                        # pebbledash bumps
            g *= 1.0 + 0.10 * smoothstep(0.62, 0.86, mid)
        g *= 0.96 + 0.08 * _hash(i, j, seed + 6)     # fine stucco grain
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


def gen_render_white():
    return _gen_render((238, 236, 230), (204, 205, 200), (196, 194, 190), SEED + 3, True)


def gen_render_cream():
    return _gen_render((236, 226, 200), (206, 198, 176), (198, 190, 172), SEED + 4, False)


# ---- coursed stone -----------------------------------------------------------------
def _build_courses(seed):
    rnd = random.Random(seed)
    nc = 9
    hs = [0.55 + rnd.random() for _ in range(nc)]
    tot = sum(hs)
    ys = [0]
    acc = 0.0
    for h in hs:
        acc += h / tot * W
        ys.append(int(round(acc)))
    for k in range(1, len(ys)):
        if ys[k] <= ys[k - 1]:
            ys[k] = ys[k - 1] + 1
    ys[-1] = W
    courses = []
    for k in range(nc):
        y0, y1 = ys[k], ys[k + 1]
        nb = rnd.randint(3, 5)
        ws = [0.6 + rnd.random() for _ in range(nb)]
        tw = sum(ws)
        bx = [0]
        a = 0.0
        for w in ws:
            a += w / tw * W
            bx.append(int(round(a)))
        for kk in range(1, len(bx)):
            if bx[kk] <= bx[kk - 1]:
                bx[kk] = bx[kk - 1] + 1
        bx[-1] = W
        courses.append((y0, y1, [(bx[kk], bx[kk + 1]) for kk in range(nb)]))
    return courses


def gen_stone_grey():
    courses = _build_courses(SEED + 5)
    crow = [0] * W
    for k, (y0, y1, _b) in enumerate(courses):
        for j in range(y0, y1):
            crow[j] = k
    fm = build_field(64, 4, 5.0, 5.0, SEED + 51)
    HW = 7

    def f(i, j, x, y):
        cidx = crow[j]
        y0, y1, blocks = courses[cidx]
        blk = blocks[0]
        for b in blocks:
            if b[0] <= i < b[1]:
                blk = b
                break
        dx = i - blk[0]
        if blk[1] - 1 - i < dx:
            dx = blk[1] - 1 - i
        dy = j - y0
        if y1 - 1 - j < dy:
            dy = y1 - 1 - j
        dm = dx if dx < dy else dy
        if dm < HW:
            msh = 1.0 - 0.22 * smoothstep(0.0, HW, dm)
            mg = (0.90 + 0.12 * _hash(i, j, SEED + 52)) * msh
            return (clamp8(96 * mg), clamp8(94 * mg), clamp8(88 * mg))
        bh = _hash(blk[0], y0, SEED + 53)
        col = mixc((138, 136, 130), (168, 166, 158), bh)
        col = mixc(col, (126, 124, 118), _hash(blk[0], y0, SEED + 54) * 0.5)
        m = sample(fm, x, y) - 0.5
        col = (col[0] * (1 + 0.16 * m), col[1] * (1 + 0.16 * m), col[2] * (1 + 0.16 * m))
        sh = 1.0
        if dy < 3:
            sh = 1.05
        elif dy > (y1 - y0) - 4:
            sh = 0.88
        gate = smoothstep(HW, HW + 16.0, dm)
        g = (0.72 + 0.28 * gate) * sh * (0.95 + 0.07 * g01(x + 0.4, y + 0.2, GRAIN_B))
        g *= 0.94 + 0.12 * _hash(i, j, SEED + 55)
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


# ---- concrete ----------------------------------------------------------------------
def gen_concrete():
    fm = build_field(64, 4, 5.0, 5.0, SEED + 6)
    fs = build_field(48, 3, 3.0, 3.0, SEED + 61)

    def f(i, j, x, y):
        m = sample(fm, x, y) - 0.5
        base = (152 + m * 26, 150 + m * 26, 147 + m * 24)
        g = 0.97 + 0.06 * (g01(x, y) - 0.5)
        if g01(x + 0.5, y + 0.5, GRAIN_B) < 0.02:         # pores / pitting
            g *= 0.72
        yy = (j - 64) % 256                              # formwork board lines (off-seam)
        if yy < 2:
            g *= 0.80
        elif yy < 5:
            g *= 0.94
        xx = (i - 96) % 512                              # vertical board joints
        if xx < 2:
            g *= 0.84
        # faint water staining
        g *= 1.0 - 0.06 * smoothstep(0.6, 0.9, sample(fs, x, y))
        g *= 0.95 + 0.10 * _hash(i, j, SEED + 7)         # chalky tooth
        return (clamp8(base[0] * g), clamp8(base[1] * g), clamp8(base[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


# ---- roof tiles --------------------------------------------------------------------
def _gen_rooftile(base, dark2, moss, seed, grey):
    CH = 128
    TW = 128
    SHW = 26
    HALF = CH // 2                       # phase shift: seam lands mid-course
    fc = build_field(64, 4, 4.0, 4.0, seed + 1)

    def f(i, j, x, y):
        course = ((j + HALF) // CH) % (W // CH)
        yl = (j + HALF) % CH
        off = (course & 1) * (TW // 2)
        u = (i + off) % W
        ci = u // TW
        xl = u - ci * TW
        hj = _hash(ci, course, seed + 2)
        col = mixc(base, dark2, hj * 0.9)
        prof = math.sin(math.pi * (xl + 0.5) / TW)
        shade = 0.62 + 0.62 * prof                       # barrel-tile cross-section
        if xl < 5 or xl > TW - 6:                        # interlock groove
            shade *= 0.60
        shade *= 0.50 + 0.50 * smoothstep(0.0, SHW, yl)  # shadow under the course above
        if yl >= CH - 2:                                 # dark lip
            shade *= 0.50
        w = sample(fc, x, y)
        if grey:
            col = mixc(col, (96, 98, 100), smoothstep(0.45, 0.78, w) * 0.40)
        else:
            col = mixc(col, moss, smoothstep(0.70, 0.92, w) * 0.28)
        g = shade * (0.90 + 0.20 * _hash(i, j, seed + 5))
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


def gen_roof_tile_red():
    return _gen_rooftile((150, 72, 52), (112, 50, 38), (74, 82, 56), SEED + 9, False)


def gen_roof_tile_grey():
    return _gen_rooftile((112, 112, 110), (84, 84, 84), (92, 100, 66), SEED + 10, True)


# ---- slate -------------------------------------------------------------------------
def gen_roof_slate():
    CH = 64
    SW = 128
    UNDER = 14
    HALF = CH // 2                       # phase shift: seam lands mid-course
    fc = build_field(64, 3, 5.0, 5.0, SEED + 11)

    def f(i, j, x, y):
        course = ((j + HALF) // CH) % (W // CH)
        yl = (j + HALF) % CH
        off = (course & 1) * (SW // 2)
        u = (i + off) % W
        ci = u // SW
        xl = u - ci * SW
        hj = _hash(ci, course, SEED + 12)
        col = mixc((70, 74, 82), (94, 98, 106), hj)
        col = mixc(col, (72, 78, 74), _hash(ci, course, SEED + 13) * 0.35)
        st = vnoise2(x, y, 140, 9, SEED + 14)            # cleave streaks
        shade = 0.90 + 0.22 * st
        shade *= 0.42 + 0.58 * smoothstep(0.0, UNDER, yl)  # underlap shadow
        if yl >= CH - 2:
            shade *= 0.42
        if xl < 2 or xl >= SW - 3:
            shade *= 0.72
        shade *= 0.92 + 0.16 * sample(fc, x, y)
        g = shade * (0.91 + 0.18 * _hash(i, j, SEED + 15))
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


# ---- timber ------------------------------------------------------------------------
def gen_timber():
    PLW = 128
    fgrey = build_field(48, 3, 4.0, 4.0, SEED + 16)
    fgrain = build_field(256, 3, 30.0, 2.2, SEED + 17)     # vertical streak grain
    rnd = random.Random(SEED + 18)
    knots = []
    for p in range(W // PLW):
        if rnd.random() < 0.55:
            knots.append((p, rnd.random() * W, 9 + rnd.random() * 11))   # (plank, y, radius)

    def f(i, j, x, y):
        p = i // PLW
        xl = i - p * PLW
        if xl < 3 or xl > PLW - 4:                         # shadowed gap between boards
            hj = _hash(p, 0, SEED + 19)
            return (clamp8(20 + 12 * hj), clamp8(14 + 8 * hj), clamp8(8 + 5 * hj))
        hj = _hash(p, 0, SEED + 20)
        col = mixc((146, 110, 72), (112, 80, 50), hj)
        gr = sample(fgrain, x, y)
        g = 0.86 + 0.28 * gr
        if gr < 0.40:
            g *= 0.82                                      # dark grain lines
        g *= 0.95 + 0.10 * vnoise2(x, y, 110, 7, SEED + 21)
        for (pk, ky, kr) in knots:
            if pk == p:
                dx = i - (pk * PLW + PLW // 2)             # knot sits mid-plank
                dy = abs(j - ky)
                dy = dy if dy < W - dy else W - dy
                dd = math.hypot(dx, dy)
                if dd < kr:
                    g *= 0.55 + 0.45 * (dd / kr)
        col = mixc(col, (126, 122, 114), smoothstep(0.5, 0.8, sample(fgrey, x, y)) * 0.5)
        g *= 0.94 + 0.12 * _hash(i, j, SEED + 22)          # sawn surface tooth
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


# ---- metals ------------------------------------------------------------------------
def gen_metal_dark():
    fm = build_field(64, 3, 4.0, 4.0, SEED + 23)

    def f(i, j, x, y):
        m = sample(fm, x, y) - 0.5
        base = (58 + m * 14, 60 + m * 14, 62 + m * 14)   # dark painted steel
        g = 0.90 + 0.20 * _hash(i, j, SEED + 24)
        yy = (j - 192) % 512                             # panel seam (offset off-seam)
        if yy < 2:
            g *= 0.70
        elif yy < 5:
            g *= 0.90
        if 1 <= yy <= 4 and (i % 64) < 6:                # rivet heads along the seam
            g *= 0.78 if (i % 64) in (0, 5) else 1.12
        sc = vnoise2(x, y, 130, 9, SEED + 25)            # occasional bright scratch
        if sc > 0.90:
            g *= 1.0 + 0.35 * smoothstep(0.90, 0.97, sc)
        g *= 1.0 - 0.05 * smoothstep(0.62, 0.9, sample(fm, x, (y + 0.3) % 1.0))  # streak
        return (clamp8(base[0] * g), clamp8(base[1] * g), clamp8(base[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


def gen_metal_rust():
    fbase = build_field(64, 3, 4.0, 4.0, SEED + 26)
    fbloom = build_field(96, 4, 5.0, 5.0, SEED + 27)
    fhue = build_field(64, 3, 7.0, 7.0, SEED + 28)

    def f(i, j, x, y):
        m = sample(fbase, x, y)
        col = (88 + 20 * m, 86 + 18 * m, 84 + 16 * m)    # remaining steel
        bloom = sample(fbloom, x, y)
        b1 = sample(fbloom, x, (y - 0.10) % 1.0)         # runs/stains hanging below a bloom
        b2 = sample(fbloom, x, (y - 0.24) % 1.0)
        b3 = sample(fbloom, x, (y - 0.40) % 1.0)
        run = (smoothstep(0.55, 0.80, b1) * 0.75
               + smoothstep(0.60, 0.85, b2) * 0.55
               + smoothstep(0.62, 0.88, b3) * 0.35)
        run *= 0.35 + 1.1 * vnoise2(x, y, 30, 2.2, SEED + 29)   # vertical streaking
        amt = smoothstep(0.50, 0.76, bloom) + run * 0.55
        if amt > 1.0:
            amt = 1.0
        rc = mixc((156, 78, 36), (102, 44, 20), sample(fhue, x, y))
        col = mixc(col, rc, amt)
        g = 0.93 + 0.14 * _hash(i, j, SEED + 30)         # corroded tooth
        if _hash(i, j, SEED + 31) < 0.018:               # pitting
            g *= 0.55
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


def gen_metal_bare():
    fo = build_field(32, 3, 3.0, 3.0, SEED + 32)

    def f(i, j, x, y):
        d, cid, _du, _dv = voronoi2(x, y, 8, 0.85, SEED + 33)
        tone = _hash(cid[0], cid[1], SEED + 34)
        col = mixc((158, 161, 164), (188, 190, 192), tone)   # galvanised sheet
        edge = smoothstep(0.30, 0.55, d)                     # faint crystalline facets
        shade = 1.05 - 0.16 * edge
        shade *= 0.97 + 0.06 * (sample(fo, x, y) - 0.5)      # broad oil-canning
        sc = vnoise2(x, y, 140, 10, SEED + 35)
        if sc > 0.90:
            shade *= 1.06                                    # fine polish scratches
        g = shade * (0.955 + 0.09 * _hash(i, j, SEED + 36))
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


# ---- asphalt -----------------------------------------------------------------------
def gen_asphalt():
    fc = build_field(256, 4, 7.0, 7.0, SEED + 37)     # for cracks
    fa = build_field(128, 3, 40.0, 40.0, SEED + 38)   # aggregate clusters
    fsm = build_field(48, 3, 4.0, 4.0, SEED + 39)

    def f(i, j, x, y):
        h = g01(x, y)                                  # tileable fine speckle
        col = (56, 56, 58)
        a = smoothstep(0.45, 0.85, sample(fa, x, y))
        gp = 0.6 + 0.8 * h
        col = mixc(col, (120 * gp, 116 * gp, 110 * gp), a * 0.5 * (0.4 + 0.8 * h))
        if h > 0.93:
            col = mixc(col, (150, 146, 140), 0.35)
        elif h < 0.05:
            col = mixc(col, (30, 30, 32), 0.5)
        cv = abs(sample(fc, x, y) - 0.5)
        if cv < 0.018:
            col = (col[0] * 0.50, col[1] * 0.50, col[2] * 0.50)
        elif cv < 0.030:
            col = (col[0] * 0.78, col[1] * 0.78, col[2] * 0.78)
        col = mixc(col, (64, 64, 66), smoothstep(0.55, 0.85, sample(fsm, x, y)) * 0.40)
        g = (0.96 + 0.08 * (h - 0.5)) * (0.875 + 0.25 * _hash(i, j, SEED + 41))
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


# ---- gravel ------------------------------------------------------------------------
def gen_gravel():
    def f(i, j, x, y):
        d, cid, _du, _dv = voronoi2(x, y, 16, 0.95, SEED + 42)
        r = 0.34 + 0.16 * _hash(cid[0], cid[1], SEED + 43)
        if d < r:
            t = d / r
            shade = 1.0 - 0.5 * t * t                    # centre catches light
            tone = _hash(cid[0], cid[1], SEED + 44)
            col = mixc((120, 110, 96), (178, 170, 152), tone)
            col = mixc(col, (150, 140, 124), _hash(cid[0], cid[1], SEED + 45) * 0.5)
            g = 0.72 + 0.48 * shade
            if _hash(i, j, SEED + 46) > 0.94:
                g *= 0.80                                # small surface pit
            g *= 0.92 + 0.16 * _hash(i, j, SEED + 47)
        else:
            col = (46, 42, 36)                           # interstitial shadow
            g = 1.0
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


# ---- stamped organics: grass / foliage / thatch -------------------------------------
def gen_grass():
    rows = new_rows()
    fill(rows, (30, 46, 24))
    rnd = random.Random(SEED + 101)
    for _n in range(20000):
        bx = rnd.random() * W
        by = rnd.random() * W
        L = 16.0 + rnd.random() * 40.0
        lean = (rnd.random() - 0.5) * 0.8
        curve = (rnd.random() - 0.5) * 0.5
        dry = rnd.random() < 0.09                        # occasional dry/yellow strand
        t0 = rnd.random()
        if dry:
            c0, c1, c2 = 172 + t0 * 46, 150 + t0 * 40, 80 + t0 * 50
        else:
            c0, c1, c2 = 40 + t0 * 70, 72 + t0 * 86, 26 + t0 * 44
        wide = rnd.random() < 0.45
        steps = int(L)
        for s in range(steps):
            t = s / float(steps)
            px = bx + lean * s + curve * s * s * 0.4
            py = by - s
            f = 0.5 + 0.5 * t                            # darker at the root
            xi = int(px) % W
            yi = int(py) % W
            row = rows[yi]
            o = xi * 3
            row[o] = clamp8(c0 * f)
            row[o + 1] = clamp8(c1 * f)
            row[o + 2] = clamp8(c2 * f)
            if wide:
                o2 = ((xi + 1) % W) * 3
                f2 = f * 0.72
                row[o2] = clamp8(c0 * f2)
                row[o2 + 1] = clamp8(c1 * f2)
                row[o2 + 2] = clamp8(c2 * f2)
    return rows


def _draw_leaf(rows, cx, cy, ca, sa, a, b, r, g, bl, soft=False, pe=2.0):
    """Stamp one leaf. soft=True instead darkens what is already there (a
    multiplicative contact shadow), which gives soft occlusion instead of a
    black halo; pe varies the tip pointiness so the leaves are not one shape."""
    x0 = int(cx - a - 2)
    x1 = int(cx + a + 3)
    y0 = int(cy - a - 2)
    y1 = int(cy + a + 3)
    inv_a = 1.0 / a
    inv_b = 1.0 / b
    for py in range(y0, y1):
        dy = py - cy
        row = rows[py % W]
        for px in range(x0, x1):
            dx = px - cx
            u = dx * ca + dy * sa
            v = -dx * sa + dy * ca
            uu = u * inv_a
            vv = v * inv_b
            au = uu if uu >= 0.0 else -uu
            nrm = (au ** pe) + vv * vv
            if nrm <= 1.0:
                o = (px % W) * 3
                if soft:
                    k = 1.0 - 0.62 * smoothstep(0.10, 1.0, nrm)
                    row[o] = clamp8(row[o] * k)
                    row[o + 1] = clamp8(row[o + 1] * k)
                    row[o + 2] = clamp8(row[o + 2] * k)
                else:
                    f = 1.0 - 0.30 * vv                  # lit on the upper half
                    f *= 1.0 + 0.14 * uu                 # tip catches the light
                    if abs(v) < b * 0.16:
                        f *= 1.14                        # midrib
                    f *= 1.0 - 0.20 * smoothstep(0.62, 1.0, nrm)   # soft rim
                    row[o] = clamp8(r * f)
                    row[o + 1] = clamp8(g * f)
                    row[o + 2] = clamp8(bl * f)


def gen_foliage():
    rows = new_rows()
    fill(rows, (16, 26, 14))
    rnd = random.Random(SEED + 102)
    leaves = []
    for _n in range(2600):
        leaves.append((rnd.random(), rnd.random() * W, rnd.random() * W,
                       rnd.random() * math.pi,
                       14.0 + rnd.random() * 34.0, 6.0 + rnd.random() * 14.0,
                       2.0 + rnd.random() * 1.4))
    leaves.sort(key=lambda e: e[0])            # far/dark layers first, near/bright last
    for (t, cx, cy, ang, a, b, pe) in leaves:
        ca, sa = math.cos(ang), math.sin(ang)
        ox, oy = 0.22 * a, 0.28 * a
        _draw_leaf(rows, cx + ox, cy + oy, ca, sa, a * 1.10, b * 1.14, 0, 0, 0, True)
        _draw_leaf(rows, cx, cy, ca, sa, a, b, 26 + t * 78, 52 + t * 104, 20 + t * 48,
                   False, pe)
    return rows


def gen_thatch():
    rows = new_rows()
    fill(rows, (70, 55, 30))
    fclump = build_field(64, 3, 4.0, 4.0, SEED + 104)
    rnd = random.Random(SEED + 103)
    for _n in range(15000):
        bx = rnd.random() * W
        by = rnd.random() * W
        L = 50.0 + rnd.random() * 120.0
        lean = (rnd.random() - 0.5) * 0.5
        cl = sample(fclump, bx / W, by / W)
        bri = 0.72 + 0.55 * cl                       # straw bundles of varying tone
        t0 = rnd.random()
        c0, c1, c2 = (140 + t0 * 64) * bri, (114 + t0 * 56) * bri, (60 + t0 * 44) * bri
        wide = rnd.random() < (0.35 + 0.50 * cl)
        steps = int(L)
        for s in range(steps):
            t = s / float(steps)
            px = bx + lean * s
            py = by + s                                 # straw laid downward
            f = 0.60 + 0.50 * t                         # lit toward the exposed tip
            xi = int(px) % W
            yi = int(py) % W
            row = rows[yi]
            o = xi * 3
            row[o] = clamp8(c0 * f)
            row[o + 1] = clamp8(c1 * f)
            row[o + 2] = clamp8(c2 * f)
            if wide:
                o2 = ((xi + 1) % W) * 3
                f2 = f * 0.70
                row[o2] = clamp8(c0 * f2)
                row[o2 + 1] = clamp8(c1 * f2)
                row[o2 + 2] = clamp8(c2 * f2)
    # lapped courses: thatch is laid in overlapping bundles, so darken a band under
    # each course edge and give each course its own tone (CH divides 1024 -> wraps)
    CH = 256
    HALF = CH // 2
    for j in range(W):
        course = (j + HALF) // CH
        yl = (j + HALF) % CH
        sh = 0.86 + 0.24 * _hash(3, course, SEED + 105)
        if yl < 26:
            sh *= 0.45 + 0.55 * smoothstep(0.0, 26.0, yl)
        row = rows[j]
        for i in range(0, W * 3, 3):
            row[i] = clamp8(row[i] * sh)
            row[i + 1] = clamp8(row[i + 1] * sh)
            row[i + 2] = clamp8(row[i + 2] * sh)
    return rows


# ---- sand / snow -------------------------------------------------------------------
def gen_sand():
    fp = build_field(64, 4, 6.0, 6.0, SEED + 48)         # ripple perturbation
    fb = build_field(48, 3, 4.0, 4.0, SEED + 49)         # coarse tone blotches

    def f(i, j, x, y):
        ph = 2.0 * math.pi * (14.0 * x + 3.0 * y)
        r = math.sin(ph + (sample(fp, x, y) - 0.5) * 3.0)
        col = mixc((180, 162, 116), (214, 198, 152), (r + 1.0) * 0.5)   # crests lighter
        bl = sample(fb, x, y) - 0.5
        col = (col[0] * (1 + 0.10 * bl), col[1] * (1 + 0.10 * bl), col[2] * (1 + 0.10 * bl))
        g = (0.96 + 0.06 * (g01(x, y) - 0.5)) * (0.96 + 0.08 * _hash(i, j, SEED + 50))
        if _hash(i, j, SEED + 51) > 0.992:
            g *= 0.80                                    # tiny pebble/shell
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


def gen_snow():
    fd = build_field(64, 4, 4.0, 4.0, SEED + 56)

    def f(i, j, x, y):
        d = sample(fd, x, y)
        hollow = smoothstep(0.55, 0.25, d)               # wind drift hollows
        col = mixc((236, 240, 247), (204, 214, 232), hollow * 0.70)     # faint blue shadow
        r = math.sin(2.0 * math.pi * (9.0 * x + 2.0 * y) + (d - 0.5) * 4.0)
        col = (col[0] * (0.985 + 0.025 * r), col[1] * (0.985 + 0.025 * r), col[2] * (0.985 + 0.025 * r))
        g = 0.97 + 0.06 * _hash(i, j, SEED + 57)
        if _hash(i, j, SEED + 58) > 0.995:
            g *= 1.06                                    # sparkle
        return (clamp8(col[0] * g), clamp8(col[1] * g), clamp8(col[2] * g))

    rows = new_rows()
    render_field(rows, f)
    return rows


# ============================================================================ registry
# (name, kind, roughness, metallic, scale_hint[tiles/metre], generator)
TEX = [
    ("brick_red",      "brick",    0.85, 0.00, 0.94, gen_brick_red),
    ("brick_brown",    "brick",    0.85, 0.00, 0.94, gen_brick_brown),
    ("render_white",   "render",   0.90, 0.00, 1.00, gen_render_white),
    ("render_cream",   "render",   0.90, 0.00, 1.00, gen_render_cream),
    ("stone_grey",     "stone",    0.90, 0.00, 0.50, gen_stone_grey),
    ("concrete",       "concrete", 0.85, 0.00, 0.50, gen_concrete),
    ("roof_tile_red",  "roof",     0.70, 0.00, 0.38, gen_roof_tile_red),
    ("roof_tile_grey", "roof",     0.70, 0.00, 0.38, gen_roof_tile_grey),
    ("roof_slate",     "roof",     0.45, 0.00, 0.21, gen_roof_slate),
    ("timber",         "timber",   0.75, 0.00, 0.83, gen_timber),
    ("metal_dark",     "metal",    0.45, 0.00, 0.50, gen_metal_dark),
    ("metal_rust",     "metal",    0.88, 0.15, 0.50, gen_metal_rust),
    ("metal_bare",     "metal",    0.35, 0.90, 1.00, gen_metal_bare),
    ("asphalt",        "asphalt",  0.90, 0.00, 1.00, gen_asphalt),
    ("gravel",         "gravel",   0.85, 0.00, 1.00, gen_gravel),
    ("grass",          "ground",   0.85, 0.00, 2.00, gen_grass),
    ("foliage",        "foliage",  0.60, 0.00, 1.00, gen_foliage),
    ("thatch",         "other",    0.90, 0.00, 1.00, gen_thatch),
    ("sand",           "ground",   0.80, 0.00, 1.00, gen_sand),
    ("snow",           "ground",   0.50, 0.00, 1.00, gen_snow),
]


# ============================================================================ self-check
def stats(rows):
    sr = sg = sb = 0
    mn = [255, 255, 255]
    mx = [0, 0, 0]
    for row in rows:
        rr = row[0::3]
        gg = row[1::3]
        bb = row[2::3]
        sr += sum(rr)
        sg += sum(gg)
        sb += sum(bb)
        m = min(rr)
        if m < mn[0]:
            mn[0] = m
        m = max(rr)
        if m > mx[0]:
            mx[0] = m
        m = min(gg)
        if m < mn[1]:
            mn[1] = m
        m = max(gg)
        if m > mx[1]:
            mx[1] = m
        m = min(bb)
        if m < mn[2]:
            mn[2] = m
        m = max(bb)
        if m > mx[2]:
            mx[2] = m
    n = W * W
    mean = [sr // n, sg // n, sb // n]
    det = 0
    for row in rows:
        rr = row[0::3]
        gg = row[1::3]
        bb = row[2::3]
        det += sum(abs((b2 + c2 + d2) - (a1 + b1 + c1))
                   for a1, b1, c1, b2, c2, d2 in zip(rr, gg, bb, rr[1:], gg[1:], bb[1:]))
    det = det / float(W * (W - 1) * 3)
    sx = 0
    for j in range(W):
        row = rows[j]
        sx += (abs(row[0] - row[W * 3 - 3])
               + abs(row[1] - row[W * 3 - 2])
               + abs(row[2] - row[W * 3 - 1]))
    sx = sx / float(W * 3)
    r0 = rows[0]
    rl = rows[W - 1]
    sy = sum(abs(a - b) for a, b in zip(r0, rl)) / float(W * 3)
    return mean, mn, mx, det, sx, sy


def main():
    os.makedirs(OUT, exist_ok=True)
    print("world textures ->", OUT)
    print("%-16s %-16s %-16s %-16s %8s %7s %7s %6s  %s"
          % ("name", "mean(r,g,b)", "min(r,g,b)", "max(r,g,b)", "detail", "seamX", "seamY", "s/det", "flag"))
    manifest = {}
    warn = 0
    for (name, kind, rough, metal, scale, gen) in TEX:
        rows = gen()
        path = os.path.join(OUT, name + ".png")
        size = write_png(path, rows)
        mean, mn, mx, det, sx, sy = stats(rows)
        ratio = (max(sx, sy) / det) if det > 0 else 999.0
        flag = ""
        if det < 1.5:
            flag = "FLAT-FILL!"
            warn += 1
        elif det < 3.0:
            flag = "low-detail"
        # a stochastic tile has seam ~= detail by construction; a real seam shows as
        # seam >> detail. 1.25x allows the sampling noise of a single column/row pair.
        if sx > 1.25 * det or sy > 1.25 * det:
            flag = (flag + " SEAM>>DETAIL").strip()
            warn += 1
        print("%-16s %-16s %-16s %-16s %8.3f %7.3f %7.3f %6.2f  %s"
              % (name, str(tuple(mean)), str(tuple(mn)), str(tuple(mx)), det, sx, sy, ratio, flag))
        manifest[name] = {
            "file": name + ".png",
            "size": W,
            "kind": kind,
            "mean": mean,
            "roughness": rough,
            "metallic": metal,
            "scale_hint": scale,
        }
    mpath = os.path.join(OUT, "manifest.json")
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("\n%d textures, manifest -> %s" % (len(manifest), mpath))
    print("warnings:", warn)


if __name__ == "__main__":
    main()
