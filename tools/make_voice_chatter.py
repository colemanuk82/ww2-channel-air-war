"""Quiet-spell / lull / air-support radio lines (generated voices, edge-tts).

One source of truth: this file writes
  assets/voice/voice_chatter.csv   (read by tools/generate_voices_edge.py -> assets/voice/<side>/<category>_<n>.mp3)
  scripts/radio_chatter.gd         (const LINES, the text shown as subtitle; Radio.play_line / chatter_clip use it)

    python tools/make_voice_chatter.py                 # rewrite both files
    python tools/generate_voices_edge.py --csv voice_chatter.csv --missing

Axis lines are English read by German voices (the convention of every other Axis line), with the odd German word.
Never use recorded / commercial audio: only these generated voices (assets/voice/ is allow-listed).
"""
import csv
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# role -> sender name used on the subtitle line by the game ("wing" = a wingman's callsign)
# speaker names are the keys of CAST in tools/generate_voices_edge.py
A_W, A_P, A_S, A_C = "RAF wingman", "RAF pilot", "RAF section leader", "RAF sector controller"
X_W, X_P, X_C = "Luftwaffe wingman", "Luftwaffe pilot", "Luftwaffe controller"
A_T, X_T = "RAF airfield tower", "Luftwaffe airfield tower"

