#!/usr/bin/env python3
"""Validate all generated data against the contract in SPEC.md and print a summary.
Exit code 1 if any hard error is found. Usage: python tools/validate_data.py"""
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data")
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0
# Generous per-file size cap. The *accepted* real roads.json is ~19.7 MB (a genuine OSM road
# network, not a bug), so the guard exists only to catch an accidental multi-hundred-MB blow-up.
MAX_JSON_KB = 40000
INDUSTRY_KINDS = {"gasworks", "colliery", "mill", "brewery", "power_station", "shipyard",
                  "dockyard", "goods_yard", "engine_shed", "waterworks", "cement_works", "staithes",
                  "quarry"}   # chalk/limestone pits: IndustryKit.build() case \"quarry\"
PIER_KINDS = {"pleasure_pier", "harbour_pier"}
DOCK_KINDS = {"drydock", "shipyard", "basin", "lock"}
errors, warns = [], []


def polyline_km(pts):
    """Approximate length of a [[lat,lon],...] polyline in km (equirectangular, ~51 deg N)."""
    tot = 0.0
    for i in range(1, len(pts)):
        tot += math.hypot((pts[i][0] - pts[i - 1][0]) * 110.5, (pts[i][1] - pts[i - 1][1]) * 71.0)
    return tot


def latlon_to_world(lat, lon):
    """SPEC WORLD COORDINATE CONTRACT (y = 0). Mirrors scripts/world_coords.gd."""
    # Mirrors WorldCoords.HORIZ_COMPRESSION (1.0 = 1 world unit per real metre; it was 10.0 before v1.9).
    # This used to hardcode /10.0, which made every printed world coordinate - and the "playable bounds"
    # line - ten times too small.
    x = (lon - 0.0) * 111320.0 * math.cos(math.radians(50.3)) / 1.0
    z = -(lat - 50.3) * 110540.0 / 1.0
    return x, 0.0, z


def err(m):
    errors.append(m)
    print("  ERROR:", m)


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:  # noqa: BLE001
        err(f"cannot load {path}: {e}")
        return None


def check_locations():
    print("== locations.json")
    L = load(os.path.join(D, "locations.json"))
    if not L:
        return None
    req = dict(airfields=["id", "name", "side", "lat", "lon", "heading_deg", "runway_len_m"],
               cities=["id", "name", "lat", "lon", "size"],
               features=["id", "name", "type", "lat", "lon"],
               targets=["id", "name", "type", "lat", "lon", "side_owner"])
    ids = set()
    for sec, keys in req.items():
        arr = L.get(sec)
        if not isinstance(arr, list):
            err(f"missing section {sec}")
            continue
        oob = 0
        for r in arr:
            for k in keys:
                if k not in r:
                    err(f"{sec}/{r.get('id')} missing '{k}'")
            if r.get("id") in ids:
                err(f"duplicate id {r.get('id')}")
            ids.add(r.get("id"))
            if not r.get("in_bounds", True):
                oob += 1
            if sec == "airfields" and r.get("side") not in ("RAF", "Luftwaffe"):
                err(f"airfield {r['id']} bad side")
            if sec == "cities" and not 1 <= r.get("size", 0) <= 5:
                err(f"city {r['id']} size out of range")
            if sec == "features" and r.get("type") not in ("cliff", "beach", "battery", "river", "forest", "landmark"):
                err(f"feature {r['id']} bad type")
            if sec == "targets" and r.get("side_owner") not in ("Axis", "Allies"):
                err(f"target {r['id']} bad side_owner")
        extra = f" ({oob} outside playable bounds, flagged in_bounds=false)" if oob else ""
        print(f"  {sec}: {len(arr)}{extra}")
    raf = sum(1 for a in L["airfields"] if a["side"] == "RAF")
    print(f"  airfields RAF={raf} Luftwaffe={len(L['airfields']) - raf}")
    M = load(os.path.join(D, "missions_seed.json"))
    if M:
        tids = {t["id"] for t in L["targets"]}
        aids = {a["id"] for a in L["airfields"]}
        for m in M["missions"]:
            for s in m["sides"]:
                if s["start_airfield"] not in aids:
                    err(f"mission {m['id']} bad airfield {s['start_airfield']}")
            for side, objs in m["objectives"].items():
                for o in objs:
                    if o not in tids:
                        err(f"mission {m['id']} unknown objective {o}")
        print(f"  missions_seed: {len(M['missions'])} missions")
    return L


