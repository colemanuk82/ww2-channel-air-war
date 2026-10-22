import csv, os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "voice", "voice_lines.csv")
os.makedirs(os.path.dirname(OUT), exist_ok=True)

rows = []  # id, side, speaker, line, direction


def add(i, side, spk, line, note=""):
    rows.append([i, side, spk, line, note])


CLOCK_A = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]

for side in ["allies", "axis"]:
    ax = side == "axis"
    ctl = "Luftwaffe controller" if ax else "RAF sector controller"
    wing = "Luftwaffe wingman" if ax else "RAF wingman"
    lead = "Player (Luftwaffe leader)" if ax else "Player (RAF leader)"
    tower = "Luftwaffe airfield tower" if ax else "RAF airfield tower"
    # control / tower
    add("intro_takeoff", side, ctl, "Kanal Control here. You are cleared for take-off. Good hunting." if ax else "This is Control. You are cleared for take-off. Good luck.", "calm, clipped")
    add("intro_scramble", side, ctl, "Alarmstart! Alarmstart! Enemy aircraft approaching the coast!" if ax else "Scramble, scramble! Enemy aircraft inbound!", "urgent")
    add("tower_land", side, tower, "Runway is clear. You are cleared to land." if ax else "Runway clear. You're cleared to land, use the brakes.", "calm")
    add("tower_land_wind", side, tower, "Strong crosswind on the field. Careful on approach, cleared to land." if ax else "Strong winds on the field, watch your crosswind. Cleared to land.", "calm")
    add("lost_contact", side, ctl, "We have lost contact with your wingman. Stay alert." if ax else "Lost contact with your wingman. Stay sharp.", "sombre")
    # spotting calls, one per clock position
    for n, w in enumerate(CLOCK_A, 1):
        add("bandits_%02d" % n, side, wing, ("Indians, %s o'clock!" if ax else "Bandits, %s o'clock!") % w, "alert")
    for n, w in enumerate(CLOCK_A, 1):
        add("bombers_%02d" % n, side, wing, ("Viermots, %s o'clock!" if ax else "Bombers, %s o'clock!") % w, "alert")
    # kills
    kp = ["Abschuss! Good shooting!", "Horrido! He's going down!", "He's burning, well done!", "Well done, leader!"] if ax else ["Splash one!", "Good shooting, leader!", "He's going down!", "Nice one!"]
    for n, t in enumerate(kp, 1):
        add("kill_player_%d" % n, side, wing, t, "excited")
    kf = ["Abschuss!", "Got him!", "One Tommy down!", "Kill confirmed!"] if ax else ["Splash one!", "Got him!", "Bandit down!", "Kill confirmed!"]
    for n, t in enumerate(kf, 1):
        add("kill_friend_%d" % n, side, wing, t, "excited")
    # damage
    hits = ["I'm hit! I'm hit!", "Taking fire, I need help!", "My engine is failing!", "I've lost power!"]
    for n, t in enumerate(hits, 1):
        add("hit_%d" % n, side, wing, t, "panicked, engine noise ok")
    add("smoke_warn", side, wing, "Leader, you're trailing smoke! Get out of there!", "urgent")
    add("leader_down", side, wing, "Leader is down! Leader's gone!", "shocked")
    # player orders
    add("order_alone", side, lead, "Anyone on this frequency? Nobody's flying with me.", "dry")
    for f, t in [("vic", "Form on me, vic formation."), ("echelon", "Form on me, echelon right."), ("line", "Form on me, line abreast."), ("trail", "Form on me, line astern.")]:
        add("order_form_" + f, side, lead, t, "commanding")
    add("order_attack", side, lead, "Attack my target!", "commanding")
    add("order_cover", side, lead, "Cover me, I'm going in.", "commanding")
    add("order_rtb", side, lead, "Break off and return to base.", "commanding")
    # replies
    for n, t in enumerate(["Roger, forming up.", "Copy, on your wing.", "Moving into position."], 1):
        add("reply_form_%d" % n, side, wing, t)
    for n, t in enumerate(["Tally-ho! Engaging.", "Roger, going in.", "Visual, attacking!"] if not ax else ["Pauke, pauke! Engaging.", "Understood, going in.", "Target in sight, attacking!"], 1):
        add("reply_attack_%d" % n, side, wing, t, "keen")
    for n, t in enumerate(["Negative, no target in sight.", "We don't have eyes on anything, leader."], 1):
        add("reply_notarget_%d" % n, side, wing, t)
    for n, t in enumerate(["Covering you, leader.", "Got your six.", "Roger, we have you covered."], 1):
        add("reply_cover_%d" % n, side, wing, t)
    for n, t in enumerate(["Copy, heading home.", "Roger, returning to base.", "Going home, good hunting."], 1):
        add("reply_rtb_%d" % n, side, wing, t)

