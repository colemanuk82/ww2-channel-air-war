"""Third batch of radio takes (v7.18), written to spend the remaining ElevenLabs credits, most-heard first.

Writes assets/voice/voice_more.csv. Generate with:
    python tools/generate_voices_elevenlabs.py --csv assets/voice/voice_more.csv --premade
Rows are in priority order; if the credits run out part-way, the game simply uses the takes that exist.
"""
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "voice", "voice_more.csv")

V = {
    "RAF sector controller": "Male, mid 40s, RAF squadron leader. Received Pronunciation, calm, measured and unhurried even when urgent.",
    "Luftwaffe controller": "Male, mid 40s, Luftwaffe Major. German accent in English, precise, cool and formal.",
    "RAF airfield tower": "Female, early 20s, WAAF radio operator. Crisp Home Counties accent, bright and precise.",
    "Luftwaffe airfield tower": "Female, early 20s, Luftwaffe signals auxiliary (Nachrichtenhelferin). light German accent in English, clear and polite.",
    "RAF wingman": "Male, about 21, young RAF pilot officer. Northern English (Yorkshire) accent, energetic, breathless in combat.",
    "Luftwaffe wingman": "Male, about 21, young German fighter pilot, Bavarian accent in English, eager and excitable.",
    "RAF squadron leader": "Male, mid 30s, Scottish (Glasgow) accent, gruff and commanding.",
    "RAF section leader": "Male, mid 20s, New Zealander, relaxed but sharp.",
    "RAF pilot": "Male, mid 20s, Polish pilot of No. 303 Squadron, strong Polish accent in English, steady.",
    "Observer Corps": "Male, about 50, civilian Royal Observer Corps volunteer, West Country (Devon) accent, careful.",
    "Coastguard, Dover": "Male, late 50s, Kentish coastguard, weathered, slow, a little gravelly.",
    "Luftwaffe pilot": "Male, mid 20s, Austrian (Viennese) accent in English, cheerful.",
    "Luftwaffe radar operator": "Male, late 20s, technical NCO, German accent in English, flat and monotone.",
    "Luftwaffe flak officer": "Male, mid 50s, gruff Luftwaffe flak officer, heavy German accent in English, shouting over gunfire.",
}
ROLE = {"allies": {"ctl": "RAF sector controller", "tower": "RAF airfield tower", "wing": "RAF wingman"},
        "axis": {"ctl": "Luftwaffe controller", "tower": "Luftwaffe airfield tower", "wing": "Luftwaffe wingman"}}
rows = []


def add(file, side, spk, line, d=""):
    rows.append([file, side, spk, V[spk], line, line, d])


CLOCK = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]

# 1. wingman combat calls - heard in every fight (takes numbered on from v7.17)
from make_voice_more_data import WING_TAKES, BRIEF_MORE, CHAT_MORE, TOWER_MORE, BRIEF_SIX, OPS_MORE  # noqa: E402

for key, start, al, ax, d in WING_TAKES:
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("%s/%s_%d" % (side, key, start + i), side, ROLE[side]["wing"], t, d)

# 2. a fourth take of every spotting call (suffix _d)
for side in ("allies", "axis"):
    for kind, fmt in (("bandits", "Bandits! {n} o'clock, coming in fast!" if side == "allies" else "Indians! {n} o'clock, coming fast!"),
                      ("bombers", "Heavies, {n} o'clock! Lots of them!" if side == "allies" else "Bombers, {n} o'clock! Many of them!")):
        for n, w in enumerate(CLOCK, 1):
            add("%s/%s_%02d_d" % (side, kind, n), side, ROLE[side]["wing"], fmt.format(n=w.capitalize()), "alert")

# 3. Ops Room briefing headlines: takes 4 and 5 for every kind of job
for kind, al, ax in BRIEF_MORE:
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("ops/%s/brief_%s_%d" % (side, kind, 4 + i), side, ROLE[side]["ctl"], t, "radio, controller, briefing")

for kind, al, ax in BRIEF_SIX:
    for side, t in (("allies", al), ("axis", ax)):
        add("ops/%s/brief_%s_6" % (side, kind), side, ROLE[side]["ctl"], t, "radio, controller, briefing")
for key, al, ax in OPS_MORE:
    for side, t in (("allies", al), ("axis", ax)):
        add("ops/%s/%s" % (side, key), side, ROLE[side]["ctl"], t, "radio, pleased")

# 4. tower and take-off
for key, start, al, ax in TOWER_MORE:
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("%s/%s_%d" % (side, key, start + i), side, ROLE[side]["ctl" if key.startswith("intro") else "tower"], t, "calm")

# 5. more background chatter
for side, first, lines in (("allies", 21, CHAT_MORE["allies"]), ("axis", 18, CHAT_MORE["axis"])):
    for n, (spk, t) in enumerate(lines, first):
        add("%s/chatter_%02d" % (side, n), side, spk, t, "background radio chatter")

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    w.writerows(rows)
print("wrote %d lines, %d characters -> %s" % (len(rows), sum(len(r[4]) for r in rows), OUT))