def check_heightmap():
    print("== heightmap")
    meta = load(os.path.join(D, "heightmap", "region_meta.json"))
    if not meta:
        return
    for k in ("width", "height", "lat_min", "lat_max", "lon_min", "lon_max", "max_elev_m", "sea_level_value"):
        if k not in meta:
            err(f"region_meta missing {k}")
    try:
        import numpy as np
        from PIL import Image
        im = Image.open(os.path.join(D, "heightmap", "region_height.png"))
        a = np.asarray(im)
        print(f"  image mode={im.mode} dtype={a.dtype} size={im.size} meta={meta['width']}x{meta['height']}")
        if a.dtype != np.uint16:
            err("heightmap is not 16-bit")
        if im.size != (meta["width"], meta["height"]):
            err("heightmap size != meta")
        e = a.astype(float) / 65535 * 1000
        print(f"  elevation min {e.min():.0f} m  max {e.max():.0f} m  land {(a > 0).mean() * 100:.1f}%  source: {meta.get('source', '?')}")

        def s(lat, lon):
            x = int((lon - meta["lon_min"]) / (meta["lon_max"] - meta["lon_min"]) * meta["width"])
            y = int((meta["lat_max"] - lat) / (meta["lat_max"] - meta["lat_min"]) * meta["height"])
            return e[max(0, y - 3):y + 4, max(0, x - 3):x + 4].max()
        dover, chan = s(51.13, 1.35), s(50.5, 0.5)
        print(f"  Dover cliffs (51.13,1.35) local max {dover:.0f} m; Channel (50.5,0.5) {chan:.0f} m")
        if dover <= 0:
            err("Dover is not land")
        if chan != 0:
            err("Channel is not sea")
    except ImportError:
        warns.append("numpy/pillow missing: skipped heightmap pixel checks")


def check_osm(L):
    print("== osm")
    src = load(os.path.join(D, "osm", "_source.json")) or {}
    for layer, key in (("roads", "lines"), ("rails", "lines"), ("rivers", "lines"), ("coast", "lines"),
                       ("woods", "polys"), ("towns", "towns")):
        p = os.path.join(D, "osm", f"{layer}.json")
        if not os.path.exists(p):
            err(f"missing {p}")
            continue
        j = load(p)
        if not j or key not in j:
            err(f"{layer}.json missing '{key}'")
            continue
        arr = j[key]
        npts = sum(len(r["pts"]) for r in arr) if key != "towns" else len(arr)
        kb = os.path.getsize(p) / 1024
        bad = 0
        if key != "towns":
            for r in arr:
                for la, lo in r["pts"]:
                    if not (LAT_MIN - 0.05 <= la <= LAT_MAX + 0.05 and LON_MIN - 0.05 <= lo <= LON_MAX + 0.05):
                        bad += 1
        if bad:
            err(f"{layer}: {bad} points outside bounds")
        if kb > MAX_JSON_KB:
            err(f"{layer}.json too large ({kb:.0f} KB > {MAX_JSON_KB} KB)")
        print(f"  {layer:7s} {len(arr):6d} {key:5s} {npts:8d} pts {kb:8.0f} KB  source={src.get(layer, '?')}")
    # rivers detail: line count, total length and true provenance (Phase 0 acceptance line)
    rp = os.path.join(D, "osm", "rivers.json")
    if os.path.exists(rp):
        rj = load(rp) or {}
        rlines = rj.get("lines", [])
        rkm = sum(polyline_km(l["pts"]) for l in rlines)
        kinds = {}
        for l in rlines:
            kinds[l.get("k", "?")] = kinds.get(l.get("k", "?"), 0) + 1
        cls = " ".join(f"{k}={v}" for k, v in sorted(kinds.items()))
        print(f"  rivers: {len(rlines)} lines, {rkm:.0f} km total, source={src.get('rivers', '?')} ({cls})")


def _check_records(where, arr, keys, kinds):
    ids = set()
    for r in arr:
        for k in keys:
            if k not in r:
                err(f"{where}/{r.get('id')} missing '{k}'")
        rid = r.get("id")
        if rid in ids:
            err(f"{where} duplicate id {rid}")
        ids.add(rid)
        if r.get("kind") not in kinds:
            err(f"{where}/{rid} bad kind {r.get('kind')!r}")
        if r.get("team") not in ("Axis", "Allies"):
            err(f"{where}/{rid} bad team {r.get('team')!r}")
        if "size" in r and not 1 <= r.get("size", 0) <= 3:
            err(f"{where}/{rid} size out of range")
        la, lo = r.get("lat"), r.get("lon")
        if not (isinstance(la, (int, float)) and isinstance(lo, (int, float))
                and LAT_MIN <= la <= LAT_MAX and LON_MIN <= lo <= LON_MAX):
            err(f"{where}/{rid} lat/lon out of bounds ({la}, {lo})")


