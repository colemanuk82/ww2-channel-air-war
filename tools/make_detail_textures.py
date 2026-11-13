"""Close-range terrain detail texture - the single texture file terrain.gdshader uses.

Writes one seamlessly tileable 256x256 8-bit RGB PNG into
assets/textures/terrain_detail/terrain_detail.png for the shader's close-range
micro detail (P2).  Channels (all centred on 0.5 so the shader's
`1.0 + (dt - 0.5) * k` grade stays neutral on average):

  R  turf / grass micro-grain: fine blade speckle over clump mottling
  G  soil / plough grain:      clod domes with furrow gaps + fine tilth
  B  micro height:             turf tufts + the same soil clods (dFdx bump)

Pure stdlib (argparse/math/os/struct/zlib/hashlib) - the same no-dependency
approach as tools/make_world_textures.py, and the same design rules:

  * every noise octave wraps modulo its own lattice period -> opposite edges
    match (value noise sampled with the coordinates mod the tile period, i.e.
    on a torus)
  * the clod Voronoi measures distances from cell-LOCAL site positions, so a
    site's images across the seam are bit-identical, not merely similar
  * per-pixel detail samples wrapped fields, never a raw pixel-index hash, so
    the grain stays continuous across the seam

Tileability is self-checked and the script aborts on failure: the fields are
sampled on a (size+1) x (size+1) grid (u = i / size for i = 0..size) and
value(0) must equal value(size) EXACTLY - bit-for-bit after 8-bit quantisation
- on every row and column.  That is the torus statement of "first row ==
last row": the written PNG's own row 0 and row 255 are adjacent samples of one
continuous field, as in any seamless tile (duplicating them would paint a
doubled feature line along the seam).  A seam-vs-interior statistic on the
finished image is asserted too.

Determinism: every random-looking number comes from fixed seeds and coordinate
hashing - there is no time, OS or entropy input - so two runs write
byte-identical files.

  python tools/make_detail_textures.py [--out PATH] [--size N] [--seed N]
"""
import argparse
import hashlib
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "assets", "textures", "terrain_detail", "terrain_detail.png")
DEFAULT_SIZE = 256
SEED = 19440606


# ----------------------------------------------------------------------------- noise
def _hash(x, y, s=0):
    """Deterministic 24-bit value in [0,1) from integer lattice coords + salt."""
    h = (x * 374761393 + y * 668265263 + s * 1442695040888963407) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def vnoise2(x, y, fx, fy, seed=0):
    """Periodic value noise. Lattice indices wrap modulo (fx, fy) so the field is
    exactly periodic over the unit tile - this is what makes the texture seamless."""
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


def clod_field(u, v, cells, jitter, seed):
    """Wrapped jittered-cell clod height in [0,1]: a dome over each clod, furrow
    (0) between them.  Site positions are kept cell-local and distances are
    measured from the cell origin as (fu - gx) - lx, so the value at u and u+1
    is bit-identical and the field tiles exactly across the seam."""
    fu, fv = u * cells, v * cells
    cu, cv = int(math.floor(fu)), int(math.floor(fv))
    best = 1e9
    rad = 0.38
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            gx, gy = cu + ox, cv + oy
            wx, wy = gx % cells, gy % cells
            lx = 0.5 + (_hash(wx, wy, seed) - 0.5) * jitter
            ly = 0.5 + (_hash(wx, wy, seed + 7) - 0.5) * jitter
            du = (fu - gx) - lx
            dv = (fv - gy) - ly
            dd = du * du + dv * dv
            if dd < best:
                best = dd
                rad = 0.30 + 0.16 * _hash(wx, wy, seed + 17)
    d = math.sqrt(best)
    if d >= rad:
        return 0.0
    t = d / rad
    return 1.0 - t * t


def clamp01(v):
    if v < 0.0:
        return 0.0
    if v > 1.0:
        return 1.0
    return v


def clamp8(v):
    if v <= 0:
        return 0
    if v >= 255:
        return 255
    return int(v + 0.5)