# category -> side -> [(role, speaker, text)]
DATA = {
    "lull_quiet": {
        "allies": [
            ("wing", A_W, "Bit quiet up here, isn't it?"),
            ("wing", A_W, "I don't like it, leader. It's too quiet."),
            ("wing", A_S, "Keep your eyes peeled, they're out there somewhere."),
            ("wing", A_W, "Nothing on the horizon, leader. Not a sausage."),
            ("wing", A_S, "Too quiet by half. Stay sharp, chaps."),
            ("wing", A_W, "Not a Hun in sight. It makes me nervous."),
            ("wing", A_P, "Sky is empty. Funny, that."),
            ("wing", A_W, "Quiet as the grave up here."),
            ("wing", A_S, "Anyone else got the jitters? It's far too quiet."),
            ("wing", A_W, "Control, any trade for us? Nothing up here."),
            ("ctl", A_C, "Nothing for you at present. Maintain patrol."),
            ("ctl", A_C, "No plots in your sector. Remain alert, it won't last."),
        ],
        "axis": [
            ("wing", X_W, "Quiet today, leader. Very quiet."),
            ("wing", X_W, "It is too quiet. I do not like it."),
            ("wing", X_P, "Eyes open, comrades. The Tommies are out there somewhere."),
            ("wing", X_W, "Nothing in the sky, leader. Not one Spitfire."),
            ("wing", X_W, "Ruhig heute. Too quiet for my taste."),
            ("wing", X_P, "Zu ruhig, Kameraden. Augen auf."),
            ("wing", X_W, "The sky is empty. Strange."),
            ("wing", X_P, "Not a Tommy in sight. This makes me nervous."),
            ("wing", X_W, "Quiet as a graveyard up here."),
            ("wing", X_W, "Jafu, any targets for us? We see nothing."),
            ("ctl", X_C, "Nothing for you at present. Maintain patrol."),
            ("ctl", X_C, "No contacts in your sector. Stay alert, it will not last."),
        ],
    },
    "lull_end": {
        "allies": [
            ("ctl", A_C, "Plots building over Calais. Twenty plus, angels fifteen."),
            ("ctl", A_C, "Control to patrol. Bandits approaching from the south-east, vector one-three-zero."),
            ("ctl", A_C, "Raid forming up behind Cap Gris-Nez. Thirty plus, angels twenty."),
            ("ctl", A_C, "Bandits crossing the French coast, heading north-west. Vector zero-four-zero, angels twelve."),
            ("ctl", A_C, "New plots over the Channel, heading for the Kent coast. Buster."),
            ("ctl", A_C, "Control to all aircraft. Enemy formation approaching Dungeness, forty plus, angels eighteen."),
            ("ctl", A_C, "Standby. Radar reports activity over Boulogne. Be ready."),
            ("ctl", A_C, "Hostiles building over the Pas de Calais. Stand by for vectors."),
        ],
        "axis": [
            ("ctl", X_C, "Indianer over the Channel. Twenty plus, height five thousand."),
            ("ctl", X_C, "Jafu to all aircraft. Indianer approaching Calais from the north-west, course three-one-zero."),
            ("ctl", X_C, "Many Tommies building over Kent. Stand by."),
            ("ctl", X_C, "Indianer crossing the coast near Dunkirk, heading out over the Channel, height four thousand."),
            ("ctl", X_C, "Radar reports contacts over the Thames estuary. Be ready."),
            ("ctl", X_C, "Enemy aircraft climbing out of Manston. Stand by for vectors."),
            ("ctl", X_C, "New contacts over the Channel. Forty plus, course one-five-zero, height five thousand."),
            ("ctl", X_C, "Control to patrol. Enemy fighters approaching Gris-Nez. Be alert."),
        ],
    },
    "support_land": {
        "allies": [
            ("ctl", A_C, "Control to all aircraft. Our troops are pinned down by enemy armour, requesting air support!"),
            ("ctl", A_C, "Any aircraft, any aircraft. Our lads are hard pressed on the ground, enemy tanks attacking. Request air support!"),
            ("ctl", A_C, "Control. Ground forces under heavy attack, anti-tank guns holding us down. Please assist!"),
            ("ctl", A_C, "Control to patrol. Enemy armour attacking our positions near the coast. Requesting air support now!"),
            ("ctl", A_C, "All aircraft, army reports a tank attack in progress. Can anyone give them a hand?"),
        ],
        "axis": [
            ("ctl", "Luftwaffe ground control", "Ground control to all aircraft. Our troops are pinned down by enemy armour, requesting air support!"),
            ("ctl", "Luftwaffe ground control", "Any aircraft, any aircraft. Our men are hard pressed, enemy tanks attacking. Request air support!"),
            ("ctl", "Luftwaffe ground control", "Ground control. Heavy attack on our positions, anti-tank guns are holding us down. Please assist!"),
            ("ctl", "Luftwaffe ground control", "Ground control to patrol. Enemy armour attacking near the coast. Requesting air support now!"),
            ("ctl", "Luftwaffe ground control", "All aircraft, the army reports a tank attack in progress. Can anyone help them?"),
        ],
    },
    "support_land_losing": {
        "allies": [
            ("ctl", A_C, "Control. We are being overrun, the enemy are through! Anything you can spare, please, now!"),
            ("ctl", A_C, "Control. Our line is collapsing, we need help immediately!"),
            ("ctl", A_C, "Control. They've broken through, we can't hold much longer. Air support, now!"),
            ("ctl", A_C, "Control. We're falling back. Any aircraft, please!"),
        ],
        "axis": [
            ("ctl", "Luftwaffe ground control", "Ground control. We are being overrun, the enemy is through! Anything you can spare, please, now!"),
            ("ctl", "Luftwaffe ground control", "Ground control. Our line is collapsing, we need help immediately!"),
            ("ctl", "Luftwaffe ground control", "Ground control. They have broken through, we cannot hold much longer. Air support, now!"),
            ("ctl", "Luftwaffe ground control", "Ground control. We are falling back. Any aircraft, please!"),
        ],
    },
    "support_land_thanks": {
        "allies": [
            ("ctl", A_C, "Control. Well done, the attack has been broken. Thank you."),
            ("ctl", A_C, "Control. Excellent work, the enemy armour is knocked out."),
            ("ctl", A_C, "Control. The army sends its thanks. That turned the battle."),
            ("ctl", A_C, "Control. Good shooting, they're falling back."),
        ],
        "axis": [
            ("ctl", "Luftwaffe ground control", "Ground control. Well done, the attack has been broken. Thank you."),
            ("ctl", "Luftwaffe ground control", "Ground control. Excellent work, the enemy armour is destroyed."),
            ("ctl", "Luftwaffe ground control", "Ground control. The army sends its thanks. That turned the battle."),
            ("ctl", "Luftwaffe ground control", "Ground control. Good shooting, they are falling back."),
        ],
    },
    "support_naval": {
        "allies": [
            ("ship", "Air-Sea Rescue", "Convoy under attack by E-boats! Any aircraft in the area, request immediate support!"),
            ("ship", "Air-Sea Rescue", "Mayday, mayday. Convoy under attack in the Channel! Any aircraft, request immediate air support!"),
            ("ship", "Air-Sea Rescue", "All aircraft, this is the escort. Enemy boats are among the convoy, we need air support!"),
            ("ship", "Air-Sea Rescue", "Convoy under attack! Any aircraft in the area, enemy torpedo boats are closing, please help!"),
            ("ship", "Air-Sea Rescue", "Escort to all aircraft. We are being attacked, the convoy is in trouble. Request support!"),
        ],
        "axis": [
            ("ship", "Luftwaffe sea rescue", "Convoy under attack by enemy boats! Any aircraft in the area, request immediate support!"),
            ("ship", "Luftwaffe sea rescue", "Mayday, mayday. Convoy under attack in the Channel! Any aircraft, request immediate air support!"),
            ("ship", "Luftwaffe sea rescue", "All aircraft, this is the escort. Enemy boats are among the convoy, we need air support!"),
            ("ship", "Luftwaffe sea rescue", "Convoy under attack! Any aircraft in the area, enemy torpedo boats are closing, please help!"),
            ("ship", "Luftwaffe sea rescue", "Escort to all aircraft. We are being attacked, the convoy is in trouble. Request support!"),
        ],
    },
    "support_naval_attack": {
        "allies": [
            ("ship", "Air-Sea Rescue", "All aircraft, we are engaging an enemy convoy and need air support. Any aircraft in the area, please assist!"),
            ("ship", "Air-Sea Rescue", "Boats to all aircraft. Enemy convoy sighted, we are going in. Request air cover!"),
            ("ship", "Air-Sea Rescue", "We are attacking an enemy convoy and the escorts are fighting back. Request air support!"),
            ("ship", "Air-Sea Rescue", "Any aircraft, any aircraft. Enemy ships ahead, we could use a hand!"),
        ],
        "axis": [
            ("ship", "Luftwaffe sea rescue", "All aircraft, we are engaging an enemy convoy and need air support. Any aircraft in the area, please assist!"),
            ("ship", "Luftwaffe sea rescue", "Boats to all aircraft. Enemy convoy sighted, we are going in. Request air cover!"),
            ("ship", "Luftwaffe sea rescue", "We are attacking an enemy convoy and the escorts are fighting back. Request air support!"),
            ("ship", "Luftwaffe sea rescue", "Any aircraft, any aircraft. Enemy ships ahead, we could use some help!"),
        ],
    },
    "support_naval_end": {
        "allies": [
            ("ship", "Air-Sea Rescue", "Thank you, aircraft. That was well timed."),
            ("ship", "Air-Sea Rescue", "Thanks for the help, aircraft. We're clear."),
            ("ship", "Air-Sea Rescue", "The attackers have broken off. Much obliged, aircraft!"),
            ("ship", "Air-Sea Rescue", "Good show, aircraft. They've turned away."),
            ("ship", "Air-Sea Rescue", "Thank you, aircraft. Drinks are on us."),
        ],
        "axis": [
            ("ship", "Luftwaffe sea rescue", "Thank you, aircraft. That was well timed."),
            ("ship", "Luftwaffe sea rescue", "Thanks for the help, aircraft. We are clear."),
            ("ship", "Luftwaffe sea rescue", "The attackers have broken off. Many thanks, aircraft!"),
            ("ship", "Luftwaffe sea rescue", "Good work, aircraft. They have turned away."),
            ("ship", "Luftwaffe sea rescue", "Thank you, aircraft. Well done."),
        ],
    },
    "support_naval_lost": {
        "allies": [
            ("ship", "Air-Sea Rescue", "She's going down. The ship is lost."),
            ("ship", "Air-Sea Rescue", "We've lost her. Abandoning ship."),
            ("ship", "Air-Sea Rescue", "Too late. The ship is lost, we're picking up survivors."),
            ("ship", "Air-Sea Rescue", "She's gone. Convoy scattered."),
        ],
        "axis": [
            ("ship", "Luftwaffe sea rescue", "She is going down. The ship is lost."),
            ("ship", "Luftwaffe sea rescue", "We have lost her. Abandoning ship."),
            ("ship", "Luftwaffe sea rescue", "Too late. The ship is lost, we are picking up survivors."),
            ("ship", "Luftwaffe sea rescue", "She is gone. Convoy scattered."),
        ],
    },
    # take-off clearance on the start of the roll (tower), good luck once away, wingman airborne check
    "takeoff_clear": {
        "allies": [
            ("twr", A_T, "Clear to take off. Wind two-four-zero, ten knots."),
            ("twr", A_T, "You're clear, off you go."),
            ("twr", A_T, "Runway's clear. Cleared for take-off."),
            ("twr", A_T, "Cleared for take-off, wind light and variable. Good luck."),
            ("twr", A_T, "You're clear to roll. Mind the crosswind."),
            ("twr", A_T, "Cleared to go. Nothing in the circuit."),
            ("twr", A_T, "All clear, you may take off when ready."),
        ],
        "axis": [
            ("twr", X_T, "Clear to take off. Wind two-four-zero, ten knots."),
            ("twr", X_T, "You are clear. Take off."),
            ("twr", X_T, "Runway is clear. Cleared for take-off."),
            ("twr", X_T, "Cleared for take-off, wind light. Hals- und Beinbruch."),
            ("twr", X_T, "You are clear to roll. Watch the crosswind."),
            ("twr", X_T, "Cleared to go. Nothing in the circuit."),
            ("twr", X_T, "Alles frei. You may take off when ready."),
        ],
    },
    "takeoff_away": {
        "allies": [
            ("ctl", A_C, "Good luck, Red Section. Good hunting."),
            ("twr", A_T, "Safe flight, and bring the kites back in one piece."),
            ("ctl", A_C, "Off you go, chaps. Good luck up there."),
            ("twr", A_T, "Airborne. Good luck, and happy landings."),
            ("ctl", A_C, "Good hunting. We'll have the kettle on when you get back."),
            ("twr", A_T, "Safe flight. Keep your eyes peeled."),
            ("ctl", A_C, "Good luck, leader. Control will keep an eye out for you."),
            ("twr", A_T, "Chocks away and cheerio. Look after yourselves."),
        ],
        "axis": [
            ("ctl", X_C, "Viel Glück, Rotte. Gute Jagd."),
            ("twr", X_T, "Safe flight, and bring everyone home in one piece."),
            ("ctl", X_C, "Hals- und Beinbruch!"),
            ("twr", X_T, "You are airborne. Good luck, and happy landings."),
            ("ctl", X_C, "Waidmannsheil! Good hunting."),
            ("twr", X_T, "Safe flight. Keep your eyes open."),
            ("ctl", X_C, "Good luck, leader. Jafü is watching for you."),
            ("twr", X_T, "Hals- und Beinbruch. Come back safely."),
        ],
    },
    "takeoff_check": {
        "allies": [
            ("wing", A_W, "Two, airborne."),
            ("wing", A_W, "Wheels up, Two with you."),
            ("wing", A_W, "Airborne and on your wing, leader."),
            ("wing", A_W, "Two's up, closing in."),
            ("wing", A_W, "Gear up. I've got you in sight, leader."),
            ("wing", A_W, "Off the ground. Right behind you."),
        ],
        "axis": [
            ("wing", X_W, "Zwei, airborne."),
            ("wing", X_W, "Wheels up, Zwei with you."),
            ("wing", X_W, "Airborne and on your wing, leader."),
            ("wing", X_W, "Zwei is up, closing in."),
            ("wing", X_W, "Fahrwerk drin. I have you in sight, leader."),
            ("wing", X_W, "Off the ground. Right behind you."),
        ],
    },
    "support_guns": {
        "allies": [
            ("coast", "Coastguard, Dover", "Dover under shellfire from Gris-Nez. Any aircraft, attack the batteries on the French coast!"),
            ("coast", "Coastguard, Dover", "Coastguard Dover to all aircraft. Heavy shelling of the town from across the Channel. Please attack the guns!"),
            ("coast", "Coastguard, Dover", "Dover is under bombardment from the French coast. Any aircraft able, silence those batteries!"),
            ("coast", "Coastguard, Dover", "Shells falling on the town. Cross-Channel guns firing from Gris-Nez. Request aircraft attack the batteries!"),
            ("coast", "Coastguard, Dover", "All aircraft, the long-range guns are firing on Dover again. Can anyone spare a pass at those batteries?"),
        ],
        "axis": [
            ("coast", "Luftwaffe ground control", "Battery report. Our guns at Gris-Nez are shelling Dover. Watch the coast for enemy fighters."),
            ("coast", "Luftwaffe ground control", "Ground control to all aircraft. The heavy guns are firing across the Channel. Keep the enemy off the batteries!"),
            ("coast", "Luftwaffe ground control", "Our long-range guns are bombarding Dover. Enemy aircraft may try to attack the batteries."),
            ("coast", "Luftwaffe ground control", "All aircraft, the Gris-Nez batteries are firing on Dover. Cover the coast, please."),
            ("coast", "Luftwaffe ground control", "Ground control. Shells are falling on Dover. Protect our guns from the Tommies!"),
        ],
    },
}

