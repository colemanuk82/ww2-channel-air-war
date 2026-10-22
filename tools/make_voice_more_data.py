"""Line texts for tools/make_voice_more.py (kept apart so scripts/radio.gd's TAKES can be checked against them)."""

# (key, first take number, allies takes, axis takes, direction)
WING_TAKES = [
    ("kill_player", 9, ["Smashing shooting, leader!", "He's bailing out!"], ["Wonderful, leader! He is finished!", "He is bailing out!"], "excited"),
    ("kill_friend", 9, ["He's had it! Going down in flames!", "Got the blighter!"], ["He is going down in flames!", "I got the dog!"], "excited"),
    ("hit", 8, ["Hit in the wing, I'm all right!", "Petrol's pouring out, I'm hit!", "Christ, they've shot my tail up!"],
                ["Hit in the wing, I am all right!", "My fuel is leaking, I am hit!", "They have shot up my tail!"], "panicked, engine noise ok"),
    ("reply_form", 6, ["Closing up now.", "Right with you, leader."], ["Closing up now.", "With you, leader."], ""),
    ("reply_attack", 6, ["I've got him, going in!", "Following you in!"], ["I have him, attacking!", "Following you in!"], "keen"),
    ("reply_cover", 5, ["I've got you, leader. Go!", "Watching your tail."], ["I have you, leader. Go!", "Watching your tail."], ""),
    ("reply_rtb", 5, ["Roger, turning for home.", "Heading back, leader."], ["Understood, turning for home.", "Heading back, leader."], ""),
]

# (kind, [allies take 4, take 5], [axis take 4, take 5])
BRIEF_MORE = [
    ("strike", ["Bombing job. Get in, put them on the target, and get out.", "Group want that target flattened. Off you go."],
               ["A bombing job. Get in, hit the target, get out.", "Command wants that target destroyed. Go."]),
    ("airfield", ["Catch them on the ground. Strafe the dispersals.", "Their airfield's busy. Go and make a mess of it."],
                 ["Catch them on the ground. Attack the dispersals.", "Their airfield is busy. Go and wreck it."]),
    ("convoy", ["Lorries on the move. Shoot them up.", "Transport column on the road. Stop it."],
               ["Lorries on the move. Attack them.", "A supply column on the road. Stop it."]),
    ("train", ["A goods train is running. Knock out the engine.", "There's a train on the line. Stop it dead."],
              ["A goods train is running. Destroy the engine.", "A train is on the line. Stop it."]),
    ("shipping", ["Ships off the coast. Go and sink them.", "Coasters with escorts. Low and fast."],
                 ["Ships off the coast. Go and sink them.", "Small ships with escorts. Low and fast."]),
    ("eboats", ["E-boats on the prowl. Find them and sink them.", "Fast boats heading for our convoy. Stop them."],
               ["Enemy gunboats out. Find them and sink them.", "Fast boats heading for our ships. Stop them."]),
    ("intercept", ["Raid coming in. Get up there and break it up.", "Bombers on the plot. Vector to intercept."],
                  ["Enemy raid coming in. Break it up.", "Bombers reported. Intercept them."]),
    ("cover", ["Our ships are being bombed. Get over them now.", "Dive bombers on the convoy. Buster!"],
              ["Our ships are being bombed. Get over them now.", "Bombers over our convoy. Full throttle!"]),
    ("sweep", ["Fighter sweep. Clear the sky over their side.", "Go and hunt their fighters."],
              ["Fighter sweep. Clear the sky.", "Go and hunt their fighters."]),
    ("rescue", ["A pilot's in the water. Find him and circle.", "Dinghy reported. Go and find him."],
               ["A pilot is in the water. Find him and circle.", "A dinghy is reported. Go and find him."]),
    ("recce", ["Photo run for you. Keep it steady.", "We need pictures. One clean pass, then home."],
              ["Photo flight for you. Keep it steady.", "We need pictures. One clean pass, then home."]),
    ("escort", ["Escort job. Look after the bombers.", "Bombers need cover. Meet them at the rendezvous."],
               ["Escort mission. Protect the bombers.", "Our bombers need cover. Meet them at the rendezvous."]),
    ("intruder", ["Intruder job. Catch them landing.", "Get over their airfield in the dark."],
                 ["Intruder mission. Catch them landing.", "Get over their airfield in the dark."]),
]

