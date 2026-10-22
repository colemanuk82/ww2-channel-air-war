"""Briefings, training and in-mission dialogue for the voice generator.

Writes assets/voice/voice_story.csv (same columns as voice_lines.csv). Generate with:
    python tools/generate_voices_elevenlabs.py --csv assets/voice/voice_story.csv
Files land in assets/voice/<file>.mp3, e.g. brief/bob_kent_allies.mp3, training/allies/t_basic_intro.mp3,
mission/bob_kent/allies/start_1.mp3, mode/allies/bomb_target_1.mp3.
"""
import csv
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "voice", "voice_story.csv")

VOICES = {
    "RAF intelligence officer": "Male, mid 50s, RAF intelligence officer and First World War veteran. Received Pronunciation, dry wit, measured and grave, briefing young pilots in a crowded dispersal hut.",
    "Luftwaffe briefing officer": "Male, mid 50s, Luftwaffe Oberst giving a mission briefing. English with a German accent, stern, formal and precise.",
    "RAF flying instructor": "Male, early 40s, RAF flight sergeant flying instructor. Lancashire accent, patient, warm but firm, a little dry humour.",
    "Luftwaffe flying instructor": "Male, early 40s, Luftwaffe flying instructor (Fluglehrer). English with a German accent, strict but fair, clear and encouraging.",
    "RAF wing leader": "Male, early 30s, RAF wing commander leading the formation. Light Received Pronunciation, cool, confident, steady under fire.",
    "RAF operations room": "Male, mid 40s, RAF operations room controller. Welsh accent, calm and reassuring, slightly hoarse.",
    "Luftwaffe formation leader": "Male, early 30s, Luftwaffe Gruppenkommandeur leading the formation. English with a German accent, hard, confident, clipped.",
    "Luftwaffe ground control": "Male, mid 40s, Luftwaffe Gefechtsstand (ground control) officer. English with a German accent, cool, formal, unhurried.",
}

rows = []


def add(file, side, speaker, line, direction=""):
    rows.append([file, side, speaker, line, direction])


