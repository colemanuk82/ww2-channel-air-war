"""Adds the D-Day / Dunkirk missions (data in battle_data.py), their new targets, and bomber 'wing' formations
to the Blitz / bomber missions. Idempotent: re-running replaces the same ids. Run from the project root."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import battle_data as B

MODE = {"strike": "bombing", "strafe": "ground_attack", "defend": "defend", "sweep": "dogfight", "escort": "escort"}

NEW_TARGETS = [
 {"id": "battery_azeville", "name": "Azeville Battery", "type": "battery", "lat": 49.4896, "lon": -1.2787, "side_owner": "Axis"},
 {"id": "battery_crisbecq", "name": "Crisbecq Battery (St Marcouf)", "type": "battery", "lat": 49.4806, "lon": -1.2692, "side_owner": "Axis"},
 {"id": "battery_wn62_omaha", "name": "Omaha: Strongpoint WN62 (Colleville)", "type": "battery", "lat": 49.3633, "lon": -0.8553, "side_owner": "Axis"},
 {"id": "battery_mont_fleury", "name": "Gold: Mont Fleury Battery", "type": "battery", "lat": 49.3372, "lon": -0.5928, "side_owner": "Axis"},
 {"id": "battery_courseulles", "name": "Juno: Courseulles Strongpoint", "type": "battery", "lat": 49.3335, "lon": -0.4605, "side_owner": "Axis"},
 {"id": "battery_riva_bella", "name": "Sword: Riva Bella Battery", "type": "battery", "lat": 49.2872, "lon": -0.2548, "side_owner": "Axis"},
 {"id": "bridge_pegasus", "name": "Benouville (Pegasus) Bridge", "type": "bridge", "lat": 49.2447, "lon": -0.2748, "side_owner": "Axis"},
 {"id": "battery_gravelines", "name": "Gravelines Heavy Battery", "type": "battery", "lat": 51.0128, "lon": 2.1286, "side_owner": "Axis"},
 {"id": "battery_nieuport", "name": "Nieuport Heavy Battery", "type": "battery", "lat": 51.1356, "lon": 2.7513, "side_owner": "Axis"},
 {"id": "convoy_utah", "name": "Utah Beach Assault Waves", "type": "convoy_route", "lat": 49.55, "lon": -0.95, "side_owner": "Allies",
  "path": [[49.56, -0.92], [49.48, -1.00], [49.425, -1.10]], "naval": True},
 {"id": "convoy_omaha", "name": "Omaha Beach Assault Waves", "type": "convoy_route", "lat": 49.62, "lon": -0.88, "side_owner": "Allies",
  "path": [[49.62, -0.88], [49.50, -0.87], [49.40, -0.87]], "naval": True},
 {"id": "convoy_gold", "name": "Gold Beach Assault Waves", "type": "convoy_route", "lat": 49.55, "lon": -0.60, "side_owner": "Allies",
  "path": [[49.55, -0.60], [49.45, -0.60], [49.37, -0.60]], "naval": True},
 {"id": "convoy_sword", "name": "Sword Beach Assault Waves", "type": "convoy_route", "lat": 49.50, "lon": -0.30, "side_owner": "Allies",
  "path": [[49.50, -0.30], [49.40, -0.29], [49.33, -0.28]], "naval": True},
 {"id": "convoy_mulberry", "name": "Mulberry Harbour Supply Ships", "type": "convoy_route", "lat": 49.50, "lon": -0.70, "side_owner": "Allies",
  "path": [[49.55, -0.72], [49.45, -0.66], [49.40, -0.62]], "naval": True},
 {"id": "convoy_21panzer", "name": "21st Panzer Division Column", "type": "convoy_route", "lat": 49.12, "lon": -0.37, "side_owner": "Axis",
  "path": [[49.12, -0.37], [49.20, -0.37], [49.27, -0.33]]},
 {"id": "convoy_dunkirk_perimeter", "name": "German Armoured Column (Bergues)", "type": "convoy_route", "lat": 50.93, "lon": 2.50, "side_owner": "Axis",
  "path": [[50.93, 2.50], [50.97, 2.43], [51.01, 2.40]]},
 {"id": "convoy_la_panne", "name": "La Panne Evacuation Ships", "type": "convoy_route", "lat": 51.12, "lon": 2.58, "side_owner": "Allies",
  "path": [[51.12, 2.58], [51.20, 2.40], [51.25, 2.00]], "naval": True},
]

WINGS = {  # existing missions -> friendly bomber stream flying the target chain with the player
 "blitz_black_saturday": ("he111", 8, 2300), "blitz_london_dawn_fog": ("he111", 5, 2100), "blitz_birmingham_night": ("he111", 4, 2400),
 "blitz_portsmouth_dusk": ("ju88", 6, 2200), "blitz_plymouth_storm": ("he111", 5, 2000), "blitz_filton_day": ("ju88", 5, 2300),
 "blitz_weybridge_evening": ("do17", 5, 2100), "blitz_swansea_night": ("he111", 4, 2200), "blitz_derby_predawn": ("he111", 4, 2300),
 "blitz_southampton_night": ("ju88", 6, 2200),
 "bmb_coventry_night": ("he111", 6, 2400), "bmb_london_docks_night": ("he111", 6, 2200), "bmb_woolston_day": ("ju88", 5, 2300),
 "bmb_rochester_day": ("do17", 5, 2100), "bmb_lille_locos": ("b26", 5, 2400), "bmb_cologne_night": ("lancaster", 6, 2600),
 "bmb_krupp_night": ("lancaster", 6, 2600),
}


def build(m):
    sides, objectives, roles, protect, modes = [], {}, {}, {}, {}
    briefs = {}
    for side in ("Allies", "Axis"):
        s = m["sides"][side]
        sides.append({"side": side, "start_airfield": s["af"], "aircraft": s["ac"]})
        roles[side] = s["role"]
        modes[side] = MODE[s["role"]]
        if s["role"] == "defend":
            protect[side] = s["protect"]
            objectives[side] = s["protect"]
        else:
            objectives[side] = s["objs"]
        briefs[side] = s["brief"]
    ax = briefs["Axis"].split(". ")
    brief = briefs["Allies"] + " (Axis: " + ". ".join(ax[:2]).rstrip(".") + ".)"
    out = {"id": m["id"], "name": m["name"], "year": int(m["date"][:4]), "date": m["date"], "sides": sides,
           "objectives": objectives, "time_of_day": m["hour"], "weather": m["weather"], "brief": brief, "roles": roles,
           "protect": protect, "time_limit": m["limit"], "waves": 3, "difficulty_hint": m["diff"], "modes": modes,
           "_source": "D-Day / Dunkirk campaign"}
    if m.get("scene"):
        out["scene"] = m["scene"]
    wings = {side: m["sides"][side]["wing"] for side in ("Allies", "Axis") if m["sides"][side].get("wing")}
    if wings:
        out["wing_by_side"] = wings
    if m.get("events"):
        out["events"] = m["events"]
    return out


def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    lp = os.path.join(root, "data", "locations.json")
    loc = json.load(open(lp, encoding="utf-8"))
    have = {t["id"] for t in loc["targets"]}
    for t in NEW_TARGETS:
        if t["id"] not in have:
            t = dict(t)
            t["in_bounds"] = True
            loc["targets"].append(t)
    json.dump(loc, open(lp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    mp = os.path.join(root, "data", "missions.json")
    data = json.load(open(mp, encoding="utf-8"))
    ms = data["missions"]
    ids = {m["id"] for m in B.MISSIONS}
    ms[:] = [m for m in ms if m["id"] not in ids]
    for m in B.MISSIONS:
        ms.append(build(m))
    for m in ms:
        if m["id"] in WINGS:
            ac, n, alt = WINGS[m["id"]]
            side = m["sides"][0]["side"]
            m["wing_by_side"] = {side: {"count": n, "aircraft": ac, "alt_m": alt}}
    json.dump(data, open(mp, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("missions:", len(ms), "targets:", len(loc["targets"]))


main()
