"""Ops Room tasking voice lines (free flight taskings, scripts/modes/ops_room.gd).

Writes assets/voice/voice_ops.csv (same columns as voice_lines.csv). Generate with:
    python tools/generate_voices_elevenlabs.py --csv assets/voice/voice_ops.csv --premade
Files land in assets/voice/ops/<allies|axis>/<key>.mp3. The Ops Room plays a clip when its file exists and
shows the full text (places, bearings, distances) on screen; the voiced line is the general part of the call.
"""
import csv
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "voice", "voice_ops.csv")

VOICE = {
    "RAF sector controller": "Male, mid 40s, RAF squadron leader. Received Pronunciation, calm, measured and unhurried even when urgent.",
    "Luftwaffe controller": "Male, mid 40s, Luftwaffe Major. German accent in English, precise, cool and formal.",
    "RAF wingman": "Male, about 21, young RAF pilot officer. Northern English (Yorkshire) accent, energetic, breathless in combat.",
    "Luftwaffe wingman": "Male, early 20s, young Luftwaffe Leutnant. German accent in English, eager, quick.",
    "Player (RAF leader)": "Male, late 20s, RAF flight lieutenant leading a section. Light RP, steady.",
    "Player (Luftwaffe leader)": "Male, late 20s, Luftwaffe Staffelkapitän. German accent in English, steady.",
    "RAF wing leader": "Male, early 30s, RAF wing commander leading the formation. Light Received Pronunciation, cool, confident, steady under fire.",
    "Luftwaffe formation leader": "Male, early 30s, Luftwaffe Gruppenkommandeur leading the formation. English with a German accent, hard, confident, clipped.",
}

CTRL = {"allies": "RAF sector controller", "axis": "Luftwaffe controller"}
WING = {"allies": "RAF wingman", "axis": "Luftwaffe wingman"}
PLAYER = {"allies": "Player (RAF leader)", "axis": "Player (Luftwaffe leader)"}
BOMB = {"allies": "RAF wing leader", "axis": "Luftwaffe formation leader"}

# key -> (speaker role, allies line, axis line, direction)
L = {}


def c(key, en, de=None, d="radio, controller"):
    L[key] = ("ctrl", en, de or en, d)


c("open_1", "This is Sector Control. New tasking for you.", "Jafü here. New orders for you.")
c("open_2", "Hello, Ops here.", "Ground control calling.")
c("open_3", "Sector here. New tasking for you.", "New orders from Jafü.")
c("open_4", "Ops Room. Listen carefully.", "Attention, Jafü here. Listen carefully.")