# ------------------------------------------------------------------------------ texel
def sample_px(u, v, seed):
    """One texel's (R, G, B) detail values at a point on the unit torus."""
    # ---- R: turf / grass micro-grain -----------------------------------------
    clump = fbm2(u, v, 2, 10.0, 10.0, seed + 101)          # sward clump mottling (~12 cm)
    sp1 = vnoise2(u, v, 64.0, 64.0, seed + 102)            # fine blade speckle (~4 px = 2 cm)
    sp2 = vnoise2(u, v, 40.0, 40.0, seed + 103)            # coarser speckle (~6 px)
    sp1 = clamp01((sp1 - 0.5) * 1.9 + 0.5)                 # sharpen into dark / light blades
    turf = 0.5 + (clump - 0.5) * 0.50 + (sp1 - 0.5) * 0.36 + (sp2 - 0.5) * 0.22
    # ---- G: soil / plough grain ----------------------------------------------
    clod = clod_field(u, v, 28, 0.7, seed + 111)           # clod domes with furrow gaps
    tilth = vnoise2(u, v, 56.0, 56.0, seed + 112)          # fine tilth (~4-5 px)
    rip = vnoise2(u, v, 9.0, 84.0, seed + 113)             # faint drill-direction ripple
    rip = clamp01((rip - 0.5) * 1.8 + 0.5)
    soil = 0.5 + (clod - 0.24) * 0.60 + (tilth - 0.5) * 0.28 + (rip - 0.5) * 0.12
    # ---- B: micro height (turf tufts + the same soil clods as G) -------------
    tuft = fbm2(u, v, 2, 12.0, 12.0, seed + 121)           # turf mounds (~10 cm and up)
    hgt = 0.5 + (tuft - 0.5) * 0.50 + (clod - 0.24) * 0.62 + (tilth - 0.5) * 0.18
    return (clamp01(turf), clamp01(soil), clamp01(hgt))


def make_grid(size, seed):
    """Sample (size+1) x (size+1): grid[j][i] for i, j = 0..size.  The extra row
    and column exist only to prove the wrap (value at 0 == value at size)."""
    grid = []
    for j in range(size + 1):
        v = j / float(size)
        row = []
        for i in range(size + 1):
            row.append(sample_px(i / float(size), v, seed))
        grid.append(row)
    return grid


def _snap(b):
    """Snap an 8-bit value to the nearest multiple of 4 (64 levels): visually
    identical on stochastic grain, but it cuts the compressed size by ~30% and
    keeps the PNG inside its 100 KB budget."""
    q = (b + 2) & 0xFC
    return 252 if q > 252 else q


def to_rows(grid, size):
    """Quantise the first size x size texels to 8-bit RGB scanlines."""
    rows = []
    for j in range(size):
        row = bytearray(size * 3)
        for i in range(size):
            r, g, b = grid[j][i]
            o = i * 3
            row[o] = _snap(clamp8(r * 255.0))
            row[o + 1] = _snap(clamp8(g * 255.0))
            row[o + 2] = _snap(clamp8(b * 255.0))
        rows.append(row)
    return rows


# ------------------------------------------------------------------------------ checks
def check_tileable(grid, size):
    """Torus proof: value(0) == value(size) bit-for-bit (also after 8-bit
    quantisation) along every row (u wrap) and every column (v wrap)."""
    worst = 0.0
    for j in range(size):
        for ch in range(3):
            d = abs(grid[j][0][ch] - grid[j][size][ch])
            if d > worst:
                worst = d
            assert d <= 1e-12, "u-wrap mismatch at row %d channel %d (%g)" % (j, ch, d)
            assert clamp8(grid[j][0][ch] * 255.0) == clamp8(grid[j][size][ch] * 255.0), \
                "u-wrap quantised mismatch at row %d channel %d" % (j, ch)
    for i in range(size):
        for ch in range(3):
            d = abs(grid[0][i][ch] - grid[size][i][ch])
            if d > worst:
                worst = d
            assert d <= 1e-12, "v-wrap mismatch at col %d channel %d (%g)" % (i, ch, d)
            assert clamp8(grid[0][i][ch] * 255.0) == clamp8(grid[size][i][ch] * 255.0), \
                "v-wrap quantised mismatch at col %d channel %d" % (i, ch)
    return worst


