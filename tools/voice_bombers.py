"""Briefings + radio dialogue for the bomber missions (bmb_* and blitz_*). Merged into make_voice_story.py."""

def L(start_1, start_2, first, half, all_, win, lose):
    return {"start_1": start_1, "start_2": start_2, "first": first, "half": half, "all": all_, "win": win, "lose": lose}

M_EXTRA = {
 # ---------------------------------------------------------------- Allies
 ("bmb_lille_locos", "allies"): L(
  "Hello all aircraft, this is Ops. Marauders, you are clear to climb. Target Fives-Lille. Flak and fighters expected at the coast.",
  "Formation, close it up. Tight and steady, we hold our height all the way to the target.",
  "Bombs on the works! The first target is burning.", "Half the target is gone. Stay on the run.", "All targets destroyed! Turn for home, tight formation.",
  "Locomotive works destroyed. Well done, crews. Bring them home.", "The target still stands. We'll have to go again."),
 ("bmb_rouen_oil", "allies"): L(
  "Hello all aircraft. Weather is clear over Normandy. Refinery at Petit-Couronne is your first aiming point.",
  "Make it count, boys. After this run the Germans will not have the fuel to drive their tanks to the beach.",
  "Refinery hit! Black smoke is climbing out of Petit-Couronne.", "One target down, one to go. Keep your heading.", "Both targets destroyed. Excellent. Heading home.",
  "The refinery is gone. A great day's work.", "The target is intact. Return to base."),
 ("bmb_krupp_night", "allies"): L(
  "All aircraft, this is Ops. Ruhr defences are fully alert. Searchlights and night fighters reported over the target.",
  "Crew, this is the skipper. Stay sharp, keep the intercom clear. Gunners, watch the dark for fighters. Bomb aimer, you have the run.",
  "Bombs gone and bursting! There are fires in the Krupp works.", "The first aiming point is hit. On to the next.", "Both targets burning. Well done everyone. Get us out of here.",
  "Back over the Channel. Good show, crew. Krupp will not forget tonight.", "We did not hit the target. Home, and we will try again tomorrow."),
 ("bmb_cologne_night", "allies"): L(
  "Hello all aircraft. Three aiming points tonight: Ford, Bayer and the Gremberg yards. The Rhine will show you the way.",
  "Skipper to crew. Look for the river, then the cathedral. Set the sight and keep it steady.",
  "First target burning! Look at those fires!", "Two aiming points still to go, hold your course.", "All three targets destroyed! Cologne is lit up like a bonfire. Home now.",
  "A fine night's work. Cologne has paid for it. Home safe, everyone.", "The aiming points are intact. Return to base."),
 ("bmb_channel_ports_1940", "allies"): L(
  "Hello all aircraft. Barges are massing in the harbour at Boulogne. Keep low, stay in formation.",
  "Blenheims, in we go. Bombs on the barges, then straight out. No hanging about.",
  "Direct hit on the harbour! Barges are burning!", "One harbour hit. On to the next.", "Both harbours hit! That should put the invasion back a week.",
  "Barges burning in both ports. The invasion has taken a heavy blow tonight.", "The barges still float. Return home and try again."),
 ("bmb_minerva_mosquito", "allies"): L(
  "Hello Mosquito. Antwerp is clear of cloud. One aiming point: the Minerva works. High, fast, one pass.",
  "Navigator, call the run. Altitude and speed on the sight, then we are in and out before they wake up.",
  "Bang on! The works are hit!", "Half the job is done.", "Target destroyed. Throttle up and run for home.",
  "Perfect. In and out, no losses. The Mosquito strikes again.", "Missed. Not tonight, then. Come home."),
 # ---------------------------------------------------------------- Axis, bmb_
 ("bmb_london_docks_night", "axis"): L(
  "Attention all formations. Bombers over the Channel. Target: the London docks. The fires from the first wave will guide you.",
  "Crew, this is the pilot. The Thames is ahead. We bomb on the fires. Observer, set your sight.",
  "Hit! The docks are burning!", "One target destroyed. On to the next.", "All targets destroyed! The whole sky is red. Turn for home.",
  "London is burning tonight. Mission accomplished. Return to base.", "The raid has failed. Return home."),
 ("bmb_coventry_night", "axis"): L(
  "All formations, this is Ground Control. Course for Coventry. Pathfinders have marked the target with fires and beams.",
  "Pilot to crew. It is a long way to Coventry. Keep your eyes open for night fighters, they will come out of the dark.",
  "The ordnance works are burning!", "One target down. Keep your course.", "Both targets are destroyed! Coventry is on fire. Return home.",
  "Coventry has been hit hard. Well done, everyone.", "Target missed. Return to base."),
 ("bmb_woolston_day", "axis"): L(
  "Hello all aircraft. Ju 88 formation, steady over the coast. Target: the Supermarine works at Woolston. Spitfires are expected.",
  "Stay in formation. The fighters will protect us, the guns will protect us. Hold the run.",
  "The works are hit! Smoke rising over Southampton!", "One target is destroyed.", "Both targets destroyed. All aircraft, turn for the coast.",
  "The Spitfire factory is burning. A good day's work.", "The raid has failed. Return to base."),
 ("bmb_rochester_day", "axis"): L(
  "Attention all formations. The Thames estuary is clear. Target Rochester. Dorniers, keep low and tight.",
  "Dornier crews, stay together. The escorts are above us. Follow the river.",
  "Short Brothers is burning!", "Half the targets are down.", "All targets destroyed! Back across the estuary now.",
  "The works are in ruins. Congratulations, all crews.", "The target stands. Return to base."),
 # ---------------------------------------------------------------- Axis, Blitz
 ("blitz_black_saturday", "axis"): L(
  "All aircraft, this is Ground Control. Massive formation crossing the coast. Fighter cover above you. Target: the London docks.",
  "Look at them all! Hundreds of aircraft. Hold your heading and bomb as one.",
  "Hit! Smoke is pouring from the docks!", "One target down. The sky is full of smoke.", "All targets are burning. The whole East End is alight. Turn for home.",
  "London is on fire from end to end. Return to base, good work.", "The raid has failed. The fighters are on us. Break off."),
 ("blitz_london_dawn_fog", "axis"): L(
  "Ground Control to all aircraft. Dawn over the Thames, fog on the ground. You will have to trust your instruments.",
  "Pilot to crew. Fog on the river. We cannot see the ground. Set the sight by the dials and the map.",
  "A hit at Clapham! Smoke is climbing through the fog.", "One target hit. Stay on the heading.", "Both targets down. The river is in flames. Turn for home.",
  "In and out under the fog. A clean job.", "We never found the target in that fog. Return to base."),
 ("blitz_birmingham_night", "axis"): L(
  "Ground Control. Cloud over the Midlands, ten tenths. The beams are weak. Navigate by the instruments.",
  "Pilot to crew. Deep in the English night under cloud. Navigator, give me the heading, and keep it exact.",
  "Hit! Fires are showing through the cloud!", "One target burning. On to the next.", "All targets are hit. Birmingham is aflame. Home, quickly.",
  "The Midlands are burning. A long flight but a good result.", "We bombed blind and missed. Return to base."),
 ("blitz_portsmouth_dusk", "axis"): L(
  "Hello all aircraft. Dusk over the Solent. The first wave has lit fires at the dockyard. Follow the fires.",
  "Pilot to crew. Portsmouth below, fires already burning. Observer, the sight is yours.",
  "The dockyard is hit! Fires are spreading!", "One harbour hit. Now Southampton.", "Both ports are burning. Return to Cherbourg.",
  "The ports are in flames. Well done, crews.", "Missed the aiming points. Return to base."),
 ("blitz_plymouth_storm", "axis"): L(
  "Ground Control. Rain and low cloud over Devon. Fighters will not find you in this, but you may not find Plymouth either.",
  "Pilot to crew. Dark, wet and cold. We have the dockyard on the chart. Hold the course and listen to the engines.",
  "Fire in the dockyard! The rain cannot put that out!", "Half the target is burning.", "Devonport is destroyed. Home through the storm.",
  "Plymouth has taken a beating tonight. Good flying through that weather.", "We could not find the dockyard in the rain. Return to base."),
 ("blitz_filton_day", "axis"): L(
  "All formations, Ground Control. Midday. Bristol and the Filton works ahead. Spitfires will come out to meet you.",
  "Pilot to crew. Gunners, alert. They will come in from the sun. Hold the run on Filton.",
  "Direct hit on the works! Smoke is pouring out!", "One target hit, the second remains.", "Both targets destroyed. All aircraft turn for the coast.",
  "The Bristol works are in ruins. Excellent work.", "The raid has failed. Return to base, if you can."),
 ("blitz_weybridge_evening", "axis"): L(
  "Hello all aircraft. Weybridge and Kingston. Two aiming points, minutes apart. Evening sun behind you.",
  "Pilot to crew. Low sun in the west, so they will see us coming. Set your sights and drop.",
  "First target hit! Bomber production is dead at Weybridge.", "One factory is burning, one to go.", "Both works destroyed. Fly low and fast for the coast.",
  "Hurricane and Wellington production are out. A fine evening's work.", "The factories are still standing. Return to base."),
 ("blitz_swansea_night", "axis"): L(
  "Ground Control. Long flight across the Bristol Channel to Swansea. Moon is down. You are alone in the dark.",
  "Pilot to crew. A very long night. Fuel is tight, so every turn counts. Keep the heading and watch the dials.",
  "The docks are hit! Fires on the waterfront!", "Half the docks are burning.", "Swansea is on fire. Turn for home, watch the fuel.",
  "Swansea has burned for three nights. Excellent, crews.", "We have not hit the docks. Return, if the fuel holds."),
 ("blitz_derby_predawn", "axis"): L(
  "Hello all aircraft. Clear sky over the Midlands, first light on the horizon. Derby and the Rolls-Royce works.",
  "Pilot to crew. Dawn is coming. We want to be over the target before sunrise. Steady course.",
  "Hit on the works! Smoke over Derby!", "Half the works are hit.", "Rolls-Royce is burning. Turn for home before the sun rises.",
  "The engine works are down. The Spitfire will be waiting for engines.", "The works still stand. Return to base."),
 ("blitz_southampton_night", "axis"): L(
  "Ground Control. Winter night over Southampton Water. The flak is heavy. Keep your height.",
  "Pilot to crew. Fires on the water. Flak to starboard. Do not weave on the run.",
  "The Woolston works are burning!", "One of the targets is hit.", "Southampton is alight. Turn for the Channel.",
  "A heavy raid on Southampton. Well done to all.", "The target is intact. Break off and return."),
}

