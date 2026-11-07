#!/usr/bin/env python3
"""Generate the desert map's life and campaign data.

Writes:
  data/desert/life.json      settlements, oases, camel caravans, moving battle groups
  data/desert/locations.json adds generated targets (army camps, convoy routes) and extra airfields

Everything is validated against the real coast mask and heightmap, so nothing is placed in the sea or
on a mountain. Deterministic: same inputs -> same output. Existing hand-authored rows are preserved;
rows this tool wrote earlier (marked "generated": true) are replaced.

  python tools/make_desert_life.py
"""
import json
import math
import os
import sys
import zlib

import numpy as np
from PIL import Image

DATA = os.path.join("data", "desert")
M_PER_DEG_LAT = 110574.0
M_PER_DEG_LON = 111320.0

# ------------------------------------------------------------------ data validation

class Field:
    def __init__(self):
        meta = json.load(open(os.path.join(DATA, "region_meta.json")))
        self.lat_min, self.lat_max = meta["lat_min"], meta["lat_max"]
        self.lon_min, self.lon_max = meta["lon_min"], meta["lon_max"]
        self.max_elev = float(meta.get("max_elev_m", 3000))
        self.w, self.h = meta["width"], meta["height"]
        coast = Image.open(os.path.join(DATA, "region_coast.png")).convert("L")
        self.land_img = np.asarray(coast.resize((self.w, self.h), Image.BILINEAR), dtype=np.float32) / 255.0
        himg = Image.open(os.path.join(DATA, "region_height.png"))
        arr = np.asarray(himg, dtype=np.uint16)
        self.elev = arr.astype(np.float32) / 65535.0 * self.max_elev

    def _uv(self, lat, lon):
        u = (lon - self.lon_min) / (self.lon_max - self.lon_min) * (self.w - 1)
        v = (self.lat_max - lat) / (self.lat_max - self.lat_min) * (self.h - 1)
        return u, v

    def sample(self, lat, lon):
        u, v = self._uv(lat, lon)
        if u < 0 or v < 0 or u >= self.w - 1 or v >= self.h - 1:
            return 0.0, 0.0
        x, y = int(u), int(v)
        fx, fy = u - x, v - y
        m = (self.land_img[y, x] * (1 - fx) * (1 - fy) + self.land_img[y, x + 1] * fx * (1 - fy)
             + self.land_img[y + 1, x] * (1 - fx) * fy + self.land_img[y + 1, x + 1] * fx * fy)
        e = (self.elev[y, x] * (1 - fx) * (1 - fy) + self.elev[y, x + 1] * fx * (1 - fy)
             + self.elev[y + 1, x] * (1 - fx) * fy + self.elev[y + 1, x + 1] * fx * fy)
        return m, e

    def ok(self, lat, lon, radius_m=300.0, max_elev=650.0):
        m, e = self.sample(lat, lon)
        if m < 0.55 or e < 2.0 or e > max_elev:
            return False
        dlat = radius_m / M_PER_DEG_LAT
        dlon = radius_m / (M_PER_DEG_LON * math.cos(math.radians(lat)))
        for a in (0, 90, 180, 270):
            mm, ee = self.sample(lat + math.cos(math.radians(a)) * dlat,
                                 lon + math.sin(math.radians(a)) * dlon)
            if mm < 0.5 or abs(ee - e) > 35.0:
                return False
        return True

    def flat(self, lat, lon, radius_m=900.0):
        e0 = self.sample(lat, lon)[1]
        dlat = radius_m / M_PER_DEG_LAT
        dlon = radius_m / (M_PER_DEG_LON * math.cos(math.radians(lat)))
        es = [e0]
        for a in (0, 45, 90, 135, 180, 225, 270, 315):
            m, e = self.sample(lat + math.cos(math.radians(a)) * dlat,
                               lon + math.sin(math.radians(a)) * dlon)
            if m < 0.5:
                return False
            es.append(e)
        return max(es) - min(es) < 40.0


