"""Bulk batch of radio takes (v7.18): spends the rest of the ElevenLabs credits. Rows are in priority order and the
background chatter comes last, so if the credits run out part-way only chatter is lost; the game uses only the
takes whose recordings exist. Generate with:
    python tools/generate_voices_elevenlabs.py --csv assets/voice/voice_bulk.csv --premade
"""
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_voice_more import V, ROLE  # noqa: E402  (also rewrites voice_more.csv, harmless)
from make_voice_bulk_data import SPOT, WING, BRIEF, OPS, CHAT  # noqa: E402
from make_voice_more_data import BRIEF_SIX  # noqa: E402
HAS_SIX = {k for k, _a, _x in BRIEF_SIX}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "voice", "voice_bulk.csv")
V = dict(V)
V["Air-Sea Rescue"] = "Male, early 40s, RAF rescue launch skipper, London Cockney accent, matter-of-fact, engine noise behind."
V["Luftwaffe sea rescue"] = "Male, mid 40s, northern German (Hamburg) naval officer, dry and calm."
CLOCK = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
rows = []


def add(file, side, spk, line, d=""):
    rows.append([file, side, spk, V[spk], line, line, d])


for side in ("allies", "axis"):
    for kind, takes in SPOT[side].items():
        for n, w in enumerate(CLOCK, 1):
            for sfx, t in zip(("e", "f"), takes):
                add("%s/%s_%02d_%s" % (side, kind, n, sfx), side, ROLE[side]["wing"], t.format(n=w.capitalize()), "alert")
for key, start, al, ax, d in WING:
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("%s/%s_%d" % (side, key, start + i), side, ROLE[side]["wing"], t, d)
for kind, (al, ax) in BRIEF.items():
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("ops/%s/brief_%s_%d" % (side, kind, (7 if kind in HAS_SIX else 6) + i), side, ROLE[side]["ctl"], t, "radio, controller, briefing")
for key, start, al, ax in OPS:
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("ops/%s/%s_%d" % (side, key, start + i), side, ROLE[side]["ctl"], t, "radio, controller")
for side, first in (("allies", 35), ("axis", 32)):
    for n, (_call, spk, t) in enumerate(CHAT[side], first):
        add("%s/chatter_%02d" % (side, n), side, spk, t, "background radio chatter")

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    w.writerows(rows)
print("wrote %d lines, %d characters -> %s" % (len(rows), sum(len(r[4]) for r in rows), OUT))
