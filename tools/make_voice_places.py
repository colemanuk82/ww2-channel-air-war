"""Short place-name radio lines for the star (converted Rheinland) missions -> assets/voice/voice_places.csv.
Two clips per mission/side (start_1, win) naming the target area and the home airfield; every other call falls back to
the generic lines (voice_generic.csv). Run: python tools/make_voice_places.py, then generate with
  python tools/generate_voices_elevenlabs.py --csv assets/voice/voice_places.csv --model eleven_flash_v2_5"""
import ast
import csv
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tree = ast.parse(open(os.path.join(ROOT, "tools", "make_voice_story.py"), encoding="utf-8").read())
VOICES = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "VOICES")
LOC = json.load(open(os.path.join(ROOT, "data", "locations.json"), encoding="utf-8"))
TN = {t["id"]: t["name"] for t in LOC["targets"]}
AF = {a["id"]: a["name"] for a in LOC["airfields"]}


def place(tid):
    n = TN.get(tid, tid).replace('Terneuzer', 'Terneuzen')
    m = re.search(r" near (.+)$", n)
    if m:
        return m.group(1)
    return re.sub(r"\s*\(.*?\)", "", n)


rows = []
for m in json.load(open(os.path.join(ROOT, "data", "missions.json"), encoding="utf-8"))["missions"]:
    if not m["id"].startswith("rh_"):
        continue
    for s in m["sides"]:
        side = s["side"].lower()
        al = side == "allies"
        objs = m["objectives"].get(s["side"], [])
        pl = place(objs[0]) if objs else "the target area"
        field = AF.get(s["start_airfield"], s["start_airfield"].replace("rh_af_", "").replace("_", " ").title())
        role = m["roles"][s["side"]]
        ops = "RAF operations room" if al else "Luftwaffe ground control"
        if role == "defend":
            a = "All aircraft, raiders are heading for %s. Intercept them before they get there." % pl
            b = "%s is safe. The raid is turned back. Return to %s." % (pl, field)
        elif role == "escort":
            a = "All aircraft, you are escorting the bombers to %s. Cleared in from %s. Keep them alive." % (pl, field)
            b = "The bombers have hit %s and are heading home. Well done. Return to %s." % (pl, field)
        elif role == "sweep":
            a = "All aircraft, you are cleared for a fighter sweep out of %s. Engage any enemy fighters you find." % field
            b = "Sweep complete. Well done. Return to %s." % field
        else:
            a = "All aircraft, your target is at %s. Cleared in from %s. Hit it and return." % (pl, field)
            b = "%s has been hit. Well done. Return to %s." % (pl, field)
        for key, text, d in (("start_1", a, "radio, mid-battle"), ("win", b, "radio, end of mission")):
            rows.append(["mission/%s/%s/%s" % (m["id"], side, key), side, ops, VOICES[ops], text, text, d])
out = os.path.join(ROOT, "assets", "voice", "voice_places.csv")
with open(out, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    w.writerows(rows)
c = sum(len(r[5]) for r in rows)
print("wrote %s: %d clips, %d chars (~%d credits on flash)" % (out, len(rows), c, c // 2))