def check_curated():
    """Phase 0 hand-authored 1940s datasets (industry + docks/piers)."""
    print("== curated 1940s datasets")
    ind = load(os.path.join(D, "industry_1940.json"))
    if ind is not None:
        arr = ind.get("sites")
        if not isinstance(arr, list):
            err("industry_1940.json missing 'sites' list")
        else:
            _check_records("industry", arr, ("id", "name", "kind", "lat", "lon", "size", "team"),
                           INDUSTRY_KINDS)
            print(f"  industry_1940: {len(arr)} sites")
    dk = load(os.path.join(D, "docks_1940.json"))
    if dk is not None:
        for key, kinds in (("piers", PIER_KINDS), ("docks", DOCK_KINDS)):
            arr = dk.get(key)
            if not isinstance(arr, list):
                err(f"docks_1940.json missing '{key}' list")
                continue
            _check_records(key, arr, ("id", "name", "kind", "lat", "lon", "size", "team"), kinds)
            print(f"  docks_1940 {key}: {len(arr)}")
        # ids must be unique across both sections of the file as well
        allids = [r["id"] for r in dk.get("piers", []) + dk.get("docks", [])]
        if len(allids) != len(set(allids)):
            err("docks_1940.json duplicate id across piers+docks")


SEA_DEFENCE_KINDS = {"minefield", "boom", "blockship", "sea_fort", "obstacles", "wreck",
                     "breakwater"}   # rubble-mound harbour arms: SeaDefenceKit.build_breakwater()