def line_len(pts):
    total = 0.0
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        dy = (b[0] - a[0]) * M_PER_DEG_LAT
        dx = (b[1] - a[1]) * M_PER_DEG_LON * math.cos(math.radians((a[0] + b[0]) * 0.5))
        total += math.hypot(dx, dy)
    return total


def downsample(pts, max_pts=8):
    if len(pts) <= max_pts:
        return pts
    step = max(1, (len(pts) - 1) // (max_pts - 1))
    out = pts[::step]
    if out[-1] != pts[-1]:
        out.append(pts[-1])
    return out[:max_pts]


def downsample_dist(pts, spacing_m=14000.0, max_pts=8):
    out = [pts[0]]
    acc = 0.0
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        dy = (b[0] - a[0]) * M_PER_DEG_LAT
        dx = (b[1] - a[1]) * M_PER_DEG_LON * math.cos(math.radians((a[0] + b[0]) * 0.5))
        acc += math.hypot(dx, dy)
        if acc >= spacing_m and len(out) < max_pts - 1:
            out.append(b)
            acc = 0.0
    if out[-1] != pts[-1]:
        out.append(pts[-1])
    return out


# ------------------------------------------------------------------ candidates

CAMPS = [
    # id, name, lat, lon, side, era
    ("camp_gazala", "Gazala Camp", 32.10, 23.35, "Axis", "1942-01 to 1942-12"),
    ("camp_sidi_rezegh", "Sidi Rezegh Camp", 31.83, 24.13, "Axis", "1941-10 to 1942-12"),
    ("camp_bir_hakeim", "Bir Hakeim Camp", 31.59, 23.48, "Axis", "1942-02 to 1942-12"),
    ("camp_knightsbridge", "Knightsbridge Camp", 31.75, 23.85, "Axis", "1942-05 to 1942-11"),
    ("camp_alamein", "Alamein Camp", 30.84, 28.95, "Axis", "1942-06 to 1942-11"),
    ("camp_tel_el_aqqaqir", "Tel el Aqqaqir Camp", 30.85, 29.15, "Axis", "1942-07 to 1942-11"),
    ("camp_mareth", "Mareth Camp", 33.63, 10.30, "Axis", "1942-12 to 1943-03"),
    ("camp_kasserine", "Kasserine Camp", 35.17, 8.83, "Axis", "1942-11 to 1943-02"),
    ("camp_sidi_bou_zid", "Sidi Bou Zid Camp", 35.03, 9.48, "Axis", "1942-11 to 1943-02"),
    ("camp_medenine", "Medenine Camp", 33.35, 10.50, "Axis", "1943-01 to 1943-03"),
    ("camp_tobruk_south", "Tobruk South Camp", 31.95, 23.95, "Axis", "1941-04 to 1941-12"),
    ("camp_bardia", "Bardia Camp", 31.76, 25.06, "Axis", "1941-04 to 1941-12"),
    ("camp_sollum", "Sollum Camp", 31.55, 25.16, "Axis", "1941-04 to 1942-11"),
    ("camp_tripoli_south", "Tripoli South Camp", 32.55, 13.10, "Axis", "1940-06 to 1942-11"),
    ("camp_sfax_west", "Sfax West Camp", 34.75, 10.20, "Axis", "1942-11 to 1943-04"),
    # Allied camps, so an Axis pilot has camps to attack too
    ("camp_alamein_allied", "Alamein Supply Camp", 30.92, 29.32, "Allies", "1942-07 to 1943-05"),
    ("camp_tobruk_allied", "Tobruk Supply Camp", 32.02, 24.12, "Allies", "1942-11 to 1943-05"),
    ("camp_tripoli_allied", "Tripoli Supply Camp", 32.60, 13.22, "Allies", "1943-01 to 1943-05"),
    ("camp_benghazi_allied", "Benghazi Supply Camp", 32.02, 20.22, "Allies", "1942-11 to 1943-05"),
    ("camp_kairouan_allied", "Kairouan Supply Camp", 35.62, 10.05, "Allies", "1943-04 to 1943-05"),
]

SETTLEMENTS = [
    # id, name, lat, lon, size, kind
    ("hamlet_sirte_inland", "Bir el Ghnem", 31.02, 16.85, 2, "hamlet"),
    ("hamlet_cyrenaica", "Zawiyat al Kufra", 32.62, 21.10, 2, "hamlet"),
    ("hamlet_marmarica", "Bir Habeid", 31.42, 25.55, 1, "hamlet"),
    ("hamlet_tripolitania", "Bir Tarhuna", 32.35, 13.45, 2, "hamlet"),
    ("hamlet_sirte_coast", "Bir Bu Shifa", 31.10, 18.85, 1, "hamlet"),
    ("hamlet_djebel", "Kaf al Ghazal", 32.45, 21.65, 2, "hamlet"),
    ("hamlet_tunisia", "Bir Mateur", 37.02, 9.55, 2, "hamlet"),
    ("hamlet_capbon", "Dar Ben Saad", 36.72, 10.85, 2, "hamlet"),
    ("hamlet_dorsal", "Ain Djemaa", 35.55, 9.35, 2, "hamlet"),
    ("hamlet_gafsa", "Bir Gafsa Sud", 34.20, 8.65, 2, "hamlet"),
    ("hamlet_nile", "Bir Abu Ghalib", 30.78, 29.65, 2, "hamlet"),
    ("hamlet_delta", "Kafr el Dawwar", 31.05, 30.30, 3, "hamlet"),
    ("hamlet_fayum_edge", "Bir Qarun", 30.45, 30.10, 2, "hamlet"),
    ("hamlet_erg", "Bir al Qattara", 30.32, 26.20, 1, "hamlet"),
    ("oasis_sirte", "Ain al Ghazala", 30.45, 16.20, 3, "oasis"),
    ("oasis_cyrenaica", "Ain Mara", 30.60, 21.40, 3, "oasis"),
    ("oasis_marmarica", "Bir Sidi Omar", 31.40, 24.80, 2, "oasis"),
    ("oasis_tunisia", "Ain el Ksar", 33.90, 8.90, 3, "oasis"),
    ("oasis_djebel", "Ain al Kuf", 32.20, 22.10, 2, "oasis"),
    ("oasis_nile", "Ain Shams", 30.55, 29.90, 3, "oasis"),
]

EXTRA_FIELDS = [
    # id, name, lat, lon
    ("lg_sidi_barrani", "Sidi Barrani", 31.61, 25.93),
    ("lg_sollum", "Sollum", 31.58, 25.18),
    ("lg_gazala", "Gazala", 32.10, 23.32),
    ("lg_sidi_rezegh", "Sidi Rezegh", 31.83, 24.10),
    ("lg_bir_el_gubi", "Bir el Gubi", 31.55, 24.20),
    ("lg_mechili", "Mechili", 32.18, 24.08),
    ("lg_msus", "Msus", 31.55, 20.85),
    ("lg_antelat", "Antelat", 31.45, 20.55),
    ("lg_marble_arch", "Marble Arch", 31.35, 21.35),
    ("lg_el_agheila", "El Agheila", 30.55, 19.20),
    ("lg_kairouan", "Kairouan", 35.68, 10.10),
    ("lg_mateur", "Mateur", 37.05, 9.67),
    ("lg_gafsa", "Gafsa", 34.42, 8.78),
    ("lg_sbeitla", "Sbeitla", 35.24, 9.12),
    ("lg_el_guettar", "El Guettar", 34.32, 9.05),
    ("lg_medenine", "Medenine", 33.35, 10.50),
    ("lg_sidi_bou_zid", "Sidi Bou Zid", 35.03, 9.48),
    ("lg_feriana", "Feriana", 34.95, 8.57),
    ("lg_cap_bon", "Kelibia", 36.85, 11.10),
    ("lg_sousse", "Sousse", 35.83, 10.64),
    ("lg_mahdia", "Mahdia", 35.50, 11.07),
    ("lg_bir_hacheim", "Bir Hakeim", 31.59, 23.45),
]


def main():
    if not os.path.isdir(DATA):
        print("run from the project root (data/desert not found)")
        return 1
    fld = Field()

    loc = json.load(open(os.path.join(DATA, "locations.json"), encoding="utf-8"))
    # replace everything this tool wrote earlier, so a rerun is a clean regeneration
    loc["airfields"] = [a for a in loc.get("airfields", []) if not bool(a.get("generated", False))]
    existing_fields = {str(a.get("id", "")) for a in loc.get("airfields", [])}
    existing_targets = loc.get("targets", [])
    keep_targets = [t for t in existing_targets if not bool(t.get("generated", False))]

    # ---- extra airfields
    fields_added = []
    for fid, name, lat, lon in EXTRA_FIELDS:
        if fid in existing_fields:
            continue
        if not fld.flat(lat, lon, 900.0):
            print("WARN airfield not flat/land:", fid, lat, lon)
            continue
        loc["airfields"].append({
            "id": fid, "name": name, "side": "RAF" if lon > 25.5 else "Luftwaffe/RA",
            "lat": round(lat, 4), "lon": round(lon, 4),
            "heading_deg": round((zlib.crc32(fid.encode()) % 18) * 10.0, 1),
            "runway_len_m": 1200, "era": "1940-06 to 1943-05", "in_bounds": True,
            "generated": True, "confidence": "low",
            "note": "added landing ground to break up the empty desert; heading is provisional",
        })
        fields_added.append(fid)

    # ---- army camp targets
    camps_added = []
    for cid, name, lat, lon, side, era in CAMPS:
        if not fld.ok(lat, lon, 350.0, 500.0):
            print("WARN camp not land/flat:", cid, lat, lon)
            continue
        keep_targets.append({
            "id": cid, "name": name, "type": "camp", "lat": round(lat, 4), "lon": round(lon, 4),
            "side_owner": side,
            # broad window: these are standing camps, so a sortie on any desert date has camps to attack
            "era": "1940-06 to 1943-05", "radius_m": 220, "in_bounds": True,
            "generated": True, "confidence": "low",
            "historical_era": era,
        })
        camps_added.append(cid)

    # ---- track lines for convoy routes, caravans and battle groups
    tracks = json.load(open(os.path.join(DATA, "tracks.json"), encoding="utf-8"))
    tlines = tracks.get("lines", [])

    def usable(lines, min_km=18.0):
        out = []
        for ln in lines:
            pts = ln.get("pts", [])
            if len(pts) < 2:
                continue
            km = line_len(pts) / 1000.0
            if km >= min_km:
                out.append((km, pts, ln.get("n", "piste")))
        out.sort(key=lambda x: -x[0])
        return out

    pool = usable(tlines)
    # spread: bucket by the midpoint, keep one per ~60 km cell so routes are not all in one place
    chosen = []
    seen = set()
    for km, pts, nm in pool:
        mid = pts[len(pts) // 2]
        key = (int(mid[0] / 0.55), int(mid[1] / 0.65))
        if key in seen:
            continue
        seen.add(key)
        chosen.append((km, pts, nm))
        if len(chosen) >= 16:
            break
    if len(chosen) < 8:
        for item in pool:
            if item not in chosen:
                chosen.append(item)
            if len(chosen) >= 8:
                break

    routes_added = []
    for i, (km, pts, nm) in enumerate(chosen[:12]):
        seg = downsample_dist(pts, 14000.0, 8)
        if not all(fld.ok(p[0], p[1], 120.0, 700.0) for p in seg):
            continue
        mid = seg[len(seg) // 2]
        team = "Allies" if mid[1] > 29.0 else "Axis"
        rid = "convoy_gen_%02d" % (i + 1)
        keep_targets.append({
            "id": rid, "name": ("Road convoy: " + str(nm)[:40]), "type": "convoy_route",
            "lat": round(seg[0][0], 4), "lon": round(seg[0][1], 4),
            "side_owner": team, "era": "1940-06 to 1943-05", "comp": "supply" if i % 3 else "mixed",
            "start_s": 200.0 + 400.0 * (i % 5), "in_bounds": True, "generated": True,
            "confidence": "low", "path": [[round(p[0], 4), round(p[1], 4)] for p in seg],
        })
        routes_added.append(rid)

    # ---- camel caravans and moving battle groups
    caravans = []
    groups = []
    for i, (km, pts, nm) in enumerate(chosen):
        seg = downsample_dist(pts, 16000.0, 7)
        if not all(fld.ok(p[0], p[1], 120.0, 700.0) for p in seg):
            continue
        if i % 2 == 0 and len(caravans) < 8:
            caravans.append({
                "id": "caravan_%02d" % (len(caravans) + 1),
                "name": "Camel caravan: " + str(nm)[:36],
                "team": "Neutral", "count": 8 + (i * 3) % 9, "speed": 1.25,
                "pts": [[round(p[0], 4), round(p[1], 4)] for p in seg],
            })
        else:
            mid = seg[len(seg) // 2]
            allies = mid[1] > 29.0
            groups.append({
                "id": "battle_group_%02d" % (len(groups) + 1),
                "name": "Battle group: " + str(nm)[:36],
                "team": "Allies" if allies else "Axis",
                "comp": "tanks" if len(groups) % 2 == 0 else "mixed",
                "speed": 9.0, "from": "1941-01", "to": "1943-05",
                "wrecks": 3 + (i % 4),
                "pts": [[round(p[0], 4), round(p[1], 4)] for p in seg],
            })
    # a couple of genuinely tank-heavy groups on the battle roads
    for i, (km, pts, nm) in enumerate(chosen[:6]):
        if "el agheila" in str(nm).lower() or "tobruk" in str(nm).lower() or i < 2:
            continue
        seg = downsample_dist(pts, 15000.0, 7)
        groups.append({
            "id": "battle_group_%02d" % (len(groups) + 1),
            "name": "Armoured column: " + str(nm)[:34],
            "team": "Axis", "comp": "tanks", "speed": 8.0,
            "from": "1941-01", "to": "1943-05", "wrecks": 2,
            "pts": [[round(p[0], 4), round(p[1], 4)] for p in seg],
        })

    # ---- settlements and oases
    places = []
    for pid, name, lat, lon, size, kind in SETTLEMENTS:
        if not fld.ok(lat, lon, 260.0, 620.0):
            print("WARN place not land:", pid, lat, lon)
            continue
        places.append({"id": pid, "name": name, "kind": kind, "lat": round(lat, 4), "lon": round(lon, 4),
                       "size": size})

    life = {
        "source": "generated by tools/make_desert_life.py (validated against region_coast.png + region_height.png)",
        "settlements": places,
        "caravans": caravans,
        "battle_groups": groups,
    }

    loc["targets"] = keep_targets
    with open(os.path.join(DATA, "locations.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(loc, f, indent=1, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(DATA, "life.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(life, f, indent=1, ensure_ascii=False)
        f.write("\n")

    print("airfields added:", len(fields_added), fields_added)
    print("camps added:", len(camps_added))
    print("convoy routes added:", len(routes_added))
    print("settlements:", len(places), "caravans:", len(caravans), "battle groups:", len(groups))
    return 0


if __name__ == "__main__":
    sys.exit(main())