# (key, first take number, allies, axis)
TOWER_MORE = [
    ("tower_land", 5, ["Cleared to land. The kettle's on."], ["Cleared to land. Welcome home."]),
    ("intro_takeoff", 5, ["Cleared for take-off. Good luck up there."], ["Take-off approved. Good luck."]),
]

CHAT_MORE = {
    "allies": [
        ("RAF sector controller", "Hello Tiger Leader, bandits angels two-zero over Canterbury. Buster."),
        ("RAF squadron leader", "Red section, break left! Break left!"),
        ("RAF section leader", "Yellow Two, keep your eyes on the sun."),
        ("RAF pilot", "Blue Three, I have a Messerschmitt on my tail!"),
        ("Observer Corps", "Thirty-plus over Hastings, height twelve thousand, heading north."),
        ("Coastguard, Dover", "Shelling from the French coast again. Dover harbour hit."),
        ("RAF sector controller", "All aircraft, pancake, pancake. Raid has turned back."),
        ("RAF squadron leader", "Tally-ho! Bombers dead ahead. Line astern, go!"),
    ],
    "axis": [
        ("Luftwaffe controller", "All Schwärme, Spitfires above you over Dover. Watch the sun."),
        ("Luftwaffe pilot", "Achtung, Spitfire behind me! Get him off!"),
        ("Luftwaffe radar operator", "Twelve enemy fighters climbing over Hawkinge."),
        ("Luftwaffe flak officer", "Dunkirk flak engaging. Low flyers over the harbour!"),
        ("Luftwaffe controller", "Return to base. Fuel reserves must not be risked."),
        ("Luftwaffe pilot", "I have hit a Hurricane. He is smoking badly."),
        ("Luftwaffe radar operator", "Formation over the Thames estuary. Course east."),
        ("Luftwaffe controller", "Stukas are going in. Hold the fighters off them."),
    ],
}

CHAT_MORE["allies"] += [
    ("RAF sector controller", "Hello Red Leader, your bandits are now over Ashford. Vector one-one-zero."),
    ("RAF section leader", "Green section, reforming over Biggin. Anybody seen Green Three?"),
    ("RAF pilot", "I am out of ammunition. Returning to base."),
    ("Observer Corps", "One aircraft down in flames near Tenterden. Parachute seen."),
    ("RAF sector controller", "Hello all aircraft, Diver warning. Flying bombs over Hythe."),
    ("RAF squadron leader", "Keep it tight, chaps. Here they come."),
]
CHAT_MORE["axis"] += [
    ("Luftwaffe controller", "All aircraft, the bombers are over the target. Hold your positions."),
    ("Luftwaffe pilot", "Rot Drei here. One Hurricane down, I am coming home."),
    ("Luftwaffe radar operator", "Enemy fighters landing at Manston. They will be up again soon."),
    ("Luftwaffe controller", "Sea rescue reports a pilot picked up off Calais."),
    ("Luftwaffe flak officer", "Cease fire! Our own aircraft overhead!"),
    ("Luftwaffe pilot", "I am out of ammunition. Returning home."),
]

# Ops Room: a sixth headline for the commonest jobs, and more success / hit calls
BRIEF_SIX = [
    ("intercept", "Raid approaching. Get after them, and don't let them through.", "Raid approaching. Get after them, do not let them through."),
    ("strike", "Target for tonight's photographs. Make it a good one.", "A target for you. Make it a good hit."),
    ("sweep", "Their fighters are about. Go and find them.", "Their fighters are about. Go and find them."),
    ("convoy", "Vehicles moving to the coast. Catch them in the open.", "Vehicles moving to the front. Catch them in the open."),
    ("escort", "The bombers are counting on you. Don't leave them.", "The bombers are counting on you. Do not leave them."),
    ("airfield", "Fighters refuelling on that field. Hit them now.", "Fighters refuelling on that field. Hit them now."),
]
OPS_MORE = [
    ("success_9", "Excellent show. That'll please the Air Commodore.", "Excellent. Command will be pleased."),
    ("success_10", "Job done. Good flying.", "Job done. Good flying."),
    ("hit_6", "Bang on target! Well done.", "Right on target! Well done."),
    ("open_8", "Hello, Ops calling. New job for you.", "Jafü calling. New job for you."),
]