BRIEF_EXTRA = {
 ("bmb_lille_locos", "allies"): "Ninth of October. Your target is the Fives-Lille locomotive works, one of the largest in France. Marauders and Spitfire escorts will leave Manston, cross the coast at Gravelines and climb for the target. Set your sight carefully, you need the right speed and the right altitude. One steady run and the works are finished.",
 ("bmb_rouen_oil", "allies"): "Before the landings, the German fuel supply must be broken. The refinery at Petit-Couronne and the marshalling yard at Sotteville are your targets. The weather is clear, the flak will be heavy. Hold your altitude, and bring them home.",
 ("bmb_krupp_night", "allies"): "Tonight is the Battle of the Ruhr. Essen is our target: the Krupp works. You will fly in darkness over the Dutch coast, then the Ruhr with its searchlights and flak. The night fighters hunt by their radar and you have no fighter escort. Get your speed and altitude on the sight right, hold a steady run over the aiming point, then turn for home.",
 ("bmb_cologne_night", "allies"): "A night raid on Cologne. Three aiming points: the Ford works, the Bayer plant at Leverkusen and the marshalling yard at Gremberg. The Rhine is your guide. Plan your legs on the chart, bomb each in turn and get out before the fighters find you.",
 ("bmb_channel_ports_1940", "allies"): "September, nineteen forty. The Germans are gathering barges in the Channel ports for the invasion of England. Blenheims will go in at dawn, bomb Boulogne and Calais harbours, and get out before the Luftwaffe wakes up. Every barge you sink is one fewer to cross the sea.",
 ("bmb_minerva_mosquito", "allies"): "A precision raid by Mosquito. Antwerp, the Minerva works, one pass. High, fast and alone: your best defence is speed. Set the sight to match your instruments, line up the target and let go.",
 ("bmb_london_docks_night", "axis"): "The Luftwaffe turns to London. Tonight the Royal Docks and the oil depot at Thameshaven are the targets. You will fly across the Channel in the dark and follow the Thames. The darkness helps you against the fighters, but the searchlights and flak will find you.",
 ("bmb_coventry_night", "axis"): "Operation Moonlight Sonata. Coventry, the engine and ordnance works, and the aircraft factory at Castle Bromwich. A long flight over southern England in the dark. Plan your route on the chart and trust your dials.",
 ("bmb_woolston_day", "axis"): "A daylight raid on the Supermarine factory at Woolston, where the Spitfire is built. The escort will meet you over the coast. Fly a steady run over Southampton Water, bomb, and turn for home.",
 ("bmb_rochester_day", "axis"): "Dornier raid on the Short Brothers works at Rochester and the oil depot at Thameshaven. Keep a tight line along the Thames estuary. The Spitfires will be waiting for you over Kent.",
 ("blitz_black_saturday", "axis"): "Seventh of September. The first great raid on London. Hundreds of bombers with fighter escort will cross the Channel in the late afternoon. Your aiming points are the Royal Docks and the oil depots at Thameshaven. The RAF will come at you with everything. Bomb, then get out before dark.",
 ("blitz_london_dawn_fog", "axis"): "A dawn raid on London under fog. The rail yards at Clapham Junction and the river crossings are your aim. The fog will hide you from the fighters but also hide the ground. Trust your instruments and the map.",
 ("blitz_birmingham_night", "axis"): "Birmingham. The Austin works at Longbridge, the rail yards of New Street and the factory at Castle Bromwich. A long night flight under cloud, deep into the Midlands. The beams are weak under the cloud. Set the sight by your instruments and bomb the aiming points in turn.",
 ("blitz_portsmouth_dusk", "axis"): "Portsmouth, January. Two raids tonight: the first wave lights the dockyard, the second finishes it. You fly with the dusk behind you: dockyard first, then Southampton docks. Expect balloons and heavy flak.",
 ("blitz_plymouth_storm", "axis"): "Plymouth, April. A moonless, rainy night. The rain and cloud hide you from the night fighters, but they hide the dockyard from you too. Fly by the instruments and the chart, find Devonport and drop.",
 ("blitz_filton_day", "axis"): "Bristol Aeroplane Company at Filton, midday. A long run over the Channel and Somerset, and the Spitfires will know you are coming. Stay in formation, bomb the works and the docks and turn for home.",
 ("blitz_weybridge_evening", "axis"): "Weybridge and Kingston: the factories that build the Wellington and the Hurricane. A late afternoon raid with the low sun behind the defenders. Two aiming points, a few minutes apart.",
 ("blitz_swansea_night", "axis"): "Swansea, three nights of fire. The longest flight of the Blitz: across the Bristol Channel to the docks of South Wales. Deep in the night, alone, with little fuel to spare. Every turn counts.",
 ("blitz_derby_predawn", "axis"): "Derby and the Rolls-Royce works that make the Merlin engine. A clear, predawn sky: dark enough to hide you, light enough to find the works. Bomb before the sun rises.",
 ("blitz_southampton_night", "axis"): "A winter night over Southampton Water. Fires fill the sky and the flak is heavy. Your targets are the Supermarine works and the docks. Hold your altitude and bomb as one.",
}
