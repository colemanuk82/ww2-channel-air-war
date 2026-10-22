"""Generic, mission-independent voice lines (briefing + radio calls per role/side) -> assets/voice/voice_generic.csv.
Used as the fallback for any historical mission without its own recordings (e.g. the diamond original missions).
Files: brief/generic_<role>_<side>.mp3 and generic/<role>/<side>/<key>.mp3 (roles: strike, strafe, defend).
Run:  python tools/make_voice_generic.py
Then (own terminal; key never goes in a file):  $env:ELEVENLABS_API_KEY = "<key>"
      python tools/generate_voices_elevenlabs.py --csv assets/voice/voice_generic.csv --model eleven_flash_v2_5"""
import ast
import csv
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tree = ast.parse(open(os.path.join(ROOT, "tools", "make_voice_story.py"), encoding="utf-8").read())
VOICES = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "VOICES")

BRIEF = {
    ("strike", "allies"): "Listen up. Today is a bombing sortie. Your targets are marked on the map. Expect flak over the target and enemy fighters if they scramble. Come in steady, drop on the mark, and get everyone home. Good luck.",
    ("strafe", "allies"): "Listen up. Today is a low-level strike. Your targets are on the map: vehicles, guns and anything that moves. Watch the flak, stay low and fast, and do not make a second pass over a hot target. Good luck.",
    ("defend", "allies"): "Listen up. The enemy is sending raiders against our installations today. Your job is to protect them. Hit the bombers before they reach the target, and do not chase fighters out of position. Good luck.",
    ("strike", "axis"): "Attention. Today is a bombing sortie. Your targets are marked on the map. Expect heavy flak and enemy fighters. Hold your formation, drop on the mark, and return to base. That is all.",
    ("strafe", "axis"): "Attention. Today is a low-level strike. Your targets are marked on the map. Stay low, watch the flak, and do not linger over the target. Return to base when it is done.",
    ("defend", "axis"): "Attention. Enemy bombers are coming for our installations today. You will intercept them before they reach the target. Bombers first, fighters second. Do not leave your sector. That is all.",
}
CALLS = {
    "strike": {"start_1": "All aircraft, you are cleared in. Bomb the target, then return to base.", "start_2": "Stay close, keep your eyes open. Here we go.", "first": "First target is down. Keep going.",
               "half": "Half the targets are destroyed. Keep it up.", "all": "All targets destroyed. Good work, now head for home.", "loss_1": "We are losing aircraft. Keep it tight.",
               "loss_2": "That one is hit hard. Stay in formation.", "win": "Objective complete. Well done, all of you. Return to base.", "lose": "The mission has failed. Return to base."},
    "strafe": {"start_1": "All aircraft, you are cleared in. Strike the targets, then return to base.", "start_2": "Stay low and fast. Here we go.", "first": "First target destroyed. Keep going.",
               "half": "Half the targets are down. Keep it up.", "all": "All targets destroyed. Good work, now head for home.", "loss_1": "We are taking hits. Stay low.",
               "loss_2": "That one is down. Watch the flak.", "win": "Targets destroyed. Well done, all of you. Return to base.", "lose": "The mission has failed. Return to base."},
    "defend": {"start_1": "All aircraft, raiders inbound. Intercept before they reach the target.", "start_2": "Bombers first. Stay sharp, here they come.", "first": "First raider down. Keep going.",
               "half": "Half the raid is down. Stay on them.", "all": "The raid is broken. Well done.", "loss_1": "A site has been hit. Get after them.",
               "loss_2": "Another site is hit. Stop those bombers.", "win": "The raid has been turned back. Well done, all of you.", "lose": "We have lost the targets. Return to base."},
}
rows = []
for side in ("allies", "axis"):
    al = side == "allies"
    for role in ("strike", "strafe", "defend"):
        spk = "RAF intelligence officer" if al else "Luftwaffe briefing officer"
        t = BRIEF[(role, side)]
        rows.append(["brief/generic_%s_%s" % (role, side), side, spk, VOICES[spk], t, t, "briefing, unhurried, with natural pauses"])
        for key, text in CALLS[role].items():
            who = ("RAF wing leader" if al else "Luftwaffe formation leader") if key in ("start_2", "first") else ("RAF operations room" if al else "Luftwaffe ground control")
            rows.append(["generic/%s/%s/%s" % (role, side, key), side, who, VOICES[who], text, text,
                         "radio, end of mission" if key in ("win", "lose") else "radio, mid-battle"])
# the pilot's own warnings (WeaponSystem._check_ammo): played as mode/<side>/ammo_low_N and ammo_out_N
VOICES["RAF pilot"] = "Male, mid 20s, RAF fighter pilot. Light Received Pronunciation, clipped and calm but tense, speaking over the radio in the middle of a fight."
VOICES["Luftwaffe pilot"] = "Male, mid 20s, Luftwaffe fighter pilot. English with a German accent, clipped and tense, speaking over the radio in the middle of a fight."
AMMO = {"ammo_low": ["Low on ammo.", "Running low on ammunition."], "ammo_out": ["Out of ammo! Guns empty.", "Guns are dry, I'm out of ammo!"]}
for side in ("allies", "axis"):
    spk = "RAF pilot" if side == "allies" else "Luftwaffe pilot"
    for key, texts in AMMO.items():
        for n, t in enumerate(texts, 1):
            rows.append(["mode/%s/%s_%d" % (side, key, n), side, spk, VOICES[spk], t, t, "radio, mid-battle, urgent"])
out = os.path.join(ROOT, "assets", "voice", "voice_generic.csv")
with open(out, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    w.writerows(rows)
chars = sum(len(r[5]) for r in rows)
print("wrote %s: %d clips, %d characters (~%d credits on eleven_flash_v2_5)" % (out, len(rows), chars, chars // 2))