def check_landscape_1940():
    """P1/P2/P3 hand-authored datasets: sea defences and the Dam Busters dams."""
    print("== 1940s landscape datasets")
    sd = load(os.path.join(D, "sea_defences_1940.json"))
    if sd is not None:
        arr = sd.get("sites")
        if not isinstance(arr, list):
            err("sea_defences_1940.json missing 'sites' list")
        else:
            ids = set()
            for r in arr:
                for k in ("id", "name", "kind", "lat", "lon", "team"):
                    if k not in r:
                        err(f"sea_defences/{r.get('id')} missing '{k}'")
                if r.get("kind") not in SEA_DEFENCE_KINDS:
                    err(f"sea_defences/{r.get('id')} bad kind {r.get('kind')!r}")
                if r.get("team") not in ("Axis", "Allies"):
                    err(f"sea_defences/{r.get('id')} bad team {r.get('team')!r}")
                la, lo = r.get("lat"), r.get("lon")
                if not (isinstance(la, (int, float)) and isinstance(lo, (int, float))
                        and LAT_MIN <= la <= LAT_MAX and LON_MIN <= lo <= LON_MAX):
                    err(f"sea_defences/{r.get('id')} lat/lon out of bounds ({la}, {lo})")
                if r.get("id") in ids:
                    err(f"sea_defences duplicate id {r.get('id')}")
                ids.add(r.get("id"))
            print(f"  sea_defences_1940: {len(arr)} sites")
    dm = load(os.path.join(D, "dams_1940.json"))
    if dm is not None:
        arr = dm.get("dams")
        if not isinstance(arr, list):
            err("dams_1940.json missing 'dams' list")
        else:
            ids = set()
            for r in arr:
                for k in ("id", "name", "lat", "lon", "team", "reservoir_km2"):
                    if k not in r:
                        err(f"dams/{r.get('id')} missing '{k}'")
                if r.get("team") not in ("Axis", "Allies"):
                    err(f"dams/{r.get('id')} bad team {r.get('team')!r}")
                la, lo = r.get("lat"), r.get("lon")
                if not (isinstance(la, (int, float)) and isinstance(lo, (int, float))
                        and LAT_MIN <= la <= LAT_MAX and LON_MIN <= lo <= LON_MAX):
                    err(f"dams/{r.get('id')} lat/lon out of bounds ({la}, {lo})")
                if r.get("id") in ids:
                    err(f"dams duplicate id {r.get('id')}")
                ids.add(r.get("id"))
            print(f"  dams_1940: {len(arr)} dams")
    # P4 bombing decoys
    dy = load(os.path.join(D, "decoys_1940.json"))
    if dy is not None:
        arr = dy.get("sites")
        if not isinstance(arr, list):
            err("decoys_1940.json missing 'sites' list")
        else:
            ids = set()
            nkinds = set()
            for r in arr:
                for k in ("id", "name", "kind", "lat", "lon", "team", "size", "source"):
                    if k not in r:
                        err(f"decoys/{r.get('id')} missing '{k}'")
                if r.get("kind") not in DECOY_KINDS:
                    err(f"decoys/{r.get('id')} bad kind {r.get('kind')!r}")
                if r.get("team") not in ("Axis", "Allies"):
                    err(f"decoys/{r.get('id')} bad team {r.get('team')!r}")
                if not (isinstance(r.get("size", 0), int) and 1 <= r.get("size", 0) <= 3):
                    err(f"decoys/{r.get('id')} size out of range {r.get('size')!r}")
                la, lo = r.get("lat"), r.get("lon")
                if not (isinstance(la, (int, float)) and isinstance(lo, (int, float))
                        and LAT_MIN <= la <= LAT_MAX and LON_MIN <= lo <= LON_MAX):
                    err(f"decoys/{r.get('id')} lat/lon out of bounds ({la}, {lo})")
                if r.get("id") in ids:
                    err(f"decoys duplicate id {r.get('id')}")
                ids.add(r.get("id"))
                nkinds.add(r.get("kind"))
            if len(nkinds) < 4:
                err(f"decoys_1940.json declares only {len(nkinds)} kinds (need >= 4)")
            print(f"  decoys_1940: {len(arr)} sites, {len(nkinds)} kinds")
    # P5 curated period grid (the value is the fallback; data/osm/power.json from the real fetch is optional)
    pys = load(os.path.join(D, "pylons_1940.json"))
    if pys is not None:
        arr = pys.get("lines")
        if not isinstance(arr, list) or not arr:
            err("pylons_1940.json missing/empty 'lines' list")
        else:
            ids = set()
            for r in arr:
                for k in ("id", "name", "pts", "source"):
                    if k not in r:
                        err(f"pylons/{r.get('id')} missing '{k}'")
                pts = r.get("pts", [])
                if len(pts) < 2:
                    err(f"pylons/{r.get('id')} has {len(pts)} points (need >= 2)")
                for la, lo in pts:
                    if not (LAT_MIN <= la <= LAT_MAX and LON_MIN <= lo <= LON_MAX):
                        err(f"pylons/{r.get('id')} point out of bounds ({la}, {lo})")
                if r.get("id") in ids:
                    err(f"pylons duplicate id {r.get('id')}")
                ids.add(r.get("id"))
            print(f"  pylons_1940 (curated fallback): {len(arr)} lines")
    pp = os.path.join(D, "osm", "power.json")
    if os.path.exists(pp):
        pj = load(pp) or {}
        plines = pj.get("lines", [])
        print(f"  power (osm fetch): {len(plines)} lines")
        if not plines:
            err("data/osm/power.json exists but has 0 lines - an empty power layer must not stand in for the grid")
    else:
        print("  power (osm fetch): absent - runtime uses the curated period grid")


DECOY_KINDS = {"starfish", "qf_site", "q_site", "k_site"}
RAIL_DRAMA_KINDS = {"viaduct", "tunnel"}
OIL_FUEL_KINDS = {"refinery", "oil_depot", "tank_farm", "gasworks", "petrol_depot", "gas_holder"}