# ------------------------------------------------------------------ mission briefings (narration)
BRIEFS = {
    ("bob_kent", "allies"): "Right, settle down. Fifteenth of August. Jerry is coming over in strength this afternoon: Stukas and Heinkels, with a swarm of one-oh-nines up top. Their targets are the radar station at Dover and the Short Brothers works at Rochester. Without those masts we are blind, and without Shorts there are no more Stirlings. You will scramble from Biggin Hill and meet them over the coast. Go for the bombers first, leave the fighters to look after themselves if you can. Every raid you turn back is a factory still working tomorrow. Good luck, gentlemen.",
    ("bob_kent", "axis"): "Attention. Today is Adlertag plus two. The Reichsmarschall wants the English radar blinded. Your targets: the Chain Home stations at Dover and Dunkirk in Kent, and the Short Brothers aircraft works at Rochester. The Stukas will go in low, the Heinkels high, and the Messerschmitts will clear the sky above them. Expect Spitfires and Hurricanes the moment you cross the coast. Their radar sees you coming, so speed is everything. Destroy the masts and they will be fighting blind. That is all.",
    ("dieppe_1942", "allies"): "Nineteenth of August, before dawn. The Canadians are going ashore at Dieppe in force. Your job is to keep the Luftwaffe off the beaches and to silence what you can of their coastal defences. Targets are the radar at Antifer, the heavy guns on the cliffs and the harbour at Le Havre. Watch out for the new Focke-Wulf one-nineties: they are faster than you at low level and they climb like the devil. Stay in pairs, stay over the ships, and get those boys home.",
    ("dieppe_1942", "axis"): "Alarm. The English and Canadians are landing at Dieppe. A great fleet of landing craft and destroyers lies off the beach under a Spitfire umbrella. Your orders: attack the invasion fleet. Sink the landing craft and the transports, and break up the fighter cover. You fly the new Focke-Wulf. It is faster than anything they have, use it. Every boat you sink is a hundred men who never reach the shore.",
    ("dday_1944", "allies"): "Gentlemen, this is it. Sixth of June. The invasion of Europe begins this morning. Before the first landing craft touch the sand, the coastal batteries at Longues, Pointe du Hoc and Merville must be silenced, the radar at Douvres knocked out, and the bridge at Vernon dropped to stop the panzers coming up. After that, you stay over the fleet and keep the Luftwaffe off it. There will be more of our aircraft in the sky today than you have ever seen. Watch your recognition stripes, and God speed.",
    ("dday_1944", "axis"): "Kameraden. The invasion has come. The sea off Normandy is covered with ships from horizon to horizon. We have very few aircraft left in the west and they have thousands. Your orders are simple: attack the fleet. Landing craft, transports, anything you can reach. Come in low over the water, strike once and get out. Do not stay to fight the fighters. Every minute you delay them on the beach matters.",
    ("dunkirk_1940", "allies"): "Thirtieth of May. The army is on the beaches at Dunkirk, three hundred thousand of them, and the navy is bringing them home in anything that floats: destroyers, ferries, fishing boats, pleasure steamers. The Stukas are murdering them. You will patrol over the evacuation fleet from Manston. Keep the dive bombers off those ships, whatever it costs. The men on the beach will say they never saw the RAF. Prove them wrong.",
    ("dunkirk_1940", "axis"): "The British army is trapped at Dunkirk and trying to escape by sea. The harbour, the Mole and the beaches are full of ships. Your targets: the port of Dunkirk and the evacuation convoy. The Stukas will dive on the ships; the fighters will protect them from the Spitfires coming over from England. Smoke from the burning oil tanks lies over the town, use it. Do not let them get away.",
    ("antwerp_raid", "allies"): "October, nineteen forty-four. Antwerp is ours but the Germans are hitting it with V-weapons, and their fighters still hold the yards and factories along the docks. Tonight's target is the dock area and the Minerva works. You are on a straight bombing run across the Channel: stay in formation, hold your height, and do not wander off on your own. Intelligence reports jet fighters at Deurne. If you see something without a propeller going very fast, call it out.",
    ("antwerp_raid", "axis"): "Enemy bombers will attack the port of Antwerp and the Minerva works this afternoon. You will defend them. The Messerschmitt two-six-two is the fastest aircraft in the world. Do not turn with the escorts: dive through them, hit the bombers and climb away. Watch your fuel and watch your engines on landing, the enemy fighters wait for us over our own airfield.",
    ("lille_raid", "allies"): "Thirteenth of May. Marauders, escorted by Spitfires, will hit the Fives-Lille locomotive works and the rail yards beside it. No locomotives, no trains; no trains, no supplies for the German army in France. The Focke-Wulfs at Lille-Nord and Vendeville will come up to meet you. Stay with the bombers, keep the formation tight, and bring everyone home.",
    ("lille_raid", "axis"): "A large formation of Marauders with Spitfire escort is heading for Lille. Their target is the locomotive works at Fives and the rail yards. You will scramble from Lille-Nord. Go for the bombers, head-on if you can: their defensive fire is weakest from the front. The escorts are short of fuel this far inland, they cannot stay long.",
    ("lehavre_raid", "allies"): "Fifth of September. Le Havre is still held as a fortress and our troops are waiting outside. Before they go in, we hit the docks, the radar at Antifer and the bridge at Tancarville. The heavies go in first, the Typhoons follow with rockets on the flak positions. The flak here is heavy and accurate. Make one good run and get out.",
    ("lehavre_raid", "axis"): "Tonight we strike back. Your targets are the English harbours at Portsmouth and Southampton, where the supplies for the invasion are loaded. Fly low over the water to stay under their radar, climb at the coast and bomb from the attack height. Expect night fighters and balloons over both ports.",
    ("v1_sites", "allies"): "Operation Crossbow. The Germans are launching flying bombs at London from sites all over the Pas de Calais, and building something much bigger in those concrete bunkers at Wizernes, Mimoyecques, Watten, Eperlecques and Siracourt. Every one of them is ringed with flak. Go in fast, put your bombs or rockets on the concrete and do not hang about for a second look.",
    ("v1_sites", "axis"): "The enemy knows about the special weapon sites and will try to destroy them. Wizernes, Mimoyecques, Watten, Eperlecques and Siracourt must be protected at all costs. The flak will do its part. Your task is to break up the attackers before they reach their bombing run. Typhoons come in low and fast: watch the deck.",
    ("seine_bridges", "allies"): "Tenth of May. In a few weeks we land in Normandy, and when we do the Germans will rush every reserve they have across the Seine. So the bridges are coming down. Targets are the bridges at Rouen, Oissel, Vernon and Mantes, and the Sotteville rail yards. Dive bombing, low level, whatever it takes. After you drop, strafe anything moving on the roads and the railway.",
    ("seine_bridges", "axis"): "The enemy is attacking the bridges over the Seine. If they fall, our divisions in the north cannot reach the coast when the invasion comes. Protect the bridges at Rouen, Oissel, Vernon and Mantes. They come with Thunderbolts and Typhoons, low and fast. Engage them before they reach the river.",
    ("mode_dogfight", "allies"): "Fighter sweep. Enemy fighters are coming over the Channel in waves. Get up, get above them and break them up. Watch your tail, stick with your number two, and do not chase anyone down to the wave tops on your own.",
    ("mode_dogfight", "axis"): "Free hunt over the Channel. The English send their fighters across in waves. Meet them, shoot them down, and come home. Height is life: keep it, and strike from above out of the sun.",
    ("mode_bombing", "allies"): "Bombing operation. Your target is marked on the map. Fly out, find it, put your bombs on it, and come home. Expect flak around the target and fighters on the way out.",
    ("mode_bombing", "axis"): "Bombing attack. The target is marked. Fly in, release over the target and return. Enemy fighters will try to intercept you on the way home.",
    ("mode_ground", "allies"): "Ground attack. Anything moving behind enemy lines is a target: trains, convoys, tanks. Come in low, hit hard, and keep moving. The light flak along the roads is deadly.",
    ("mode_ground", "axis"): "Ground attack. Attack the enemy's columns, trains and armour behind his lines. Low and fast, one pass, then away.",
}
import voice_bombers
BRIEFS.update(voice_bombers.BRIEF_EXTRA)
import voice_battles as _vb
BRIEFS.update(_vb.BRIEF_EXTRA)
for (mid, side), text in BRIEFS.items():
    add("brief/%s_%s" % (mid, side), side, "RAF intelligence officer" if side == "allies" else "Luftwaffe briefing officer", text, "briefing, unhurried, with natural pauses")

