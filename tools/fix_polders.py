"""Raise enclosed below-sea-level land (polders, reclaimed marsh) out of the sea.

The terrarium DEM is clamped at 0 m, so low-lying land such as the Calais / Dunkirk wateringues, Romney Marsh
pockets and the Flanders polders reads as sea level and the game floods it into inland "seas". Real open water
is the zero-height area connected to the edge of the map (the Channel / North Sea, plus estuaries that reach
it). Every other zero-height pocket is set to POLDER_M metres, unless the land cover says it is mostly water.

Run after make_heightmap.py:  python tools/fix_polders.py
"""
import json
import os
import sys

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HM = os.path.join(ROOT, "data", "heightmap", "region_height.png")
META = os.path.join(ROOT, "data", "heightmap", "region_meta.json")
LANDCOVER = os.path.join(ROOT, "data", "heightmap", "region_landcover.bin")   # ESA WorldCover classes, same grid
POLDER_M = 1.0


def main() -> int:
    h = cv2.imread(HM, cv2.IMREAD_UNCHANGED)
    if h is None or h.dtype != np.uint16:
        print("expected a 16-bit heightmap at", HM)
        return 1
    meta = json.load(open(META))
    sea_v = int(meta.get("sea_level_value", 0))
    max_m = float(meta.get("max_elev_m", 1000))
    water = (h <= sea_v).astype(np.uint8)
    n, labels = cv2.connectedComponents(water, connectivity=4)
    edge = set(np.unique(np.concatenate([labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]])).tolist())
    edge.discard(0)
    open_sea = np.isin(labels, list(edge))
    pockets = (water == 1) & ~open_sea
    # Tidal harbours with narrow mouths (Poole, Portsmouth / Langstone) close up at this resolution: keep any
    # pocket that the land cover says is mostly open water (class 80).
    if os.path.exists(LANDCOVER):
        lc = np.fromfile(LANDCOVER, dtype=np.uint8)
        if lc.size == h.size:
            lc = lc.reshape(h.shape)
            for lab in np.unique(labels[pockets]).tolist():
                m = labels == lab
                if np.mean(lc[m] == 80) > 0.5:
                    pockets &= ~m
    v = sea_v + int(round(POLDER_M / max_m * 65535.0))
    h[pockets] = v
    cv2.imwrite(HM, h)
    print("raised %d enclosed sea-level pixels (%d pockets) to %.1f m" % (int(pockets.sum()), n - 1 - len(edge), POLDER_M))
    return 0


if __name__ == "__main__":
    sys.exit(main())