DESC = {
    "RAF wingman": "Male, about 21, young RAF pilot officer, Northern English accent, calm.",
    "RAF pilot": "Male, Polish fighter pilot (303 Squadron) speaking English.",
    "RAF section leader": "Male, New Zealand section leader.",
    "RAF sector controller": "Male, RAF sector controller, calm and measured, received pronunciation.",
    "Air-Sea Rescue": "Male, Cockney launch skipper, brisk.",
    "Coastguard, Dover": "Male, late 50s, weathered Kent coastguard.",
    "Luftwaffe wingman": "Male, about 21, young German fighter pilot, Bavarian accent in English.",
    "Luftwaffe pilot": "Male, Austrian fighter pilot, cheerful, accent in English.",
    "Luftwaffe controller": "Male, Luftwaffe fighter controller, precise and cool, German accent in English.",
    "Luftwaffe ground control": "Male, Luftwaffe ground control, German accent in English.",
    "Luftwaffe sea rescue": "Male, Hamburg sea rescue officer, dry, German accent in English.",
    "RAF airfield tower": "Female, early 20s, WAAF radio operator. Crisp Home Counties accent, bright and precise.",
    "Luftwaffe airfield tower": "Female, early 20s, Luftwaffe signals auxiliary (Nachrichtenhelferin). light German accent in English, clear and polite.",
}
SIDE_SENDER = {"allies": {"wing": "", "ctl": "Control", "twr": "Tower", "ship": "Convoy escort", "coast": "Coastguard Dover"},
               "axis": {"wing": "", "ctl": "Jafü", "twr": "Turm", "ship": "Convoy escort", "coast": "Gefechtsstand"}}