# ------------------------------------------------------------------ training (instructor)
TRAIN = [
    ("t_basic_intro", "Right then. Basic flying. We'll start with straight and level, then climbs and turns. Follow the rings and fly smoothly, no snatching at the controls."),
    ("t_takeoff_intro", "Take-off. Line her up on the runway, open the throttle all the way, keep her straight with the rudder and let her fly herself off."),
    ("t_landing_intro", "Landing. This is where most pilots get hurt, so take your time. Gear down, flaps down, slow and steady down the approach, and put her on the numbers."),
    ("t_gunnery_intro", "Gunnery. Four target drones. Get in close behind them before you open fire. Most new pilots shoot from much too far away."),
    ("t_rockets_intro", "Rockets and bombs. Bunkers and fuel tanks on the range. Choose your weapon, line up early, and release in a shallow dive."),
    ("t_formation_intro", "Formation flying. Tuck in beside me and stay there through the turns. Small corrections, little and often."),
    ("t_stall_intro", "Stalls and recovery. We will stall her on purpose so you know what it feels like, and how to get out of it."),
    ("t_dogfight_intro", "Dogfighting. Two practice opponents. Get on their tail, stay there, and shoot them down. Mind your speed in the turns."),
    ("basic_welcome", "Welcome to flying school. Keep the nose level and fly through the first ring."),
    ("takeoff_start", "Full throttle. Keep her straight with the rudder."),
    ("landing_start", "You are on the approach. Gear down, flaps down, and line up with the runway."),
    ("gunnery_start", "Four target drones ahead. Get behind one and use your guns."),
    ("rockets_start", "Ground targets ahead. Switch between guns, rockets and bombs, then attack."),
    ("formation_start", "Stay on my wing. Keep close, but do not collide."),
    ("stall_start", "We are going to stall her on purpose. Throttle back and hold the stick back."),
    ("dogfight_start", "Two practice opponents. Get on their tail and shoot them down."),
    ("basic_climb", "Now a gentle climb. Pull back a little and open the throttle."),
    ("basic_left", "Bank left and ease back on the stick to turn."),
    ("basic_right", "Now roll right and turn the other way."),
    ("basic_descend", "Throttle back a little and let the nose drop to descend."),
    ("good", "Good."),
    ("again", "Let's try that again."),
    ("gunnery_done", "Good shooting. That is the gunnery lesson done."),
    ("all_done", "Well flown. Training complete."),
    ("targets_done", "All targets destroyed. Good work."),
    ("airborne", "Airborne. Raise the undercarriage and keep climbing."),
    ("nice_landing", "Nice landing. Use the brakes to stop."),
    ("off_runway", "That was off the runway. Take off and go round again, or restart the lesson."),
    ("rolling", "Rolling. Rotate gently when you reach flying speed."),
    ("gear_up_climb", "Gear up. Now climb away, and keep your speed up."),
    ("clean_takeoff", "Clean take-off. Well done."),
    ("gear_down_line_up", "Gear down. Line up on the centreline and aim to touch down just past the threshold."),
    ("smooth_landing", "Smooth landing. Well done."),
    ("formation_done", "Excellent formation flying."),
    ("stalled", "She has stalled. Nose down, full throttle, keep the wings level."),
    ("recovered", "Recovered. Well done."),
    ("too_low", "Too low. Starting again."),
]
for side in ("allies", "axis"):
    for key, text in TRAIN:
        add("training/%s/%s" % (side, key), side, "RAF flying instructor" if side == "allies" else "Luftwaffe flying instructor", text,
            "instructor talking over the intercom" if not key.endswith("_intro") else "lesson introduction, patient")

