#!/usr/bin/env python3
"""Create data/aircraft/beaufort.tres (Bristol Beaufort Mk I, Coastal Command torpedo bomber) from the Blenheim's
stats file and the published figures: 2 x Bristol Taurus (1,130 hp), 418 km/h (260 mph) at 6,500 ft, span 17.63 m (57 ft
10 in), wing area 46.7 m2 (503 sq ft), empty 5,945 kg (13,107 lb) [Wikipedia, Bristol Beaufort]. One 18 in Mk XII torpedo
on the centreline (or a 1,500 lb bomb / mines; the game carries 4 light bombs instead), three .303 (nose, dorsal turret).
Run once: python tools/add_beaufort.py"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apply_flight_models import derive, rewrite, TRES

src = open(os.path.join(TRES, "blenheim.tres"), "rb").read().decode("utf-8").replace("\r\n", "\n")
txt = src
def setkv(t, k, v):
    return re.sub(r"^%s\s*=.*$" % k, "%s = %s" % (k, v), t, flags=re.M)
txt = setkv(txt, "id", '"beaufort"')
txt = setkv(txt, "display_name", '"Bristol Beaufort Mk I"')
txt = setkv(txt, "model_id", '"beaufort"')
txt = setkv(txt, "ammo", "3000")
txt = setkv(txt, "bombs", "4")
txt = setkv(txt, "gear_height", "2.83")
if "torpedoes" not in txt:
    txt = txt.replace("bombs = 4\n", "bombs = 4\ntorpedoes = 1\n")
path = os.path.join(TRES, "beaufort.tres")
open(path, "wb").write(txt.encode("utf-8"))
rewrite(path, derive(418, 6.0, 17.63, 5945, 46.7, 31))
print("wrote", path)