BRIEF = {
    "strike": (["Priority target for you. Bombs on it, please.", "Intelligence wants a target put out of action. Go and stop it.", "We've a target that needs knocking out. Expect flak."],
               ["Priority target for you. Bombs on it.", "Intelligence wants a target destroyed. Go and stop it.", "A target must be knocked out. Expect flak."]),
    "airfield": (["Their fighters are on the ground refuelling. Go and catch them there.", "An enemy airfield is full of aircraft. Shoot it up.", "We want an airfield put out of business. Anything you can hit."],
                 ["Their fighters are on the ground refuelling. Catch them there.", "An enemy airfield is full of aircraft. Attack it.", "That airfield must be put out of action. Anything you can hit."]),
    "convoy": (["A road convoy has been seen on the move. Find it and stop it.", "The Resistance reports a convoy heading for the front. Hit it.", "There's a column on the road. Strafe the lot."],
               ["An enemy convoy is moving on the roads. Find it and stop it.", "Our agents report a convoy heading for the coast. Hit it.", "There is a column on the road. Attack the whole column."]),
    "train": (["A train is leaving the yards. Stop that train.", "Railway watchers report a train running. Go for the locomotive first.", "Big train on the line. It must not get through."],
              ["A train is leaving the yards. Stop that train.", "A train is reported on the line. Hit the locomotive first.", "A heavy train is on the line. It must not get through."]),
    "shipping": (["A convoy is steaming along their coast. Sink what you can.", "Coastal Command has shipping for you. Escorts with it, watch the flak.", "Shipping strike. Go low and go fast."],
                 ["An English convoy is in the Channel. Sink what you can.", "Shipping is reported. Escorts with it, watch the flak.", "Attack on shipping. Low and fast."]),
    "eboats": (["Fast boats putting out to sea. Catch them before they reach our convoys.", "Radar has motor boats leaving harbour. Sink them.", "Boats heading out. They're quick, so get in close."],
               ["Enemy motor torpedo boats are putting out to sea. Catch them.", "Radar has fast boats leaving harbour. Sink them.", "Boats heading out. They are quick, so get in close."]),
    "intercept": (["Raid building up. Vector to intercept.", "Bandits approaching the coast with fighter escort. Get after them.", "Bombers heading inland. Intercept."],
                  ["Enemy bombers approaching. Intercept.", "Bombers with fighter escort crossing the coast. Get after them.", "Bombers heading inland. Intercept them."]),
    "cover": (["Our convoy is under attack by dive bombers. Get over there and break it up.", "The convoy is calling for help. Buster!", "Dive bombers going for our ships. Protect them."],
              ["Our ships are under attack by enemy bombers. Break it up.", "The convoy is calling for help. Full throttle!", "Bombers are going for our ships. Protect them."]),
    "sweep": (["Enemy fighters patrolling over their side. Sweep them out of the sky.", "Free hunt. Go and find their fighters.", "Their fighters are getting cocky. Teach them a lesson."],
              ["Enemy fighters are patrolling. Clear the sky.", "Free hunt. Go and find their fighters.", "Their fighters are getting bold. Teach them a lesson."]),
    "rescue": (["One of ours is down in the sea in a dinghy. Find him and circle low until the launch has a fix.", "Mayday picked up. A pilot in the drink. Circle him low so the boat can home in.", "A crew has ditched. Find the dinghy and stay with them."],
               ["One of ours is down in the sea in a dinghy. Find him and circle low until the rescue boat has a fix.", "Emergency call received. A pilot in the water. Circle him low so the boat can find him.", "A crew has ditched. Find the dinghy and stay with them."]),
    "recce": (["We need fresh photographs. One pass, low and wings level, then bring the film home.", "Photo job for you. A steady run over the top, then straight back to base.", "Group want pictures. Get them home and you've done your bit."],
              ["We need new photographs. One pass, low and wings level, then bring the film home.", "Reconnaissance job. A steady run over the top, then straight back to base.", "Command wants pictures. Bring them home."]),
    "escort": (["Bombers need an escort. Meet them at the rendezvous and see them to the target.", "Close escort job. Pick up the bombers at the rendezvous and keep the fighters off them.", "Our bombers are going in. Meet them and bring them home."],
               ["Our bombers need an escort. Meet them at the rendezvous and take them to the target.", "Close escort. Meet the bombers at the rendezvous and keep the enemy fighters away.", "Our bombers are going in. Meet them and bring them home."]),
    "intruder": (["Intruder job. Their bombers are coming home and the flare path is lit. Catch them in the circuit.", "Night intruder. Get over their airfield while they're landing.", "Their airfield is lit up for returning bombers. Go and spoil the party."],
                 ["Intruder mission. Their bombers are coming home and the runway lights are on. Catch them in the circuit.", "Night intruder. Get over their airfield while they are landing.", "Their airfield is lit for returning bombers. Go and spoil it for them."]),
}
for kind, (en, de) in BRIEF.items():
    for i in range(3):
        c("brief_%s_%d" % (kind, i + 1), en[i], de[i], "radio, controller, briefing")

