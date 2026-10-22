"""Final v7.18 batch: spotting calls with height (high / low, two phrasings each), then more chatter as the sink
for whatever credits remain. Generate with:
    python tools/generate_voices_elevenlabs.py --csv assets/voice/voice_final.csv --premade
"""
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_voice_bulk import V, ROLE  # noqa: E402
from make_voice_final_data import CHAT2, CHAT3, BRIEF3, WING3  # noqa: E402
from make_voice_more_data import BRIEF_SIX  # noqa: E402
HAS_SIX = {k for k, _a, _x in BRIEF_SIX}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "voice", "voice_final.csv")
CLOCK = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
HEIGHT = {
    "allies": {"bandits": {"high": ["Bandits, {n} o'clock high!", "Look out, bandits above, {n} o'clock!"],
                           "low": ["Bandits, {n} o'clock low!", "Bandits below us, {n} o'clock!"]},
               "bombers": {"high": ["Bombers, {n} o'clock high!", "Bombers above us, {n} o'clock!"],
                           "low": ["Bombers, {n} o'clock low!", "Bombers below, {n} o'clock!"]}},
    "axis": {"bandits": {"high": ["Indians, {n} o'clock high!", "Achtung, Indians above, {n} o'clock!"],
                         "low": ["Indians, {n} o'clock low!", "Indians below us, {n} o'clock!"]},
             "bombers": {"high": ["Bombers, {n} o'clock high!", "Bombers above us, {n} o'clock!"],
                         "low": ["Bombers, {n} o'clock low!", "Bombers below, {n} o'clock!"]}},
}
rows = []


def add(file, side, spk, line, d=""):
    rows.append([file, side, spk, V[spk], line, line, d])


for side in ("allies", "axis"):
    for kind, hs in HEIGHT[side].items():
        for h, takes in hs.items():
            for n, w in enumerate(CLOCK, 1):
                for k, t in enumerate(takes):
                    add("%s/%s_%02d_%s%s" % (side, kind, n, h, "" if k == 0 else "2"), side, ROLE[side]["wing"], t.format(n=w.capitalize()), "alert")
for key, start, al, ax, d in WING3:
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("%s/%s_%d" % (side, key, start + i), side, ROLE[side]["wing"], t, d)
for kind, (al, ax) in BRIEF3.items():
    first = 10 if kind in HAS_SIX else 9
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("ops/%s/brief_%s_%d" % (side, kind, first + i), side, ROLE[side]["ctl"], t, "radio, controller, briefing")
for side, first in (("allies", 75), ("axis", 72)):
    for n, (_call, spk, t) in enumerate(CHAT2[side], first):
        add("%s/chatter_%02d" % (side, n), side, spk, t, "background radio chatter")

for side, first in (("allies", 111), ("axis", 108)):
    for n, (_call, spk, t) in enumerate(CHAT3[side], first):
        add("%s/chatter_%02d" % (side, n), side, spk, t, "background radio chatter")

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    w.writerows(rows)
print("wrote %d lines, %d characters -> %s" % (len(rows), sum(len(r[4]) for r in rows), OUT))