# ------------------------------------------------------------------ in-mission dialogue
# keys: start_1 (ops), start_2 (leader); strike: first, half, all; defend: loss_1, loss_2; win, lose
M = {
    ("bob_kent", "allies"): {
        "start_1": "Hello all aircraft, this is Ops. Large raid forming over Calais, fifty plus, heading for Dover. Vector one-two-zero, angels fifteen.",
        "start_2": "Right chaps, there they are. Bombers below, fighters above. Go for the bombers.",
        "loss_1": "Dover radar has been hit! We are losing the plot over the Channel.",
        "loss_2": "They've hit Rochester. Shorts is burning. Get after them!",
        "win": "Raid is turning back. Well done, all of you. Pancake, pancake.",
        "lose": "We've lost the targets. Return to base. There will be another raid tomorrow."},
    ("bob_kent", "axis"): {
        "start_1": "Attention, all formations. English fighters are taking off. Radar station Dover is your first target.",
        "start_2": "Stukas, prepare to dive. Fighters, stay above them. Here they come.",
        "first": "Direct hit! The first target is burning.",
        "half": "Half the targets are down. Keep attacking.",
        "all": "All targets destroyed. All formations, return to base.",
        "win": "Mission accomplished. The English are blind tonight. Well done.",
        "lose": "The attack has failed. Break off and return home."},
    ("dieppe_1942", "allies"): {
        "start_1": "Hello all aircraft. The landings have begun. Focke-Wulfs reported climbing out of Abbeville.",
        "start_2": "Stay over the ships and go for the guns on the cliffs. Watch for one-nineties.",
        "first": "Good hit on the target. Keep it up.",
        "half": "Half the targets are knocked out. The boys on the beach can see you.",
        "all": "All targets down. Cover the withdrawal and then come home.",
        "win": "The ships are getting away. Good work today.",
        "lose": "Too many targets still firing. Break off and return to base."},
    ("dieppe_1942", "axis"): {
        "start_1": "Enemy invasion fleet off Dieppe. All aircraft attack the ships.",
        "start_2": "Follow me down. Landing craft first, then the destroyers.",
        "first": "One ship hit! She is burning.",
        "half": "Half the fleet is damaged. They are turning back.",
        "all": "The invasion fleet is broken. Return to base.",
        "win": "The landing has failed. Not one of them stayed ashore. Well done.",
        "lose": "The fleet is still intact. Return to base."},
    ("dday_1944", "allies"): {
        "start_1": "All aircraft, this is Ops. H-hour is approaching. The batteries are your priority, the boats are already on their way.",
        "start_2": "Look at that. Ships as far as you can see. Right, let's give them a clear beach.",
        "first": "First battery silenced. Keep going.",
        "half": "Half the batteries are out. The landing craft are going in.",
        "all": "All targets destroyed. Stay over the fleet and keep the Luftwaffe off them.",
        "win": "The troops are ashore. A great day. Well done.",
        "lose": "The guns are still firing on the beaches. Return to base and rearm."},
    ("dday_1944", "axis"): {
        "start_1": "Alarm! The invasion has begun. All available aircraft attack the fleet off the coast.",
        "start_2": "So many ships. Stay low over the water. One pass, then away.",
        "first": "Hit! One ship is burning.",
        "half": "We are hurting them, keep going!",
        "all": "The fleet off our sector is in chaos. Return to base.",
        "win": "Well done. They will remember today.",
        "lose": "There are too many of them. Break off, return to base."},
    ("dunkirk_1940", "allies"): {
        "start_1": "Hello all aircraft. Stukas forming over Calais, heading for the beaches. Patrol line Dunkirk.",
        "start_2": "There are the ships. Keep the dive bombers off them, whatever happens.",
        "loss_1": "A ship's been hit! She is going down by the Mole.",
        "loss_2": "They're bombing the boats again! Get in among them!",
        "win": "The convoy is clear. Thousands more coming home tonight. Well done.",
        "lose": "We've lost too many ships. Return to base."},
    ("dunkirk_1940", "axis"): {
        "start_1": "The English are fleeing from Dunkirk. Attack the harbour and the ships.",
        "start_2": "Stukas, dive on the ships. Fighters, keep the Spitfires off us.",
        "first": "Direct hit on a ship!",
        "half": "Half the targets are burning.",
        "all": "The harbour is destroyed. Return to base.",
        "win": "Well done. Fewer of them will reach England.",
        "lose": "Too many have escaped. Return to base."},
    ("antwerp_raid", "allies"): {
        "start_1": "All aircraft, this is Ops. Target Antwerp docks. Jet fighters reported at Deurne.",
        "start_2": "Close up the formation. Steady on the run in.",
        "first": "Bombs on the target! Good show.",
        "half": "Half the targets are destroyed. Keep the formation tight.",
        "all": "All targets destroyed. Turn for home.",
        "win": "Docks destroyed. Well done, everyone.",
        "lose": "Targets still standing. Return to base."},
    ("antwerp_raid", "axis"): {
        "start_1": "Large bomber formation approaching Antwerp. All aircraft take off.",
        "start_2": "Dive through the escorts. Go for the bombers.",
        "loss_1": "Bombs are falling on the docks!",
        "loss_2": "The Minerva works have been hit!",
        "win": "The bombers are turning back. Well done.",
        "lose": "The docks are in flames. Return to base."},
    ("lille_raid", "allies"): {
        "start_1": "Hello all aircraft. Bombers have crossed the coast. Escorts close up.",
        "start_2": "Watch for one-nineties from Lille-Nord. Stay with the bombers.",
        "first": "Good hit on the rail yards!",
        "half": "Half the targets are down. Keep it up.",
        "all": "All targets destroyed. Home, everyone.",
        "win": "No trains through Lille for a long while. Well done.",
        "lose": "The works are still standing. Return to base."},
    ("lille_raid", "axis"): {
        "start_1": "Bomber formation approaching Lille. All aircraft scramble.",
        "start_2": "Head-on attacks. The front is their weak spot.",
        "loss_1": "Bombs are falling on the rail yards!",
        "loss_2": "The locomotive works have been hit!",
        "win": "The bombers have been driven off. Well done.",
        "lose": "The works are destroyed. Return to base."},
    ("lehavre_raid", "allies"): {
        "start_1": "All aircraft, this is Ops. Heavy flak reported over Le Havre.",
        "start_2": "One run, then out. Typhoons, take the flak positions.",
        "first": "Good hit on the target!",
        "half": "Half the targets are burning.",
        "all": "All targets destroyed. Get out of the flak.",
        "win": "The way into Le Havre is open. Good work.",
        "lose": "Targets still standing. Return to base."},
    ("lehavre_raid", "axis"): {
        "start_1": "Attack formation, the enemy has detected you. Fly low.",
        "start_2": "Balloons over the harbour. Watch for the cables.",
        "first": "Hit in the harbour!",
        "half": "Half the targets are burning.",
        "all": "All targets destroyed. Return to base.",
        "win": "Attack successful. Well done.",
        "lose": "The attack has failed. Return to base."},
    ("v1_sites", "allies"): {
        "start_1": "Hello all aircraft. Flak is heavy around the sites. Go in fast.",
        "start_2": "There's the concrete. Line up and go for it.",
        "first": "Direct hit on the bunker!",
        "half": "Half the sites are knocked out. Fewer bombs on London tonight.",
        "all": "All targets destroyed. Get out of there.",
        "win": "The sites are destroyed. London owes you one. Well done.",
        "lose": "The sites are still operational. Return to base."},
    ("v1_sites", "axis"): {
        "start_1": "Enemy fighter-bombers approaching the special sites. All aircraft take off.",
        "start_2": "Typhoons, low and fast. Watch the deck.",
        "loss_1": "Bombs on the bunkers!",
        "loss_2": "Another site has been hit!",
        "win": "The attack has been beaten off. Well done.",
        "lose": "The sites are destroyed. Return to base."},
    ("seine_bridges", "allies"): {
        "start_1": "All aircraft, this is Ops. The bridges are your targets. Strafe the roads after you drop.",
        "start_2": "Line up on the river. One bridge at a time.",
        "first": "The first bridge is down!",
        "half": "Half the bridges are down. They'll be swimming across soon.",
        "all": "All the bridges are down. Strafe anything on the roads, then home.",
        "win": "The Seine is cut. Well done, all of you.",
        "lose": "Bridges still standing. Return to base."},
    ("seine_bridges", "axis"): {
        "start_1": "Enemy fighter-bombers over the Seine. All aircraft protect the bridges.",
        "start_2": "Thunderbolts low over the river. Attack from above.",
        "loss_1": "A bridge has been hit!",
        "loss_2": "Another bridge is down!",
        "win": "The bridges are holding. Well done.",
        "lose": "The bridges are destroyed. Return to base."},
}
M.update(voice_bombers.M_EXTRA)
import voice_battles
M.update(voice_battles.M_EXTRA)
for (mid, side), lines in M.items():
    ops = "RAF operations room" if side == "allies" else "Luftwaffe ground control"
    lead = "RAF wing leader" if side == "allies" else "Luftwaffe formation leader"
    for key, text in lines.items():
        spk = lead if key in ("start_2", "first") else ops
        add("mission/%s/%s/%s" % (mid, side, key), side, spk, text, "radio, mid-battle" if key not in ("win", "lose") else "radio, end of mission")

