"""Extra takes of the radio calls heard most often (v7.17), so the same recording doesn't come round every minute.

Writes assets/voice/voice_variants.csv (same columns as voice_lines.csv). Generate with:
    python tools/generate_voices_elevenlabs.py --csv assets/voice/voice_variants.csv --premade
Files land beside the originals in assets/voice/<allies|axis>/<key>.mp3. scripts/radio.gd only picks a variant
whose file exists, so nothing falls back to text-to-speech if a take is missing.
"""
import csv
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "voice", "voice_variants.csv")

VOICES = {
    "RAF sector controller": "Male, mid 40s, RAF squadron leader. Received Pronunciation, calm, measured and unhurried even when urgent.",
    "RAF airfield tower": "Female, early 20s, WAAF radio operator. Crisp Home Counties accent, bright and precise.",
    "RAF wingman": "Male, about 21, young RAF pilot officer. Northern English (Yorkshire) accent, energetic, breathless in combat.",
    "RAF squadron leader": "Male, mid 30s, Scottish (Glasgow) accent, gruff and commanding.",
    "RAF section leader": "Male, mid 20s, New Zealander, relaxed but sharp.",
    "RAF pilot": "Male, mid 20s, Polish pilot of No. 303 Squadron, strong Polish accent in English, steady.",
    "Coastguard, Dover": "Male, late 50s, Kentish coastguard, weathered, slow, a little gravelly.",
    "Observer Corps": "Male, about 50, civilian Royal Observer Corps volunteer, West Country (Devon) accent, careful.",
    "Air-Sea Rescue": "Male, early 40s, RAF rescue launch skipper, London Cockney accent, matter-of-fact, engine noise behind.",
    "Luftwaffe controller": "Male, mid 40s, Luftwaffe Major. German accent in English, precise, cool and formal.",
    "Luftwaffe airfield tower": "Female, early 20s, Luftwaffe signals auxiliary (Nachrichtenhelferin). light German accent in English, clear and polite.",
    "Luftwaffe wingman": "Male, about 21, young German fighter pilot, Bavarian accent in English, eager and excitable.",
    "Luftwaffe pilot": "Male, mid 20s, Austrian (Viennese) accent in English, cheerful.",
    "Luftwaffe sea rescue": "Male, mid 40s, northern German (Hamburg) naval officer, dry and calm.",
    "Luftwaffe radar operator": "Male, late 20s, technical NCO, German accent in English, flat and monotone.",
    "Luftwaffe flak officer": "Male, mid 50s, gruff Luftwaffe flak officer, heavy German accent in English, shouting over gunfire.",
}

rows = []


def add(key, side, spk, line, direction=""):
    rows.append(["%s/%s" % (side, key), side, spk, VOICES[spk], line, line, direction])


CLOCK = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]

# key base -> (allies takes, axis takes); numbering carries on from the originals in voice_lines.csv
TAKES = {
    "intro_takeoff": (2, ["Control here. Runway's clear, you're cleared for take-off. Good hunting.",
                          "You're clear to go. Keep your eyes peeled once you're up.",
                          "Cleared for take-off. The Channel's busy today, so watch yourself."],
                      ["Kanal Control. The runway is clear, take-off approved. Good hunting.",
                       "Cleared for take-off. Keep your eyes open over the coast.",
                       "Take-off approved. Many Tommies about today, so watch yourself."], "ctl", "calm, clipped"),
    "intro_scramble": (2, ["Scramble! Bandits approaching the coast, get airborne!",
                           "Scramble, scramble! Raid coming in, all aircraft get airborne now!"],
                       ["Alarmstart! Enemy bombers approaching, get airborne!",
                        "Alarm! Alarm! Raid coming in, all aircraft take off now!"], "ctl", "urgent"),
    "tower_land": (2, ["Hello, you're clear to land. Mind the craters by the perimeter.",
                       "Cleared to land. Welcome home.",
                       "Runway's yours. Cleared to land, and mind the bowser on the left."],
                   ["Cleared to land. Welcome back.",
                    "The runway is free. Landing approved.",
                    "Landing approved. Watch the bomb craters at the edge of the field."], "tower", "calm"),
    "tower_land_wind": (2, ["It's gusty down here, watch the crosswind. Cleared to land.",
                            "Wind's picked up across the runway. Take care. Cleared to land."],
                        ["Strong gusts on the field. Careful. Landing approved.",
                         "The crosswind is strong today. Landing approved."], "tower", "calm"),
    "lost_contact": (2, ["We've lost your wingman's signal. Keep a good lookout.",
                         "No contact with your number two. Stay sharp."],
                     ["Your wingman is not answering. Stay alert.",
                      "We have lost your Rottenflieger. Watch yourself."], "ctl", "sombre"),
    "smoke_warn": (2, ["Leader, you're on fire! Get out of there!",
                       "You're streaming glycol, leader! Head for home!"],
                   ["Leader, you are burning! Get out!",
                    "You are trailing smoke, leader! Turn for home!"], "wing", "urgent"),
    "leader_down": (2, ["Leader's bought it! He's gone in!"],
                    ["Leader is hit! He is going down!"], "wing", "shocked"),
    "kill_player": (5, ["Wizard shooting, leader!", "That's one for the book!", "Smack on, he's had it!", "Flamer! Good show!"],
                    ["Horrido! Wonderful shooting!", "He is finished, leader!", "Good hit! He is burning!", "Another one for you, leader!"], "wing", "excited"),
    "kill_friend": (5, ["I got him! He's going in!", "Flamer! One destroyed!", "That bandit's had it!", "Scratch one!"],
                    ["Horrido! He is down!", "I got him!", "One Spitfire less!", "Abschuss! He is burning!"], "wing", "excited"),
    "hit": (5, ["I've been hit, losing oil pressure!", "Something's hit me, I can't see for smoke!", "They've got me! I'm hit!"],
            ["I am hit, losing oil!", "Smoke in the cockpit, I cannot see!", "They got me! I am hit!"], "wing", "panicked, engine noise ok"),
    "reply_form": (4, ["Roger, closing up.", "On my way, leader."], ["Understood, closing up.", "Coming, leader."], "wing", ""),
    "reply_attack": (4, ["Going in now!", "Tally-ho! He's mine!"], ["Attacking now!", "Horrido! He is mine!"], "wing", "keen"),
    "reply_cover": (4, ["Right behind you, leader."], ["Right behind you, leader."], "wing", ""),
    "reply_rtb": (4, ["Wilco. Heading for home."], ["Jawohl. Heading home."], "wing", ""),
    "reply_notarget": (3, ["Can't see a thing, leader."], ["Nothing in sight, leader."], "wing", ""),
}

