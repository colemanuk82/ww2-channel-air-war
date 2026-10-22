#!/usr/bin/env python3
"""Synthetic validation of every mission in data/missions.json - no game launch.
Checks schema, references (airfield / targets / aircraft), side + aircraft consistency, airfield ownership on the mission
date, objective types vs role, land/sea placement from the heightmap, distances and estimated flight time vs the time limit,
scripted-event sanity (kind, aircraft, hostility, spacing, position), weather names and voice coverage.
Usage: python tools/validate_missions.py [--verbose] [--only <id-substring>]     exit code 1 if any ERROR."""
import argparse
import glob
import json
import math
import os
import re
import sys

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0
HORIZ = 1.0                                  # game units are 1 m of real distance (WorldCoords.HORIZ_COMPRESSION)
FIGHT_TYPES = {"strike": ("factory", "rail_yard", "port", "bridge", "battery", "radar", "v1_site"),
               "strafe": ("convoy_route", "battery", "rail_yard", "bridge", "port", "factory", "radar", "v1_site"),
               "escort": ("factory", "rail_yard", "port", "bridge", "battery", "radar", "v1_site"),
               "defend": ("factory", "rail_yard", "port", "bridge", "battery", "radar", "v1_site", "convoy_route")}
EVENT_KINDS = {"ambush", "raid", "flyby", "escort", "weather", "message"}
BOMBER_CAP = 84.0


def load(p):
    return json.load(open(os.path.join(ROOT, p), encoding="utf-8"))


def parse_catalog():
    s = open(os.path.join(ROOT, "scripts", "aircraft_catalog.gd"), encoding="utf-8").read()
    out = {}
    for name in ("ALLIED_FIGHTERS", "ALLIED_BOMBERS", "AXIS_FIGHTERS", "AXIS_BOMBERS"):
        m = re.search(name + r"\s*(?::\s*Array)?\s*(?::?=)\s*\[(.*?)\]", s, re.S)
        out[name] = re.findall(r'"([^"]+)"', m.group(1)) if m else []
    return out


def aircraft_stats():
    st = {}
    for f in glob.glob(os.path.join(ROOT, "data", "aircraft", "*.tres")):
        t = open(f, encoding="utf-8").read()
        g = lambda k: (re.search(r"(?m)^%s = (.+)$" % k, t) or [None, None])[1]
        st[os.path.basename(f)[:-5]] = {"max_speed": float(g("max_speed") or 100), "nation": (g("nation") or "").strip('"')}
    return st


def weather_names():
    s = open(os.path.join(ROOT, "scripts", "weather_manager.gd"), encoding="utf-8").read()
    block = s[s.index("const PRESETS"):]
    return set(re.findall(r'^\t"([a-z_]+)": \{', block, re.M))


def km(a, b):
    return math.hypot((a[0] - b[0]) * 111.0, (a[1] - b[1]) * 71.0)