# ambient chatter (one side each)
allies_chat = [
    ("RAF sector controller", "All aircraft, bandits angels one-five over Dover. Vector one-two-zero."),
    ("RAF sector controller", "Hello Blue Leader, twenty-plus bandits approaching Dungeness, angels twelve."),
    ("RAF sector controller", "Tiger squadron, pancake, pancake. Refuel and stand by."),
    ("RAF squadron leader", "Tally-ho! Tally-ho! Bandits nine o'clock low."),
    ("Coastguard, Dover", "Convoy entering the Downs, balloons flying. Fighter cover requested."),
    ("Observer Corps", "Raid four-two crossing the coast at Beachy Head, heading north."),
    ("RAF sector controller", "Cloud base two thousand feet over the Isle of Wight, visibility good."),
    ("RAF pilot", "Green Leader, I've got a glycol leak, returning to base."),
    ("RAF sector controller", "Hello all aircraft, enemy fighters sweeping over Folkestone. Keep a good lookout."),
    ("RAF section leader", "Yellow section, buster! Bombers heading for Manston."),
    ("Air-Sea Rescue", "Launch away from Ramsgate, searching for a pilot down off the North Foreland."),
]
axis_chat = [
    ("Luftwaffe controller", "All Jagdgruppen, enemy convoy in the Strait of Dover. Escort the Stukas."),
    ("Luftwaffe controller", "Achtung, Spitfires reported over Cap Gris-Nez, high."),
    ("Luftwaffe pilot", "Horrido! One Spitfire down near Folkestone."),
    ("Luftwaffe sea rescue", "Rescue boat leaving Boulogne for a pilot in the water."),
    ("Luftwaffe radar operator", "Large formation forming over Kent. Course south-east."),
    ("Luftwaffe controller", "Haze over the Channel, cloud base low at Calais."),
    ("Luftwaffe pilot", "Fuel is getting low, I am turning for home."),
    ("Luftwaffe controller", "Bombers turning for home over Dungeness, cover them across the coast."),
    ("Luftwaffe flak officer", "Calais flak engaging enemy aircraft over the harbour."),
]
for n, (spk, t) in enumerate(allies_chat, 1):
    add("chatter_%02d" % n, "allies", spk, t, "background radio chatter")
for n, (spk, t) in enumerate(axis_chat, 1):
    add("chatter_%02d" % n, "axis", spk, t, "background radio chatter")

SPEAK_GERMAN = False

# Optional German versions of the Luftwaffe lines (spoken in German; the English line is the on-screen subtitle).
UHR = ["eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf"]
DE = {
    "intro_takeoff": "Hier Kanal. Sie haben Starterlaubnis. Weidmannsheil!",
    "intro_scramble": "Alarmstart! Alarmstart! Feindliche Flugzeuge im Anflug auf die Küste!",
    "tower_land": "Landebahn ist frei. Landung freigegeben.",
    "tower_land_wind": "Starker Seitenwind am Platz. Vorsicht im Anflug, Landung freigegeben.",
    "lost_contact": "Wir haben keinen Kontakt mehr zu Ihrem Rottenflieger. Augen auf!",
    "kill_player_1": "Abschuss! Gut geschossen!",
    "kill_player_2": "Horrido! Der geht runter!",
    "kill_player_3": "Er brennt! Sauber gemacht!",
    "kill_player_4": "Gut gemacht, Rot Eins!",
    "kill_friend_1": "Abschuss!",
    "kill_friend_2": "Hab ihn!",
    "kill_friend_3": "Ein Tommy weniger!",
    "kill_friend_4": "Abschuss bestätigt!",
    "hit_1": "Ich bin getroffen! Ich bin getroffen!",
    "hit_2": "Ich bekomme Feuer, brauche Hilfe!",
    "hit_3": "Mein Motor setzt aus!",
    "hit_4": "Ich verliere Leistung!",
    "smoke_warn": "Rot Eins, Sie ziehen eine Rauchfahne! Raus da!",
    "leader_down": "Der Führer ist abgeschossen! Rot Eins ist weg!",
    "order_alone": "Ist jemand auf dieser Frequenz? Ich fliege allein.",
    "order_form_vic": "Aufschließen, Kette!",
    "order_form_echelon": "Aufschließen, Staffelung rechts!",
    "order_form_line": "Aufschließen, breite Front!",
    "order_form_trail": "Aufschließen, Reihe hintereinander!",
    "order_attack": "Greift mein Ziel an!",
    "order_cover": "Deckt mich, ich greife an!",
    "order_rtb": "Abbrechen, zurück zum Platz!",
    "reply_form_1": "Verstanden, schließe auf.",
    "reply_form_2": "Jawohl, bin an Ihrer Seite.",
    "reply_form_3": "Gehe in Position.",
    "reply_attack_1": "Pauke, Pauke!",
    "reply_attack_2": "Verstanden, greife an.",
    "reply_attack_3": "Ziel erkannt, greife an!",
    "reply_notarget_1": "Negativ, kein Ziel in Sicht.",
    "reply_notarget_2": "Wir sehen nichts, Rot Eins.",
    "reply_cover_1": "Ich decke Sie.",
    "reply_cover_2": "Habe Ihren Rücken frei.",
    "reply_cover_3": "Verstanden, wir decken Sie.",
    "reply_rtb_1": "Verstanden, fliege nach Hause.",
    "reply_rtb_2": "Jawohl, zurück zum Platz.",
    "reply_rtb_3": "Ab nach Hause. Weidmannsheil.",
    "chatter_01": "An alle Jagdgruppen: feindlicher Geleitzug in der Straße von Dover. Begleitschutz für die Stukas.",
    "chatter_02": "Achtung, Spitfires über Kap Gris-Nez gemeldet, Kirchturm hoch.",
    "chatter_03": "Horrido! Eine Spitfire bei Folkestone abgeschossen.",
    "chatter_04": "Seenotboot läuft aus Boulogne aus, Flugzeugführer im Wasser.",
    "chatter_05": "Großer Verband sammelt sich über Kent. Kurs Südost.",
    "chatter_06": "Dunst über dem Kanal, Wolkenuntergrenze niedrig bei Calais.",
    "chatter_07": "Mein Sprit wird knapp, ich drehe nach Hause ab.",
    "chatter_08": "Die Kampfflieger drehen über Dungeness ab, gebt ihnen Begleitschutz bis zur Küste.",
    "chatter_09": "Flak Calais beschießt feindliche Flugzeuge über dem Hafen.",
}
for n, w in enumerate(UHR, 1):
    DE["bandits_%02d" % n] = "Indianer auf %s Uhr!" % w
    DE["bombers_%02d" % n] = "Dicke Autos auf %s Uhr!" % w