def check_new_1940():
    """P7/P9 hand-authored datasets: the famous rail viaducts/tunnels and the oil and fuel sites."""
    print("== railway drama + oil/fuel datasets")
    rd = load(os.path.join(D, "rail_drama_1940.json"))
    if rd is not None:
        arr = rd.get("sites")
        if not isinstance(arr, list) or not arr:
            err("rail_drama_1940.json missing/empty 'sites' list")
        else:
            ids = set()
            for r in arr:
                for k in ("id", "name", "kind", "lat", "lon", "source"):
                    if k not in r:
                        err(f"rail_drama/{r.get('id')} missing '{k}'")
                if r.get("kind") not in RAIL_DRAMA_KINDS:
                    err(f"rail_drama/{r.get('id')} bad kind {r.get('kind')!r}")
                la, lo = r.get("lat"), r.get("lon")
                if not (isinstance(la, (int, float)) and isinstance(lo, (int, float))
                        and LAT_MIN <= la <= LAT_MAX and LON_MIN <= lo <= LON_MAX):
                    err(f"rail_drama/{r.get('id')} lat/lon out of bounds ({la}, {lo})")
                if r.get("id") in ids:
                    err(f"rail_drama duplicate id {r.get('id')}")
                ids.add(r.get("id"))
            print(f"  rail_drama_1940: {len(arr)} structures")
    of = load(os.path.join(D, "oil_fuel_1940.json"))
    if of is not None:
        arr = of.get("sites")
        if not isinstance(arr, list) or not arr:
            err("oil_fuel_1940.json missing/empty 'sites' list")
        else:
            ids = set()
            for r in arr:
                for k in ("id", "name", "kind", "lat", "lon", "size", "team", "source"):
                    if k not in r:
                        err(f"oil_fuel/{r.get('id')} missing '{k}'")
                if r.get("kind") not in OIL_FUEL_KINDS:
                    err(f"oil_fuel/{r.get('id')} bad kind {r.get('kind')!r}")
                if r.get("team") not in ("Axis", "Allies"):
                    err(f"oil_fuel/{r.get('id')} bad team {r.get('team')!r}")
                if not (isinstance(r.get("size", 0), int) and 1 <= r.get("size", 0) <= 3):
                    err(f"oil_fuel/{r.get('id')} size out of range {r.get('size')!r}")
                la, lo = r.get("lat"), r.get("lon")
                if not (isinstance(la, (int, float)) and isinstance(lo, (int, float))
                        and LAT_MIN <= la <= LAT_MAX and LON_MIN <= lo <= LON_MAX):
                    err(f"oil_fuel/{r.get('id')} lat/lon out of bounds ({la}, {lo})")
                if r.get("id") in ids:
                    err(f"oil_fuel duplicate id {r.get('id')}")
                ids.add(r.get("id"))
            print(f"  oil_fuel_1940: {len(arr)} sites")


AIRCRAFT_INDUSTRY_KINDS = {"shadow_factory", "assembly_plant", "engine_works", "dispersal_site", "aircraft_depot"}
V_WEAPON_KINDS = {"ski_site", "supply_depot", "heavy_cross"}
PORT_CLUTTER_KINDS = {"crane", "lock_gate", "dredger", "hopper_barge", "tug", "paddle_steamer", "train_ferry"}


def _check_sites_file(name, kinds, min_kinds, keys):
    """Shared validator for the hand-authored {"_note","sites":[...]} datasets (P10/P11/P12)."""
    obj = load(os.path.join(D, name))
    if obj is None:
        return
    arr = obj.get("sites")
    if not isinstance(arr, list) or not arr:
        err(f"{name} missing/empty 'sites' list")
        return
    ids = set()
    nkinds = set()
    for r in arr:
        for k in keys:
            if k not in r:
                err(f"{name}/{r.get('id')} missing '{k}'")
        if r.get("kind") not in kinds:
            err(f"{name}/{r.get('id')} bad kind {r.get('kind')!r}")
        if r.get("team") not in ("Axis", "Allies"):
            err(f"{name}/{r.get('id')} bad team {r.get('team')!r}")
        if not (isinstance(r.get("size", 0), int) and 1 <= r.get("size", 0) <= 3):
            err(f"{name}/{r.get('id')} size out of range {r.get('size')!r}")
        la, lo = r.get("lat"), r.get("lon")
        if not (isinstance(la, (int, float)) and isinstance(lo, (int, float))
                and LAT_MIN <= la <= LAT_MAX and LON_MIN <= lo <= LON_MAX):
            err(f"{name}/{r.get('id')} lat/lon out of bounds ({la}, {lo})")
        if r.get("id") in ids:
            err(f"{name} duplicate id {r.get('id')}")
        ids.add(r.get("id"))
        nkinds.add(r.get("kind"))
    if len(nkinds) < min_kinds:
        err(f"{name} declares only {len(nkinds)} kinds (need >= {min_kinds})")
    print(f"  {name}: {len(arr)} sites, {len(nkinds)} kinds")