# ------------------------------------------------------------------ generic mode calls
MODE = {
    "allies": [
        ("bomb_target_1", "ops", "Target destroyed. Good bombing."),
        ("bomb_target_2", "lead", "Bang on! That one's finished."),
        ("bomb_target_3", "ops", "Good hit. Next target."),
        ("bomb_all_1", "ops", "All targets destroyed. Return to base."),
        ("bomb_all_2", "lead", "That's the lot. Let's go home."),
        ("bomb_fighters_1", "ops", "Enemy fighters climbing to intercept."),
        ("bomb_fighters_2", "lead", "Bandits coming up from below! Close up!"),
        ("bomb_complete", "ops", "Welcome home. Mission complete."),
        ("dog_wave_1", "ops", "Another raid coming in. Fighters, here they come."),
        ("dog_wave_2", "ops", "More bandits crossing the coast."),
        ("dog_wave_3", "lead", "Here they come again! Pick your targets."),
        ("dog_clear_1", "ops", "That raid's broken up. Stand by for the next one."),
        ("dog_clear_2", "lead", "Sky's clear. Reform on me."),
        ("dog_final", "ops", "This is the last wave. Give it everything you've got."),
        ("ground_start", "ops", "Free hunting over the roads and railways. Watch the flak."),
        ("ground_kills_1", "lead", "Good strafing! Keep it up."),
        ("ground_kills_2", "lead", "There's another column. Go get them."),
        ("ground_kills_3", "ops", "The roads are full of wrecks. Good work."),
        ("defend_raid_1", "ops", "New raid approaching. Intercept."),
        ("defend_raid_2", "ops", "Bombers heading for the target. Get after them."),
        ("defend_raid_3", "lead", "There they are, low down by the coast."),
    ],
    "axis": [
        ("bomb_target_1", "ops", "Target destroyed. Good bombing."),
        ("bomb_target_2", "lead", "Direct hit! That one is finished."),
        ("bomb_target_3", "ops", "Good hit. Next target."),
        ("bomb_all_1", "ops", "All targets destroyed. Return to base."),
        ("bomb_all_2", "lead", "That is all of them. We go home."),
        ("bomb_fighters_1", "ops", "Enemy fighters climbing to intercept."),
        ("bomb_fighters_2", "lead", "Spitfires below! Close up!"),
        ("bomb_complete", "ops", "Welcome home. Mission complete."),
        ("dog_wave_1", "ops", "New enemy formation approaching. Fighters, attack."),
        ("dog_wave_2", "ops", "More English fighters crossing the Channel."),
        ("dog_wave_3", "lead", "Here they come again! Pick your targets."),
        ("dog_clear_1", "ops", "The enemy is beaten off. Wait for the next wave."),
        ("dog_clear_2", "lead", "The sky is clear. Form up on me."),
        ("dog_final", "ops", "This is the last wave. Give everything."),
        ("ground_start", "ops", "Free hunt over the roads and railways. Watch the flak."),
        ("ground_kills_1", "lead", "Good shooting! Keep going."),
        ("ground_kills_2", "lead", "Another column. Attack!"),
        ("ground_kills_3", "ops", "The roads are full of wrecks. Good work."),
        ("defend_raid_1", "ops", "New raid approaching. Intercept."),
        ("defend_raid_2", "ops", "Bombers heading for the target. Attack them."),
        ("defend_raid_3", "lead", "There they are, low over the coast."),
    ],
}
for side, items in MODE.items():
    for key, who, text in items:
        spk = ("RAF operations room" if who == "ops" else "RAF wing leader") if side == "allies" else ("Luftwaffe ground control" if who == "ops" else "Luftwaffe formation leader")
        add("mode/%s/%s" % (side, key), side, spk, text, "radio")