def _line_diff(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / float(len(a))


def check_seams(rows, size):
    """The last-row -> first-row seam must be statistically identical to any
    interior adjacent pair (same for columns), i.e. no visible seam line."""
    cols = []
    for i in range(size):
        col = bytearray(size * 3)
        for j in range(size):
            col[j * 3] = rows[j][i * 3]
            col[j * 3 + 1] = rows[j][i * 3 + 1]
            col[j * 3 + 2] = rows[j][i * 3 + 2]
        cols.append(col)
    adj_y = sum(_line_diff(rows[j], rows[j + 1]) for j in range(size - 1)) / float(size - 1)
    seam_y = _line_diff(rows[size - 1], rows[0])
    adj_x = sum(_line_diff(cols[i], cols[i + 1]) for i in range(size - 1)) / float(size - 1)
    seam_x = _line_diff(cols[size - 1], cols[0])
    # the +1.0 guards against a near-flat interior; 1.45x allows single-pair sampling noise
    assert seam_y <= 1.45 * adj_y + 1.0, "vertical seam %.3f >> interior %.3f" % (seam_y, adj_y)
    assert seam_x <= 1.45 * adj_x + 1.0, "horizontal seam %.3f >> interior %.3f" % (seam_x, adj_x)
    return adj_x, adj_y, seam_x, seam_y


def channel_stats(rows, size, ch):
    tot = 0
    mn, mx = 255, 0
    for j in range(size):
        row = rows[j]
        for i in range(ch, size * 3, 3):
            v = row[i]
            tot += v
            if v < mn:
                mn = v
            if v > mx:
                mx = v
    mean = tot / float(size * size)
    # ~0.5-centred (so the shader's (dt - 0.5) * k grade is neutral on average)
    # and with real contrast (not a flat fill)
    assert abs(mean - 127.5) <= 20.0, "channel %d mean %.1f off centre" % (ch, mean)
    assert mx - mn >= 50, "channel %d nearly flat (%d..%d)" % (ch, mn, mx)
    return mean, mn, mx


# ----------------------------------------------------------------------------- image io
def write_png(path, rows, size):
    """8-bit RGB PNG.  Paeth-filtered (filter type 4) with zlib's filtered
    strategy: the cheapest encoding that keeps the fine speckle inside the
    100 KB budget (plain rows / Up filter both came out well over)."""
    def paeth(a, b, c):
        p = a + b - c
        pa = abs(p - a)
        pb = abs(p - b)
        pc = abs(p - c)
        if pa <= pb and pa <= pc:
            return a
        if pb <= pc:
            return b
        return c

    stride = size * 3
    raw = bytearray()
    prev = bytes(stride)
    for r in rows:
        raw.append(4)                                   # filter type: Paeth
        for o in range(stride):
            a = r[o - 3] if o >= 3 else 0
            b = prev[o]
            c = prev[o - 3] if o >= 3 else 0
            raw.append((r[o] - paeth(a, b, c)) & 0xFF)
        prev = r

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    hdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    co = zlib.compressobj(9, zlib.DEFLATED, 15, 9, zlib.Z_FILTERED)
    idat = co.compress(bytes(raw)) + co.flush()
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr)
           + chunk(b"IDAT", idat) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    return len(png)


# --------------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="Generate the tileable terrain close-range detail texture.")
    ap.add_argument("--out", default=DEFAULT_OUT, help="output PNG path")
    ap.add_argument("--size", type=int, default=DEFAULT_SIZE, help="tile size in pixels")
    ap.add_argument("--seed", type=int, default=SEED, help="deterministic seed")
    args = ap.parse_args()
    size = max(32, int(args.size))
    out = os.path.abspath(args.out)

    grid = make_grid(size, args.seed)
    worst = check_tileable(grid, size)
    rows = to_rows(grid, size)
    means = []
    for ch in range(3):
        mean, mn, mx = channel_stats(rows, size, ch)
        means.append((mean, mn, mx))
    adj_x, adj_y, seam_x, seam_y = check_seams(rows, size)

    os.makedirs(os.path.dirname(out), exist_ok=True)
    nbytes = write_png(out, rows, size)
    assert nbytes < 100 * 1024, "PNG too large: %d bytes" % nbytes
    with open(out, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()[:16]

    print("terrain detail texture -> %s" % out)
    print("%dx%d 8-bit RGB, %d bytes, seed %d, sha256 %s..."
          % (size, size, nbytes, args.seed, digest))
    for ch, name in enumerate(("R turf", "G soil", "B height")):
        mean, mn, mx = means[ch]
        print("  %s: mean %.1f  min %d  max %d" % (name, mean, mn, mx))
    print("  wrap float error: %.3g (0 = bit-exact torus)" % worst)
    print("  seam vs interior detail: X %.3f / %.3f   Y %.3f / %.3f (<=1.45x asserted)"
          % (seam_x, adj_x, seam_y, adj_y))
    print("OK: tileable (value(0) == value(%d) exact on rows and cols), deterministic." % size)


if __name__ == "__main__":
    main()