def check_p10_p12():
    """P10/P11/P12 hand-authored datasets: the aircraft industry, the V-weapons and the port clutter."""
    print("== aircraft industry + V-weapons + port clutter datasets")
    _check_sites_file("aircraft_industry_1940.json", AIRCRAFT_INDUSTRY_KINDS, 5,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))
    _check_sites_file("v_weapons_1940.json", V_WEAPON_KINDS, 3,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))
    _check_sites_file("port_clutter_1940.json", PORT_CLUTTER_KINDS, 7,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))


RURAL_KINDS = {"oast_house", "hop_garden", "orchard", "market_garden", "drainage_mill", "sheep_fold"}
COASTAL_LANDMARK_KINDS = {"martello_tower", "coastguard_station", "lifeboat_station", "lido", "bandstand", "holiday_camp"}
CIVIL_DEFENCE_KINDS = {"surface_shelter", "anderson_shelter", "arp_post", "sandbagged_building"}


def check_p13_p15():
    """P13/P14/P15 hand-authored datasets: the rural texture, the coastal landmarks and civil defence."""
    print("== rural + coastal landmarks + civil defence datasets")
    _check_sites_file("rural_1940.json", RURAL_KINDS, 6,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))
    _check_sites_file("coastal_landmarks_1940.json", COASTAL_LANDMARK_KINDS, 6,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))
    _check_sites_file("civil_defence_1940.json", CIVIL_DEFENCE_KINDS, 4,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))
    # every coastal-landmark kind must be a documented id in the landmark data model
    lm = load(os.path.join(D, "landmarks_1940.json"))
    cl = load(os.path.join(D, "coastal_landmarks_1940.json"))
    if lm is not None and cl is not None:
        ids = {str(e.get("id", "")) for e in lm.get("landmarks", [])}
        miss = sorted({str(r.get("kind", "")) for r in cl.get("sites", [])} - ids)
        if miss:
            err(f"coastal_landmarks kinds missing from landmarks_1940.json: {miss}")
        else:
            print(f"  coastal landmark kinds documented in landmarks_1940.json: {len(COASTAL_LANDMARK_KINDS)}")


AVIATION_SUPPORT_KINDS = {"seaplane_base", "airship_station", "kite_balloon_site"}
FORESTRY_KINDS = {"plantation", "timber_camp"}
NAVIGATION_AID_KINDS = {"radio_beacon", "df_station", "beacon_mast", "night_lighting"}
MILITARY_DEPTH_KINDS = {"transit_camp", "ammunition_depot", "vehicle_park", "horse_column", "tank_train"}


def check_p16_p19():
    """P16/P17/P18/P19 hand-authored datasets: aviation support, forestry, navigation aids, military depth."""
    print("== aviation support + forestry + navigation aids + military depth datasets")
    _check_sites_file("aviation_support_1940.json", AVIATION_SUPPORT_KINDS, 3,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))
    _check_sites_file("forestry_1940.json", FORESTRY_KINDS, 2,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))
    _check_sites_file("navigation_aids_1940.json", NAVIGATION_AID_KINDS, 4,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))
    _check_sites_file("military_depth_1940.json", MILITARY_DEPTH_KINDS, 5,
                      ("id", "name", "kind", "lat", "lon", "size", "team", "source"))


def main():
    L = check_locations()
    check_heightmap()
    check_osm(L)
    check_curated()
    check_landscape_1940()
    check_new_1940()
    check_p10_p12()
    check_p13_p15()
    check_p16_p19()
    print("== world coordinates (latlon_to_world, y=0)")
    if L:
        want = {"dover": "city", "calais": "city", "london": "city", "antwerp": "city",
                "biggin_hill": "airfield"}
        for sec in ("cities", "airfields"):
            for r in L[sec]:
                if r["id"] in want:
                    x, y, z = latlon_to_world(r["lat"], r["lon"])
                    print(f"  {r['name']:12s} lat {r['lat']:.4f} lon {r['lon']:.4f} -> ({x:9.1f}, {y:.0f}, {z:9.1f})")
        x0, _, z0 = latlon_to_world(LAT_MAX, LON_MIN)
        x1, _, z1 = latlon_to_world(LAT_MIN, LON_MAX)
        print(f"  playable bounds in world: x {x0:.0f}..{x1:.0f}  z {z0:.0f}..{z1:.0f}  "
              f"(~{(x1 - x0) / 1000:.1f} x {(z1 - z0) / 1000:.1f} km)")
    for w in warns:
        print("WARN:", w)
    print("RESULT:", "FAIL" if errors else "PASS", f"({len(errors)} errors)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