c("scramble_1", "Scramble! Scramble! Raid approaching. Get airborne now!", "Alarmstart! Alarmstart! Raid approaching. Get airborne now!", "urgent, shouting")
c("scramble_good_1", "Good scramble. Now get after them.", "Good start. Now get after them.")
c("scramble_slow_1", "Slow off the mark there. Get after them!", "Too slow! Get after them!")
c("intel_followup_1", "Your report checks out. We're sending you back to it.", "Your report is confirmed. You go back there.")
c("rv_set_1", "Rendezvous first. They'll go in with you.", "First the rendezvous. They will fly in with you.")
c("rv_set_2", "Meet up with the others at the rendezvous point first.", "Meet the others at the rendezvous point first.")
c("rv_gone_1", "They couldn't wait any longer. They've gone on ahead.", "They could not wait. They have gone on ahead.")
c("bombers_at_rv_1", "The bombers are at the rendezvous. Take station on them.", "The bombers are at the rendezvous. Take position on them.")
c("escort_bandits_1", "Bandits ahead of the bombers! Get in among them!", "Enemy fighters ahead of the bombers! Attack them!", "urgent")
c("escort_lost_1", "We've lost the bombers. That's a bad business.", "We have lost the bombers. A bad business.", "sombre")
c("pressure_flak_1", "Expect more flak than usual. They've been well supplied lately.", "Expect more flak than usual. They have been well supplied.")
c("pressure_supply_1", "That one got through. Their flak will be stronger for it.", "That one got through. Their defences will be stronger now.", "sombre")
c("nothing_1", "Nothing for you at the moment. Carry on with your patrol.", "Nothing for you at the moment. Continue your patrol.")
c("timeup_1", "Time's up on that one. Never mind, stand by for the next tasking.", "Time is up. Never mind, wait for new orders.")
c("scrub_fog_1", "Met reports fog rolling in. Scrub the job and come home.", "The weather service reports fog coming in. Abort and come home.")
c("twist_raid_turn_1", "Change of plan. The raid has turned for another target!", "Change of plan. The bombers have turned for another target!", "urgent")
c("twist_convoy_hurry_1", "The convoy's taking a pasting. They won't last five minutes. Hurry!", "The convoy is taking heavy damage. They will not last five minutes. Hurry!", "urgent")
c("twist_deadline_1", "It's nearly at its destination. Once it gets into cover we've lost it. Six minutes!", "It is nearly at its destination. Once it is in cover we have lost it. Six minutes!")
c("twist_shore_1", "They're making for the shore batteries. You've got seven minutes.", "They are making for the coastal guns. You have seven minutes.")
c("twist_flak_1", "Recce says they've moved more flak in round the target. Go in fast and low.", "Reconnaissance reports more flak around the target. Go in fast and low.")
c("twist_scramble_1", "Heads up. They're scrambling fighters off that airfield.", "Attention. They are scrambling fighters from that airfield.", "urgent")
c("twist_more_bandits_1", "Two more bandits joining them. Watch yourself.", "Two more enemy fighters joining them. Watch yourself.")
c("twist_eboat_1", "Enemy boat heading for the dinghy! Don't let them pick him up.", "Enemy boat heading for the dinghy! Do not let them take him.", "urgent")
c("raid_bombed_1", "They've bombed the target. We were too late on that one.", "They have bombed the target. We were too late.", "sombre")
c("rescue_found_1", "You've found him! Stay low and circle so the launch can get a fix on you.", "You have found him! Stay low and circle so the boat can find you.")
c("rescue_lost_1", "They've picked him up. He'll see out the war in a prison camp, poor chap.", "They have taken him. He will spend the war in a prison camp.", "sombre")
c("rescue_bandits_1", "Two bandits heading your way. They've seen the dinghy too. Keep them off him!", "Two enemy fighters heading your way. They have seen the dinghy. Keep them away!", "urgent")
c("recce_photos_1", "Cameras running. Got them! Now get those pictures home in one piece.", "Cameras running. Got them! Now bring the pictures home.")
for i, (en, de) in enumerate([("Good show! Ops confirms the job's done.", "Well done! The job is confirmed."),
                              ("Splendid work. That's one off the board.", "Excellent work. Jafü is pleased."),
                              ("Well done, that's a confirmed result.", "Confirmed. The job is done. Stand by."),
                              ("Bang on. Group are delighted. Stand by for more.", "Well flown. That one is finished.")]):
    c("success_%d" % (i + 1), en, de, "radio, pleased")
c("fail_1", "Never mind. We'll get them next time.", "A pity. We will get them next time.", "sombre")
c("fail_2", "That one got away. Stand by.", "That one escaped. Stand by.", "sombre")
for i, (en, de) in enumerate([("Direct hit! That's the job done. Good shooting.", "Direct hit! The job is done. Good shooting."),
                              ("Strike confirmed! You've hit them. Job done.", "Hit confirmed! That is the job done."),
                              ("Ops here. We have a hit reported. Well done!", "Jafü here. A hit is reported. Well done!")]):
    c("hit_%d" % (i + 1), en, de, "radio, excited")
c("intel_ack_1", "Thank you. We'll pass that to Intelligence and lay something on.", "Understood. Intelligence will be informed.")
c("intel_ack_2", "Noted. That'll make a nice target for someone. Perhaps you.", "Noted. That will be a target soon. Perhaps for you.")
c("v1_alert_1", "Diver, diver! Flying bomb crossing the coast, heading for London.", None, "urgent")
c("v1_alert_2", "Diver! Diver! Doodlebug inbound for London. Get after it!", None, "urgent")
c("v1_impact_1", "A Diver got through. It's come down on the town.", None, "sombre")
c("v1_kill_1", "Good shooting! That Diver won't reach London.", None, "pleased")
c("bounce_1", "Bandits behind you! Break, break!", "Enemy fighters behind you! Break, break!", "urgent, shouting")
c("promoted_1", "Congratulations. You've been promoted.", "Congratulations. You have been promoted.", "warm")
c("award_1", "Signal from Group. You've been decorated. Well done.", "A message from command. You have been decorated. Well done.", "warm")