ROLE = {
    "allies": {"ctl": "RAF sector controller", "tower": "RAF airfield tower", "wing": "RAF wingman"},
    "axis": {"ctl": "Luftwaffe controller", "tower": "Luftwaffe airfield tower", "wing": "Luftwaffe wingman"},
}

for base, (start, al, ax, role, d) in TAKES.items():
    for side, lines in (("allies", al), ("axis", ax)):
        for i, t in enumerate(lines):
            add("%s_%d" % (base, start + i), side, ROLE[side][role], t, d)

# spotting calls: two more takes per clock position (suffix _b, _c)
SPOT = {
    "allies": {"bandits": ["Watch it, bandits {n} o'clock!", "Enemy fighters, {n} o'clock! Heads up!"],
               "bombers": ["Bombers at {n} o'clock, leader!", "Big formation, {n} o'clock!"]},
    "axis": {"bandits": ["Achtung, Indians at {n} o'clock!", "Enemy fighters, {n} o'clock!"],
             "bombers": ["Heavies at {n} o'clock!", "Bomber formation, {n} o'clock!"]},
}
for side in ("allies", "axis"):
    for kind, takes in SPOT[side].items():
        for n, w in enumerate(CLOCK, 1):
            for suffix, t in zip(("b", "c"), takes):
                add("%s_%02d_%s" % (kind, n, suffix), side, ROLE[side]["wing"], t.format(n=w), "alert")

# more background chatter (it comes round every couple of minutes)
CHAT_ALLIES = [
    ("RAF sector controller", "Hello Red Leader, vector two-seven-zero, angels eighteen. Bandits over Maidstone."),
    ("RAF sector controller", "All aircraft, plots fading over the Channel. Resume patrol."),
    ("RAF squadron leader", "Blue section, line astern, follow me down. Keep it tight."),
    ("RAF section leader", "Green Two, you're straggling. Close up, there's a good chap."),
    ("RAF pilot", "Red Three here. Bandit destroyed, one damaged, coming home."),
    ("Observer Corps", "Raid five-one, fifteen-plus, over Ashford at ten thousand. Heading north-west."),
    ("Coastguard, Dover", "Two ships of the convoy hit off Folkestone. Lifeboat launched."),
    ("Air-Sea Rescue", "Picked him up off Margate. Cold and cross, but he'll do."),
    ("RAF sector controller", "Hello all aircraft, balloons are flying over Dover. Keep clear below five thousand."),
]
CHAT_AXIS = [
    ("Luftwaffe controller", "All Staffeln, the Stukas are over the target. Hold your height above them."),
    ("Luftwaffe controller", "Achtung, Hurricanes climbing over Dungeness. Strength twelve."),
    ("Luftwaffe pilot", "Two Spitfires below us, I am going down. Cover me."),
    ("Luftwaffe radar operator", "Plots over Kent are breaking up. Enemy fighters landing."),
    ("Luftwaffe sea rescue", "Seaplane on its way to the pilot off Cap Gris-Nez."),
    ("Luftwaffe flak officer", "Boulogne flak! Aircraft over the harbour, open fire!"),
    ("Luftwaffe pilot", "My radiator is hit. I am going home at low level."),
    ("Luftwaffe controller", "Bomber formation returning over Calais. All fighters, escort them home."),
]
for n, (spk, t) in enumerate(CHAT_ALLIES, 12):
    add("chatter_%02d" % n, "allies", spk, t, "background radio chatter")
for n, (spk, t) in enumerate(CHAT_AXIS, 10):
    add("chatter_%02d" % n, "axis", spk, t, "background radio chatter")

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    w.writerows(rows)
print("wrote %d lines, %d characters -> %s" % (len(rows), sum(len(r[4]) for r in rows), OUT))