def gd_str(t):
    return '"' + t.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    rows = []
    out = ["extends RefCounted",
           "## GENERATED by tools/make_voice_chatter.py - do not edit by hand (edit the python, rerun it).",
           "## Quiet-spell, lull and air-support radio lines: LINES[category][\"Allies\"|\"Axis\"] = [[role, sender, text], ...].",
           "## Clip n of a list (1-based) is assets/voice/<allies|axis>/<category>_<n>.mp3 (assets/voice/voice_chatter.csv).",
           "## role: wing (a wingman's callsign), ctl (Control / Jafu), ship (convoy escort), coast (Coastguard / ground).",
           "", "const LINES := {"]
    cats = list(DATA.keys())
    for ci, cat in enumerate(cats):
        out.append("\t%s: {" % gd_str(cat))
        for si, side in enumerate(("allies", "axis")):
            items = []
            for n, (role, spk, text) in enumerate(DATA[cat][side], 1):
                rows.append({"file": "%s/%s_%d" % (side, cat, n), "side": side, "speaker": spk, "voice": DESC[spk],
                             "line": text, "speak": text, "direction": "urgent" if "!" in text and cat.startswith("support") else "calm"})
                items.append("[%s, %s, %s]" % (gd_str(role), gd_str(SIDE_SENDER[side][role]), gd_str(text)))
            out.append("\t\t%s: [%s]%s" % (gd_str("Allies" if side == "allies" else "Axis"), ",\n\t\t\t".join(items), "," if si == 0 else ""))
        out.append("\t}%s" % ("," if ci < len(cats) - 1 else ""))
    out.append("}")
    with open(os.path.join(ROOT, "scripts", "radio_chatter.gd"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    with open(os.path.join(ROOT, "assets", "voice", "voice_chatter.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["file", "side", "speaker", "voice", "line", "speak", "direction"])
        w.writeheader()
        w.writerows(rows)
    print("rows", len(rows))
    for cat in cats:
        print("  %-22s allies %2d  axis %2d" % (cat, len(DATA[cat]["allies"]), len(DATA[cat]["axis"])))


if __name__ == "__main__":
    main()
