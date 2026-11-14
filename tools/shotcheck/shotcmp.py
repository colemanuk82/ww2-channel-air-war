"""Screenshot comparison: new captures against the committed baselines.

    python tools/shotcheck/shotcmp.py <shots_dir> [--update] [--tol 6.0] [--frac 0.04]

Every <name>.png in tools/shotcheck/baselines/ is compared with <shots_dir>/<name>.png. Both are shrunk to
320x180 and greyscale-blurred first, so anti-aliasing, cloud drift and small animation offsets do not count;
what fails is a real change in layout or look (a missing panel, a black screen, a broken shader, the wrong page).

A shot fails when the mean difference exceeds --tol (0-255) or more than --frac of the pixels differ by over 40.
--update copies the new captures over the baselines (do that only after looking at them).
A diff image <name>_diff.png is written next to each failing capture. Exit code 1 when any shot fails.
"""
import argparse
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

HERE = Path(__file__).resolve().parent
BASE = HERE / "baselines"
SIZE = (320, 180)


def load(p: Path) -> np.ndarray:
    im = Image.open(p).convert("L").resize(SIZE, Image.BILINEAR).filter(ImageFilter.GaussianBlur(1.2))
    return np.asarray(im, dtype=np.float32)


def small_rgb(p: Path) -> Image.Image:
    return Image.open(p).convert("RGB").resize(SIZE, Image.BILINEAR)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("shots")
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--tol", type=float, default=6.0)
    ap.add_argument("--frac", type=float, default=0.04)
    ap.add_argument("--present", action="store_true", help="skip baselines with no capture (partial runs)")
    a = ap.parse_args()
    shots = Path(a.shots)
    BASE.mkdir(parents=True, exist_ok=True)
    if a.update:
        n = 0
        for p in sorted(shots.glob("*.png")):
            if p.stem.endswith("_diff"):
                continue
            small_rgb(p).save(BASE / p.name)
            n += 1
        print(f"SHOTCHECK updated {n} baselines")
        return 0
    bases = sorted(BASE.glob("*.png"))
    if a.present:
        bases = [b for b in bases if (shots / b.name).exists()]
    if not bases:
        print("SHOTCHECK no baselines (run with --update first)")
        return 1
    bad = 0
    for b in bases:
        s = shots / b.name
        if not s.exists() and a.present:
            continue
        if not s.exists():
            print(f"FAIL {b.stem}: no capture")
            bad += 1
            continue
        x, y = load(b), load(s)
        d = np.abs(x - y)
        mean, frac = float(d.mean()), float((d > 40).mean())
        ok = mean <= a.tol and frac <= a.frac
        print(f"{'ok  ' if ok else 'FAIL'} {b.stem}: mean {mean:.2f} (<= {a.tol}), changed {frac * 100:.1f}% (<= {a.frac * 100:.1f}%)")
        if not ok:
            bad += 1
            Image.fromarray(np.clip(d * 4, 0, 255).astype(np.uint8)).save(shots / f"{b.stem}_diff.png")
    print(f"SHOTCHECK {'OK' if bad == 0 else 'FAILED'} ({len(bases) - bad}/{len(bases)})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