# Casting: one consistent voice per speaker role.
VOICES = {
    "RAF sector controller": "Male, mid 40s, RAF squadron leader. Received Pronunciation, calm, measured and unhurried even when urgent.",
    "RAF airfield tower": "Female, early 20s, WAAF radio operator. Crisp Home Counties accent, bright and precise.",
    "RAF wingman": "Male, about 21, young RAF pilot officer. Northern English (Yorkshire) accent, energetic, breathless in combat.",
    "Player (RAF leader)": "Male, late 20s, RAF flight lieutenant. Light Received Pronunciation, confident, clipped and decisive.",
    "RAF squadron leader": "Male, mid 30s, Scottish (Glasgow) accent, gruff and commanding.",
    "RAF section leader": "Male, mid 20s, New Zealander, relaxed but sharp.",
    "RAF pilot": "Male, mid 20s, Polish pilot of No. 303 Squadron, strong Polish accent in English, steady.",
    "Coastguard, Dover": "Male, late 50s, Kentish coastguard, weathered, slow, a little gravelly.",
    "Observer Corps": "Male, about 50, civilian Royal Observer Corps volunteer, West Country (Devon) accent, careful.",
    "Air-Sea Rescue": "Male, early 40s, RAF rescue launch skipper, London Cockney accent, matter-of-fact, engine noise behind.",
    "Luftwaffe controller": "Male, mid 40s, Luftwaffe Major. German accent in English, precise, cool and formal.",
    "Luftwaffe airfield tower": "Female, early 20s, Luftwaffe signals auxiliary (Nachrichtenhelferin). light German accent in English, clear and polite.",
    "Luftwaffe wingman": "Male, about 21, young German fighter pilot, Bavarian accent in English, eager and excitable.",
    "Player (Luftwaffe leader)": "Male, late 20s, Staffelkapitaen. German accent in English, confident, crisp, few words.",
    "Luftwaffe pilot": "Male, mid 20s, Austrian (Viennese) accent in English, cheerful.",
    "Luftwaffe sea rescue": "Male, mid 40s, northern German (Hamburg) naval officer, dry and calm.",
    "Luftwaffe radar operator": "Male, late 20s, technical NCO, German accent in English, flat and monotone.",
    "Luftwaffe flak officer": "Male, mid 50s, gruff Luftwaffe flak officer, heavy German accent in English, shouting over gunfire.",
}

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    for r in rows:
        # Luftwaffe lines are spoken in English with a German accent (set SPEAK_GERMAN to voice the DE text instead)
        speak = DE.get(r[0], r[3]) if (r[1] == "axis" and SPEAK_GERMAN) else r[3]
        w.writerow(["%s/%s" % (r[1], r[0]), r[1], r[2], VOICES[r[2]], r[3], speak, r[4]])
print(len(rows), "lines ->", OUT)
