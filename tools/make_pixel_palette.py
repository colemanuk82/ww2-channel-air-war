"""Generate the fixed 32-colour palette for pixel-art mode (PROMPT-pixel-art.md, phase 0.2).

Writes assets/textures/pixel/palette.png: a 32x1 RGB PNG, one palette entry per pixel, ordered so
that a nearest-colour search is cheap and the ramp order is readable. Also writes palette.json with
the same colours in sRGB 0-255 for the tests and for any tooling.

The palette is designed for this game's subject (1940s England, the Channel, France) rather than
reused from another title: two neutral ramps for terrain and roofs, a green ramp for vegetation, the
sea/sky ramp, and a handful of accent colours for markings, fire, skin and uniforms.

    python tools/make_pixel_palette.py
    python tools/make_pixel_palette.py --out DIR --check
"""
import argparse
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "assets", "textures", "pixel")

# Hand-picked sRGB values. Grouped by ramp so the shader pass and any manual drawing agree.
PALETTE = [
    # 0-3   ink: outlines, shadows, UI text (Slotbound's look is defined by its dark ink)
    (12, 11, 16), (26, 24, 32), (41, 38, 48), (58, 54, 66),
    # 4-7   neutral ramp, cool: stone, cloud shade, concrete
    (78, 78, 88), (104, 104, 116), (134, 134, 146), (166, 166, 176),
    # 8-11  neutral ramp, warm: plaster, sand, road, runway
    (190, 186, 178), (212, 206, 194), (228, 222, 208), (244, 240, 230),
    # 12-15 grass / field greens (the ground spends most of the frame here)
    (46, 66, 42), (64, 88, 50), (86, 112, 60), (110, 138, 74),
    # 16-19  second green ramp: meadow, crop, the pale dry field
    (134, 160, 92), (160, 180, 108), (186, 196, 132), (208, 208, 158),
    # 20-23  sea and sky blues
    (30, 52, 76), (44, 74, 104), (66, 104, 138), (98, 140, 176),
    # 24-25  pale sky / haze
    (140, 176, 202), (186, 212, 226),
    # 26-27  brick / roof terracotta
    (118, 62, 48), (158, 88, 62),
    # 28-29  military drab and Luftwaffe blue-grey
    (92, 86, 58), (104, 110, 118),
    # 30-31  accents: raf roundel red, fire/flak orange
    (176, 56, 48), (226, 144, 62),
]

N = 32


def build_palette():
    assert len(PALETTE) == N, f"expected {N} colours, got {len(PALETTE)}"
    for c in PALETTE:
        assert len(c) == 3 and all(0 <= v <= 255 for v in c), f"bad colour {c}"
    return PALETTE


def write_png(colours, path):
    """Write a 32x1 RGB PNG. Done by hand so the tool has no Pillow dependency."""
    import struct
    import zlib

    w, h = len(colours), 1
    raw = b""
    for y in range(h):
        raw += b"\x00"                      # filter byte: none
        for x in range(w):
            raw += bytes(colours[x])

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)   # 8-bit, colour type 2 (RGB)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--check", action="store_true", help="verify the committed files match, do not write")
    args = ap.parse_args()

    colours = build_palette()
    png = os.path.join(args.out, "palette.png")
    js = os.path.join(args.out, "palette.json")

    if args.check:
        import struct
        import zlib
        ok = True
        if not os.path.exists(png):
            print("MISSING", png)
            ok = False
        else:
            data = open(png, "rb").read()
            # pull the IDAT back out and compare the raw pixels
            pos, idat = 8, b""
            while pos < len(data):
                ln = struct.unpack(">I", data[pos:pos + 4])[0]
                tag = data[pos + 4:pos + 8]
                body = data[pos + 8:pos + 8 + ln]
                if tag == b"IDAT":
                    idat += body
                pos += 12 + ln
            raw = zlib.decompress(idat)
            got = [tuple(raw[1 + i * 3:4 + i * 3]) for i in range(N)]
            if got != [tuple(c) for c in colours]:
                print("palette.png does not match the generator")
                ok = False
        if not os.path.exists(js):
            print("MISSING", js)
            ok = False
        print("PALETTE OK" if ok else "PALETTE MISMATCH")
        return 0 if ok else 1

    os.makedirs(args.out, exist_ok=True)
    write_png(colours, png)
    with open(js, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"count": N, "colours": [list(c) for c in colours]}, f, indent="\t")
        f.write("\n")
    print(f"wrote {png} ({N} colours)")
    print(f"wrote {js}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