for i, (en, de) in enumerate([("Tally-ho, leader. Joining up on your wing.", "Leader in sight. Joining up."),
                              ("Got you visual. Forming up on you now.", "I see you. Forming up on your wing."),
                              ("There you are! Taking station on your left.", "There you are. Taking position on your left.")]):
    L["rv_join_%d" % (i + 1)] = ("wing", en, de, "radio, wingman")
L["intel_report_1"] = ("player", "Ops, I've spotted something down there. Sending a report.", "Control, I have spotted something down there. Sending a report.", "radio, calm")
L["bombers_join_1"] = ("bomb", "Good to see you, fighters. We're turning for the target now.", "Good to see you, fighters. We are turning for the target now.", "radio")
L["bombers_bombed_1"] = ("bomb", "Bombs gone! Bang on target. Thanks for the company, fighters.", "Bombs away! Right on target. Thank you, fighters.", "radio, relieved")

# v7.17: more takes of the calls heard on every job, follow-up jobs, runs of successes, out of ammunition,
# and the twist calls reworded without the old time limits
c("open_5", "Sector Control. Got a job for you.", "Jafü. A job for you.")
c("open_6", "Hello, Ops again. Something's come up.", "Ground control again. Something has come up.")
c("open_7", "Sector here. Are you receiving?", "Jafü here. Do you hear me?")
for i, (en, de) in enumerate([("While you're up there, something else close by.", "While you are up there, something else nearby."),
                              ("Don't go home yet. We've another one near you.", "Do not go home yet. Another job near you."),
                              ("Ops here. Since you're in the area...", "Jafü here. Since you are in the area..."),
                              ("Stay out a little longer. One more for you.", "Stay out a little longer. One more for you.")]):
    c("followup_%d" % (i + 1), en, de)
for i, (en, de) in enumerate([("Lovely job. Intelligence are very pleased with you.", "Good work. The General will hear of this."),
                              ("That's the stuff. Chalk that one up.", "Confirmed. A clean job, well done."),
                              ("Confirmed and logged. Nicely done.", "Excellent. That one is off the list."),
                              ("Well done indeed. The Wingco sends his compliments.", "Very good. Command sends its compliments.")]):
    c("success_%d" % (i + 5), en, de, "radio, pleased")
for i, (en, de) in enumerate([("Hard luck. Can't win them all.", "Bad luck. We cannot win them all."),
                              ("Damn. Well, it's done now. Stand by.", "That is a failure. Stand by for new orders."),
                              ("That's a miss, I'm afraid. Keep your chin up.", "A miss. Do better next time.")]):
    c("fail_%d" % (i + 3), en, de, "sombre")
c("hit_4", "Observers report a hit! Lovely shooting.", "Observers report a hit! Excellent shooting.", "radio, excited")
c("hit_5", "That's a hit! Job done, well flown.", "A hit! The job is done. Well flown.", "radio, excited")
c("streak_1", "That's three in a row. Group are taking notice.", "That is three in a row. Command is taking notice.", "warm")
c("streak_2", "Five on the trot! You're the talk of the mess tonight.", "Five in a row! The whole Geschwader is talking about you.", "warm, impressed")
c("streak_3", "Another one! There'll be a gong in this for you.", "Another one! There will be a decoration in this for you.", "warm")
c("winchester_1", "You're out of ammunition. Scrub that one. Go home and rearm, and we'll have more for you.", "You are out of ammunition. Abort. Go home and rearm, we will have more for you.")
c("rearmed_1", "Rearmed? Good. Stand by, we'll have something for you shortly.", "Rearmed? Good. Stand by, new orders shortly.")
c("twist_convoy_hurry_2", "The convoy's taking a real pasting down there. Hurry!", "The convoy is taking heavy damage. Hurry!", "urgent")
c("twist_deadline_2", "It's getting close to cover. Once it's in there we've lost it. Get a move on!", "It is nearly in cover. Once it is there we have lost it. Hurry!")
c("twist_shore_2", "They're making for the shore batteries. Catch them before they're under the guns.", "They are making for the coastal guns. Catch them before they reach them.")

rows = []
for key, (role, en, de, d) in L.items():
    for side in ("allies", "axis"):
        if side == "axis" and key.startswith("v1_"):
            continue      # V-1 alerts are an RAF affair
        spk = {"ctrl": CTRL, "wing": WING, "player": PLAYER, "bomb": BOMB}[role][side]
        line = en if side == "allies" else de
        rows.append(["ops/%s/%s" % (side, key), side, spk, VOICE[spk], line, line, d])

with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    w.writerows(rows)
print("wrote %d lines, %d characters -> %s" % (len(rows), sum(len(r[4]) for r in rows), OUT))