# ------------------------------------------------------------------ bomber crew intercom (player flying a bomber)
VOICES.update({
    "RAF bomber captain": "Male, about 30, Lancaster captain (the skipper). Received Pronunciation, calm authority, quietly encouraging his crew over the intercom.",
    "RAF bomber pilot": "Male, about 24, RAF second pilot. Midlands (Birmingham) accent, focused, terse, straining at the controls.",
    "RAF rear gunner": "Male, about 19, RAF tail gunner. London Cockney accent, sharp-eyed, nervy, quick-fire calls.",
    "RAF mid-upper gunner": "Male, about 22, RAF mid-upper gunner. Glaswegian Scottish accent, gruff, steady.",
    "RAF bomb aimer": "Male, about 26, RAF bomb aimer lying in the nose. Canadian accent, precise and calm, sing-song directions on the bomb run.",
    "Luftwaffe bomber commander": "Male, about 32, Heinkel bomber commander and observer. English with a German accent, cool and authoritative.",
    "Luftwaffe bomber pilot": "Male, about 25, Luftwaffe bomber pilot. English with a German accent, terse, concentrated.",
    "Luftwaffe dorsal gunner": "Male, about 20, Luftwaffe dorsal gunner and radio operator. English with a Saxon German accent, young, jumpy.",
    "Luftwaffe ventral gunner": "Male, about 23, Luftwaffe ventral gunner. English with a Swabian German accent, steady, a little sardonic.",
    "Luftwaffe flight engineer": "Male, about 28, Luftwaffe flight engineer who works the bomb doors. English with a Berlin German accent, practical, unflappable.",
})
CREW = {
    "allies": {
        "cap": "RAF bomber captain", "pil": "RAF bomber pilot", "rear": "RAF rear gunner", "mid": "RAF mid-upper gunner", "bomb": "RAF bomb aimer",
        "lines": [
            ("check_1", "cap", "Skipper to crew, intercom check. Rear gunner?"),
            ("check_2", "rear", "Rear gunner OK, skipper."),
            ("check_3", "mid", "Mid-upper OK."),
            ("check_4", "bomb", "Bomb aimer OK. Bombs fused and ready."),
            ("check_5", "pil", "Pilot OK. All four running sweet."),
            ("takeoff_1", "pil", "Full power. Here we go."),
            ("takeoff_2", "cap", "Wheels up. Settle down for the climb, everybody."),
            ("coast_out", "cap", "Enemy coast ahead. Gunners, keep your eyes peeled."),
            ("coast_home", "pil", "There's the English coast. Nearly home, lads."),
            ("fighter_1", "rear", "Fighter! Fighter! Port quarter, high!"),
            ("fighter_2", "rear", "Bandit, starboard quarter, low! Coming in!"),
            ("fighter_3", "mid", "Fighter dead astern, closing!"),
            ("fighter_4", "mid", "One-nine-oh, starboard beam, going down below us!"),
            ("corkscrew_1", "pil", "Corkscrew port! Go!"),
            ("corkscrew_2", "pil", "Corkscrewing starboard, hold on!"),
            ("gunner_kill_1", "rear", "Got him! He's going down in flames!"),
            ("gunner_kill_2", "mid", "I hit him! He's breaking away, smoking!"),
            ("hit_1", "cap", "We've been hit! Everybody all right? Check in."),
            ("hit_2", "pil", "Port inner's on fire! Feathering. Pressing the extinguisher."),
            ("hit_3", "rear", "Turret's hit, I'm all right. Still firing."),
            ("doors_open", "bomb", "Bomb doors open."),
            ("run_1", "bomb", "Left, left. Steady."),
            ("run_2", "bomb", "Right a bit. Steady. Steady."),
            ("run_3", "bomb", "Steady. Steady. Coming up now."),
            ("bombs_gone", "bomb", "Bombs gone!"),
            ("doors_closed", "bomb", "Bomb doors closed. Photo flash gone."),
            ("after_drop", "cap", "Good show. Let's get out of here. Course for home, pilot."),
            ("flak", "pil", "Flak ahead. Hang on, it's going to get bumpy."),
            ("landed", "cap", "Well done, everybody. Another one done. The beer is on me."),
        ],
    },
    "axis": {
        "cap": "Luftwaffe bomber commander", "pil": "Luftwaffe bomber pilot", "rear": "Luftwaffe dorsal gunner", "mid": "Luftwaffe ventral gunner", "bomb": "Luftwaffe flight engineer",
        "lines": [
            ("check_1", "cap", "Commander to crew. Intercom check. Gunner?"),
            ("check_2", "rear", "Dorsal gunner ready."),
            ("check_3", "mid", "Ventral gunner ready."),
            ("check_4", "bomb", "Bombs armed. Doors ready."),
            ("check_5", "pil", "Pilot ready. Both engines are good."),
            ("takeoff_1", "pil", "Full power. We are rolling."),
            ("takeoff_2", "cap", "Gear up. Climb to attack height."),
            ("coast_out", "cap", "English coast ahead. Gunners, watch for Spitfires."),
            ("coast_home", "pil", "French coast ahead. We are almost home."),
            ("fighter_1", "rear", "Fighter! Behind us, high left!"),
            ("fighter_2", "rear", "Spitfire, high right, attacking!"),
            ("fighter_3", "mid", "Fighter below us, climbing!"),
            ("fighter_4", "mid", "Hurricane, low behind, closing fast!"),
            ("corkscrew_1", "pil", "Evading left! Hold on!"),
            ("corkscrew_2", "pil", "Diving right, hold tight!"),
            ("gunner_kill_1", "rear", "Got him! He is burning!"),
            ("gunner_kill_2", "mid", "Hits! He is breaking away, trailing smoke!"),
            ("hit_1", "cap", "We are hit! Report damage!"),
            ("hit_2", "pil", "Left engine is burning! Shutting it down."),
            ("hit_3", "rear", "My gun is hit, I am all right. Still shooting."),
            ("doors_open", "bomb", "Bomb doors open."),
            ("run_1", "cap", "Left. A little more. Steady."),
            ("run_2", "cap", "Right a little. Steady, steady."),
            ("run_3", "cap", "Steady. Hold it. Almost there."),
            ("bombs_gone", "cap", "Bombs away!"),
            ("doors_closed", "bomb", "Bomb doors closed."),
            ("after_drop", "cap", "Good. Turn for home, quickly."),
            ("flak", "pil", "Flak ahead. Hold on."),
            ("landed", "cap", "Well done, everyone. We are home."),
        ],
    },
}
for side, c in CREW.items():
    for key, who, text in c["lines"]:
        add("crew/%s/%s" % (side, key), side, c[who], text, "bomber intercom, engine noise behind" if key not in ("bombs_gone",) else "bomber intercom, relieved")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["file", "side", "speaker", "voice", "line", "speak", "direction"])
    for r in rows:
        w.writerow([r[0], r[1], r[2], VOICES[r[2]], r[3], r[3], r[4]])
print(len(rows), "lines,", sum(len(r[3]) for r in rows), "characters ->", OUT)
