#!/usr/bin/env python3
"""Create AircraftStats .tres files for the extra aircraft types (published figures).
Flight numbers go through apply_flight_models.derive(), so they follow the same rules as the
existing aircraft. gear_height = (-gear.y + gear.len + 0.02 + gear.r) * 1.1 (see PlaneBuilder)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apply_flight_models import derive, rewrite
TRES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "aircraft")

# id: (display, side, nation, ammo, bombs, guns, rockets, fire_rate, gear(y,len,r),
#      (vmax_kmh, climb, span, mass, area, turn))
NEW = {
    "bf110":    ("Messerschmitt Bf 110 C", "Axis", "Luftwaffe", 1000, 2, 6, 0, 12, (-0.8, 0.9, 0.4), (562, 10.5, 16.25, 4500, 38.4, 24)),
    "do17":     ("Dornier Do 17 Z", "Axis", "Luftwaffe", 1200, 12, 4, 0, 8, (-0.2, 1.0, 0.5), (410, 5.5, 18.0, 5200, 55.0, 38)),
    "ju52":     ("Junkers Ju 52/3m", "Axis", "Luftwaffe", 500, 0, 2, 0, 8, (-1.1, 1.3, 0.85), (275, 3.5, 29.25, 6510, 110.5, 45)),
    "fw200":    ("Focke-Wulf Fw 200 Condor", "Axis", "Luftwaffe", 1200, 8, 4, 0, 8, (-1.1, 1.3, 0.7), (360, 3.4, 33.0, 12950, 118.0, 50)),
    "blenheim": ("Bristol Blenheim Mk IV", "Allies", "RAF", 1200, 10, 3, 0, 9, (-0.7, 1.0, 0.5), (428, 7.0, 17.17, 4000, 43.6, 30)),
    "tempest":  ("Hawker Tempest Mk V", "Allies", "RAF", 800, 2, 4, 8, 12, (-0.5, 1.0, 0.4), (700, 17.0, 12.5, 4140, 28.0, 22)),
    "p38":      ("Lockheed P-38L Lightning", "Allies", "USAAF", 1200, 2, 5, 10, 13, (-0.6, 1.0, 0.4), (667, 15.0, 15.85, 5800, 30.4, 26)),
    "defiant":  ("Boulton Paul Defiant Mk I", "Allies", "RAF", 1000, 0, 4, 0, 11, None, (489, 8.4, 11.99, 2800, 23.2, 24)),
    "b25":      ("North American B-25J Mitchell", "Allies", "USAAF", 1600, 12, 6, 0, 10, (-0.7, 1.2, 0.55), (438, 6.0, 20.6, 9600, 56.0, 38)),
    "a20":      ("Douglas A-20G Havoc", "Allies", "USAAF", 1200, 10, 6, 0, 11, (-0.5, 1.0, 0.5), (510, 8.0, 18.69, 7000, 43.1, 30)),
    "c47":      ("Douglas C-47 Skytrain", "Allies", "USAAF", 200, 0, 2, 0, 6, (-1.1, 1.2, 0.7), (360, 4.5, 29.1, 8300, 91.7, 45)),
}

def gear_height(g):
    return round((-g[0] + g[1] + 0.02 + g[2]) * 1.1, 2)

for aid, (name, side, nation, ammo, bombs, guns, rockets, rate, gear, perf) in NEW.items():
    if gear is None:  # Defiant reuses the Hurricane airframe
        txt = open(os.path.join(TRES, "hurricane.tres"), encoding="utf-8").read()
        import re
        gh = re.search(r"^gear_height\s*=\s*(.+)$", txt, re.M).group(1)
    else:
        gh = gear_height(gear)
    lines = ['[gd_resource type="Resource" script_class="AircraftStats" load_steps=2 format=3]', "",
             '[ext_resource type="Script" path="res://scripts/aircraft_stats.gd" id="1"]', "", "[resource]",
             'script = ExtResource("1")', 'id = "%s"' % aid, 'display_name = "%s"' % name, 'side = "%s"' % side,
             'nation = "%s"' % nation, 'model_id = "%s"' % aid, "ammo = %d" % ammo]
    if bombs: lines.append("bombs = %d" % bombs)
    lines.append("gun_count = %d" % guns)
    if rockets: lines.append("rockets = %d" % rockets)
    lines += ["fire_rate = %d" % rate, "gear_height = %s" % gh]
    path = os.path.join(TRES, aid + ".tres")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    rewrite(path, aid, derive(*perf))
    print("wrote", aid)