class Height:
    def __init__(self):
        self.h = cv2.imread(os.path.join(ROOT, "data", "heightmap", "region_height.png"), cv2.IMREAD_UNCHANGED)
        self.H, self.W = self.h.shape[:2]

    def elev(self, lat, lon):
        x = int((lon - LON_MIN) / (LON_MAX - LON_MIN) * (self.W - 1))
        y = int((LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * (self.H - 1))
        return float(self.h[min(max(y, 0), self.H - 1), min(max(x, 0), self.W - 1)]) / 65535.0 * 1000.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    loc = load("data/locations.json")
    missions = load("data/missions.json")["missions"]
    T = {t["id"]: t for t in loc["targets"]}
    A = {x["id"]: x for x in loc["airfields"]}
    cat = parse_catalog()
    st = aircraft_stats()
    weathers = weather_names()
    ht = Height()
    voice_csv = set()
    for fn in ("voice_story.csv", "voice_generic.csv", "voice_places.csv"):
        p = os.path.join(ROOT, "assets", "voice", fn)
        if os.path.exists(p):
            voice_csv |= set(re.findall(r"^([a-z0-9_/]+),", open(p, encoding="utf-8").read(), re.M))
    side_ids = {"Allies": cat["ALLIED_FIGHTERS"] + cat["ALLIED_BOMBERS"], "Axis": cat["AXIS_FIGHTERS"] + cat["AXIS_BOMBERS"]}
    bombers = set(cat["ALLIED_BOMBERS"] + cat["AXIS_BOMBERS"])
    errors, warns, seen = [], [], set()
    n_checked = 0
    for m in missions:
        mid = m.get("id", "?")
        if a.only and a.only not in mid:
            continue
        n_checked += 1
        E = lambda msg: errors.append((mid, msg))
        W = lambda msg: warns.append((mid, msg))
        if mid in seen:
            E("duplicate id")
        seen.add(mid)
        for k in ("name", "date", "sides", "roles", "time_of_day", "weather"):
            if k not in m:
                E("missing field '%s'" % k)
        if not m.get("sides"):
            continue
        if m.get("weather") not in weathers:
            E("unknown weather '%s'" % m.get("weather"))
        if not (0.0 <= float(m.get("time_of_day", 12)) < 24.0):
            E("time_of_day out of range")
        date = str(m.get("date", ""))
        for sd in m["sides"]:
            side = sd["side"]
            role = (m.get("roles") or {}).get(side)
            if role is None:
                E("no role for side %s" % side)
                continue
            af = A.get(sd.get("start_airfield"))
            if af is None:
                E("start airfield '%s' does not exist" % sd.get("start_airfield"))
                continue
            if not af.get("in_bounds", True):
                E("start airfield out of map bounds")
            if ht.elev(af["lat"], af["lon"]) < 0.5:
                E("start airfield %s is over water" % af["id"])
            holder = "Allies" if af["side"] == "RAF" else "Axis"
            if af.get("liberated") and date >= af["liberated"]:
                holder = "Allies"
            if holder != side:
                W("start airfield %s is held by %s on %s (flak will be hostile)" % (af["id"], holder, date))
            if not sd.get("aircraft"):
                E("no aircraft for side %s" % side)
            for ac in sd.get("aircraft", []):
                if ac not in st:
                    E("aircraft '%s' has no data file" % ac)
                if ac not in side_ids[side]:
                    E("aircraft '%s' is not in the %s catalog" % (ac, side))
            objs = (m.get("objectives") or {}).get(side, [])
            if role in ("strike", "strafe", "escort", "defend") and not objs and role != "sweep":
                if role != "defend":
                    E("%s mission with no objectives" % role)
            owner_expected = {"strike": "enemy", "strafe": "enemy", "escort": "enemy", "defend": "own"}.get(role)
            for oid in objs:
                t = T.get(oid)
                if t is None:
                    E("objective '%s' does not exist" % oid)
                    continue
                if not t.get("in_bounds", True):
                    E("objective %s out of map bounds" % oid)
                want = side if owner_expected == "own" else ("Axis" if side == "Allies" else "Allies")
                if owner_expected and t["side_owner"] != want:
                    W("objective %s is owned by %s (expected %s for a %s mission)" % (oid, t["side_owner"], want, role))
                if t["type"] not in FIGHT_TYPES.get(role, ()):
                    W("objective %s type '%s' unusual for role %s" % (oid, t["type"], role))
                if t["type"] == "convoy_route":
                    p = t.get("path") or []
                    if len(p) < 2:
                        E("convoy route %s has no path" % oid)
                    else:
                        mid_pt = p[len(p) // 2]
                        sea = ht.elev(mid_pt[0], mid_pt[1]) < 0.5
                        if bool(t.get("naval")) != sea:
                            W("convoy %s naval flag (%s) disagrees with the heightmap at its midpoint" % (oid, bool(t.get("naval"))))
                elif ht.elev(t["lat"], t["lon"]) < 0.5 and t["type"] != "port":
                    W("target %s sits on sea level / water" % oid)
            # feasibility: round trip to the first objective at ~75 % of the aircraft's top speed vs the time limit
            if objs and objs[0] in T and role in ("strike", "strafe", "escort"):
                tp = (T[objs[0]]["lat"], T[objs[0]]["lon"])
                start_pt = (sd["spawn"]["lat"], sd["spawn"]["lon"]) if sd.get("spawn") else (af["lat"], af["lon"])
                d = km(start_pt, tp)                     # start (spawn point or field) -> objective
                if sd.get("aircraft"):
                    v = st.get(sd["aircraft"][0], {"max_speed": 100})["max_speed"] * 0.75
                    t_rt = ((d + km(tp, (af["lat"], af["lon"]))) * 1000.0 / HORIZ) / v      # ... and back to the home field
                    limit = float(m.get("time_limit", 1500))
                    if t_rt > 3600:
                        W("%.0f min of flying at 1:1 (use time compression, F5)" % (t_rt / 60.0))
                    if d < 4.0:
                        W("objective only %.1f km from the start field" % d)
                    if t_rt > limit:
                        E("round trip to %s needs ~%.0f s but the time limit is %.0f s (%.0f km real)" % (objs[0], t_rt, limit, d))
                    elif t_rt > limit * 0.8:
                        W("round trip ~%.0f s is close to the %.0f s limit (%.0f km real)" % (t_rt, limit, d))
            # events
            evs = m.get("events") or []
            if len(evs) > 8:
                W("%d scripted events" % len(evs))
            for e in evs:
                k = e.get("kind")
                if k not in EVENT_KINDS:
                    E("event with unknown kind '%s'" % k)
                    continue
                if k in ("weather", "message"):
                    if k == "weather" and e.get("weather") not in weathers:
                        E("weather event with unknown weather '%s'" % e.get("weather"))
                    continue
                if e.get("aircraft") not in st:
                    E("event aircraft '%s' has no data" % e.get("aircraft"))
                if not (LAT_MIN <= e["lat"] <= LAT_MAX and LON_MIN <= e["lon"] <= LON_MAX):
                    E("event position out of bounds")
                if not (1 <= int(e.get("count", 1)) <= 8):
                    E("event count %s" % e.get("count"))
                ac = e.get("aircraft")
                # runtime rule: the aircraft's own side flies it, so a shared event list works for both sides
                if ac not in side_ids["Allies"] and ac not in side_ids["Axis"]:
                    E("event aircraft '%s' is in neither side's catalog" % ac)
                if km((af["lat"], af["lon"]), (e["lat"], e["lon"])) < 5.0 and k in ("ambush", "raid"):
                    W("hostile %s starts %.1f km from the start field (paced + moved ahead at run time)" % (k, km((af["lat"], af["lon"]), (e["lat"], e["lon"]))))
            # catchability: bombers must be slower than the player's top speed
            if role in ("escort", "defend") and sd.get("aircraft"):
                pv = st[sd["aircraft"][0]]["max_speed"]
                if pv < BOMBER_CAP * 1.15 and sd["aircraft"][0] not in bombers:
                    W("player aircraft %s (%.0f u/s) barely faster than the bomber cruise cap (%.0f u/s)" % (sd["aircraft"][0], pv, BOMBER_CAP))
            # voice coverage (text always works; clips are optional)
            if mid.startswith("rh_"):
                base = "mission/%s/%s/start_1" % (mid, side.lower())
                if base not in voice_csv:
                    W("no place-name voice line for this mission")
    # report
    print("checked %d missions: %d errors, %d warnings" % (n_checked, len(errors), len(warns)))
    for mid, msg in errors:
        print("  ERROR  %-52s %s" % (mid[:52], msg))
    shown = 0
    for mid, msg in warns:
        if a.verbose or shown < 40:
            print("  warn   %-52s %s" % (mid[:52], msg))
            shown += 1
    if len(warns) > shown:
        print("  ... %d more warnings (use --verbose)" % (len(warns) - shown))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
