# Voice brief: WW2 Channel Air War radio calls

This folder holds the recorded radio voices for the game. Please generate one audio file per line listed below.

## The game
An arcade WW2 flight game set over Kent, the English Channel and northern France, 1940-1944 (Battle of Britain to D-Day).
The player flies either for the RAF (side `allies`) or the Luftwaffe (side `axis`). These lines are heard over the
aircraft radio: sector controllers, tower operators, wingmen and the player's own orders, plus background chatter.

## Style
- Period-authentic 1940s military radio telephony: short, clipped, practical. Not theatrical, no modern slang.
- RAF voices are British (and some Commonwealth / Polish pilots). Luftwaffe voices speak **English with a German
  accent** (keep the German words that appear in the lines, e.g. "Horrido", "Abschuss", "Alarmstart").
- Combat calls are urgent and a little breathless; controllers stay calm. Follow the `direction` column.
- Read the line **exactly as written**. No extra words, no callsigns added, no numbers added.
- Keep each line natural and brisk: most calls are 1-3 seconds, chatter up to about 6 seconds.

## Audio format
- One file per line, named exactly as the `file` column, e.g. `allies/bandits_02` becomes `allies/bandits_02.ogg`.
- Format: **OGG Vorbis** (preferred) or WAV, **mono, 44.1 kHz**, normalised to about -16 LUFS, peaks below -1 dBFS.
- **Clean and dry**: no music, no reverb, no radio effect. The game adds the radio filter and squelch itself.
- Trim silence: no more than 0.1 s before the first word and 0.2 s after the last.
- Put the files in the `allies/` and `axis/` sub-folders of this folder. Missing files are fine: the game falls
  back to on-screen text for any line without a recording.

## Cast (one consistent voice per speaker)
| Speaker | Voice |
|---|---|
| RAF sector controller | Male, mid 40s, RAF squadron leader. Received Pronunciation, calm, measured and unhurried even when urgent. |
| RAF airfield tower | Female, early 20s, WAAF radio operator. Crisp Home Counties accent, bright and precise. |
| RAF wingman | Male, about 21, young RAF pilot officer. Northern English (Yorkshire) accent, energetic, breathless in combat. |
| Player (RAF leader) | Male, late 20s, RAF flight lieutenant. Light Received Pronunciation, confident, clipped and decisive. |
| Luftwaffe controller | Male, mid 40s, Luftwaffe Major. German accent in English, precise, cool and formal. |
| Luftwaffe airfield tower | Female, early 20s, Luftwaffe signals auxiliary (Nachrichtenhelferin). Light German accent, clear and polite. |
| Luftwaffe wingman | Male, about 21, young German fighter pilot, Bavarian accent in English, eager and excitable. |
| Player (Luftwaffe leader) | Male, late 20s, Staffelkapitaen. German accent in English, confident, crisp, few words. |
| RAF squadron leader | Male, mid 30s, Scottish (Glasgow) accent, gruff and commanding. |
| Coastguard, Dover | Male, late 50s, Kentish coastguard, weathered, slow, a little gravelly. |
| Observer Corps | Male, about 50, civilian Royal Observer Corps volunteer, West Country (Devon) accent, careful. |
| RAF pilot | Male, mid 20s, Polish pilot of No. 303 Squadron, strong Polish accent in English, steady. |
| RAF section leader | Male, mid 20s, New Zealander, relaxed but sharp. |
| Air-Sea Rescue | Male, early 40s, RAF rescue launch skipper, London Cockney accent, matter-of-fact, engine noise behind. |
| Luftwaffe pilot | Male, mid 20s, Austrian (Viennese) accent in English, cheerful. |
| Luftwaffe sea rescue | Male, mid 40s, northern German (Hamburg) naval officer, dry and calm. |
| Luftwaffe radar operator | Male, late 20s, technical NCO, German accent, flat and monotone. |
| Luftwaffe flak officer | Male, mid 50s, gruff Luftwaffe flak officer, heavy German accent, shouting over gunfire. |

## Lines
The same list as machine-readable CSV: `voice_lines.csv` (columns: file, side, speaker, voice, line, direction).

### RAF side (folder `allies/`)

**RAF sector controller** - Male, mid 40s, RAF squadron leader. Received Pronunciation, calm, measured and unhurried even when urgent.

| File | Line | Direction |
|---|---|---|
| `allies/intro_takeoff` | This is Control. You are cleared for take-off. Good luck. | calm, clipped |
| `allies/intro_scramble` | Scramble, scramble! Enemy aircraft inbound! | urgent |
| `allies/lost_contact` | Lost contact with your wingman. Stay sharp. | sombre |
| `allies/chatter_01` | All aircraft, bandits angels one-five over Dover. Vector one-two-zero. | background radio chatter |
| `allies/chatter_02` | Hello Blue Leader, twenty-plus bandits approaching Dungeness, angels twelve. | background radio chatter |
| `allies/chatter_03` | Tiger squadron, pancake, pancake. Refuel and stand by. | background radio chatter |
| `allies/chatter_07` | Cloud base two thousand feet over the Isle of Wight, visibility good. | background radio chatter |
| `allies/chatter_09` | Hello all aircraft, enemy fighters sweeping over Folkestone. Keep a good lookout. | background radio chatter |

**RAF airfield tower** - Female, early 20s, WAAF radio operator. Crisp Home Counties accent, bright and precise.

| File | Line | Direction |
|---|---|---|
| `allies/tower_land` | Runway clear. You're cleared to land, use the brakes. | calm |
| `allies/tower_land_wind` | Strong winds on the field, watch your crosswind. Cleared to land. | calm |

**RAF wingman** - Male, about 21, young RAF pilot officer. Northern English (Yorkshire) accent, energetic, breathless in combat.

| File | Line | Direction |
|---|---|---|
| `allies/bandits_01` | Bandits, one o'clock! | alert |
| `allies/bandits_02` | Bandits, two o'clock! | alert |
| `allies/bandits_03` | Bandits, three o'clock! | alert |
| `allies/bandits_04` | Bandits, four o'clock! | alert |
| `allies/bandits_05` | Bandits, five o'clock! | alert |
| `allies/bandits_06` | Bandits, six o'clock! | alert |
| `allies/bandits_07` | Bandits, seven o'clock! | alert |
| `allies/bandits_08` | Bandits, eight o'clock! | alert |
| `allies/bandits_09` | Bandits, nine o'clock! | alert |
| `allies/bandits_10` | Bandits, ten o'clock! | alert |
| `allies/bandits_11` | Bandits, eleven o'clock! | alert |
| `allies/bandits_12` | Bandits, twelve o'clock! | alert |
| `allies/bombers_01` | Bombers, one o'clock! | alert |
| `allies/bombers_02` | Bombers, two o'clock! | alert |
| `allies/bombers_03` | Bombers, three o'clock! | alert |
| `allies/bombers_04` | Bombers, four o'clock! | alert |
| `allies/bombers_05` | Bombers, five o'clock! | alert |
| `allies/bombers_06` | Bombers, six o'clock! | alert |
| `allies/bombers_07` | Bombers, seven o'clock! | alert |
| `allies/bombers_08` | Bombers, eight o'clock! | alert |
| `allies/bombers_09` | Bombers, nine o'clock! | alert |
| `allies/bombers_10` | Bombers, ten o'clock! | alert |
| `allies/bombers_11` | Bombers, eleven o'clock! | alert |
| `allies/bombers_12` | Bombers, twelve o'clock! | alert |
| `allies/kill_player_1` | Splash one! | excited |
| `allies/kill_player_2` | Good shooting, leader! | excited |
| `allies/kill_player_3` | He's going down! | excited |
| `allies/kill_player_4` | Nice one! | excited |
| `allies/kill_friend_1` | Splash one! | excited |
| `allies/kill_friend_2` | Got him! | excited |
| `allies/kill_friend_3` | Bandit down! | excited |
| `allies/kill_friend_4` | Kill confirmed! | excited |
| `allies/hit_1` | I'm hit! I'm hit! | panicked, engine noise ok |
| `allies/hit_2` | Taking fire, I need help! | panicked, engine noise ok |
| `allies/hit_3` | My engine is failing! | panicked, engine noise ok |
| `allies/hit_4` | I've lost power! | panicked, engine noise ok |
| `allies/smoke_warn` | Leader, you're trailing smoke! Get out of there! | urgent |
| `allies/leader_down` | Leader is down! Leader's gone! | shocked |
| `allies/reply_form_1` | Roger, forming up. |  |
| `allies/reply_form_2` | Copy, on your wing. |  |
| `allies/reply_form_3` | Moving into position. |  |
| `allies/reply_attack_1` | Tally-ho! Engaging. | keen |
| `allies/reply_attack_2` | Roger, going in. | keen |
| `allies/reply_attack_3` | Visual, attacking! | keen |
| `allies/reply_notarget_1` | Negative, no target in sight. |  |
| `allies/reply_notarget_2` | We don't have eyes on anything, leader. |  |
| `allies/reply_cover_1` | Covering you, leader. |  |
| `allies/reply_cover_2` | Got your six. |  |
| `allies/reply_cover_3` | Roger, we have you covered. |  |
| `allies/reply_rtb_1` | Copy, heading home. |  |
| `allies/reply_rtb_2` | Roger, returning to base. |  |
| `allies/reply_rtb_3` | Going home, good hunting. |  |

**Player (RAF leader)** - Male, late 20s, RAF flight lieutenant. Light Received Pronunciation, confident, clipped and decisive.

| File | Line | Direction |
|---|---|---|
| `allies/order_alone` | Anyone on this frequency? Nobody's flying with me. | dry |
| `allies/order_form_vic` | Form on me, vic formation. | commanding |
| `allies/order_form_echelon` | Form on me, echelon right. | commanding |
| `allies/order_form_line` | Form on me, line abreast. | commanding |
| `allies/order_form_trail` | Form on me, line astern. | commanding |
| `allies/order_attack` | Attack my target! | commanding |
| `allies/order_cover` | Cover me, I'm going in. | commanding |
| `allies/order_rtb` | Break off and return to base. | commanding |

**RAF squadron leader** - Male, mid 30s, Scottish (Glasgow) accent, gruff and commanding.

| File | Line | Direction |
|---|---|---|
| `allies/chatter_04` | Tally-ho! Tally-ho! Bandits nine o'clock low. | background radio chatter |

**Coastguard, Dover** - Male, late 50s, Kentish coastguard, weathered, slow, a little gravelly.

| File | Line | Direction |
|---|---|---|
| `allies/chatter_05` | Convoy entering the Downs, balloons flying. Fighter cover requested. | background radio chatter |

**Observer Corps** - Male, about 50, civilian Royal Observer Corps volunteer, West Country (Devon) accent, careful.

| File | Line | Direction |
|---|---|---|
| `allies/chatter_06` | Raid four-two crossing the coast at Beachy Head, heading north. | background radio chatter |

**RAF pilot** - Male, mid 20s, Polish pilot of No. 303 Squadron, strong Polish accent in English, steady.

| File | Line | Direction |
|---|---|---|
| `allies/chatter_08` | Green Leader, I've got a glycol leak, returning to base. | background radio chatter |

**RAF section leader** - Male, mid 20s, New Zealander, relaxed but sharp.

| File | Line | Direction |
|---|---|---|
| `allies/chatter_10` | Yellow section, buster! Bombers heading for Manston. | background radio chatter |

**Air-Sea Rescue** - Male, early 40s, RAF rescue launch skipper, London Cockney accent, matter-of-fact, engine noise behind.

| File | Line | Direction |
|---|---|---|
| `allies/chatter_11` | Launch away from Ramsgate, searching for a pilot down off the North Foreland. | background radio chatter |

### Luftwaffe side (folder `axis/`)

**Luftwaffe controller** - Male, mid 40s, Luftwaffe Major. German accent in English, precise, cool and formal.

| File | Line | Direction |
|---|---|---|
| `axis/intro_takeoff` | Kanal Control here. You are cleared for take-off. Good hunting. | calm, clipped |
| `axis/intro_scramble` | Alarmstart! Alarmstart! Enemy aircraft approaching the coast! | urgent |
| `axis/lost_contact` | We have lost contact with your wingman. Stay alert. | sombre |
| `axis/chatter_01` | All Jagdgruppen, enemy convoy in the Strait of Dover. Escort the Stukas. | background radio chatter |
| `axis/chatter_02` | Achtung, Spitfires reported over Cap Gris-Nez, high. | background radio chatter |
| `axis/chatter_06` | Haze over the Channel, cloud base low at Calais. | background radio chatter |
| `axis/chatter_08` | Bombers turning for home over Dungeness, cover them across the coast. | background radio chatter |

**Luftwaffe airfield tower** - Female, early 20s, Luftwaffe signals auxiliary (Nachrichtenhelferin). Light German accent, clear and polite.

| File | Line | Direction |
|---|---|---|
| `axis/tower_land` | Runway is clear. You are cleared to land. | calm |
| `axis/tower_land_wind` | Strong crosswind on the field. Careful on approach, cleared to land. | calm |

**Luftwaffe wingman** - Male, about 21, young German fighter pilot, Bavarian accent in English, eager and excitable.

| File | Line | Direction |
|---|---|---|
| `axis/bandits_01` | Indians, one o'clock! | alert |
| `axis/bandits_02` | Indians, two o'clock! | alert |
| `axis/bandits_03` | Indians, three o'clock! | alert |
| `axis/bandits_04` | Indians, four o'clock! | alert |
| `axis/bandits_05` | Indians, five o'clock! | alert |
| `axis/bandits_06` | Indians, six o'clock! | alert |
| `axis/bandits_07` | Indians, seven o'clock! | alert |
| `axis/bandits_08` | Indians, eight o'clock! | alert |
| `axis/bandits_09` | Indians, nine o'clock! | alert |
| `axis/bandits_10` | Indians, ten o'clock! | alert |
| `axis/bandits_11` | Indians, eleven o'clock! | alert |
| `axis/bandits_12` | Indians, twelve o'clock! | alert |
| `axis/bombers_01` | Viermots, one o'clock! | alert |
| `axis/bombers_02` | Viermots, two o'clock! | alert |
| `axis/bombers_03` | Viermots, three o'clock! | alert |
| `axis/bombers_04` | Viermots, four o'clock! | alert |
| `axis/bombers_05` | Viermots, five o'clock! | alert |
| `axis/bombers_06` | Viermots, six o'clock! | alert |
| `axis/bombers_07` | Viermots, seven o'clock! | alert |
| `axis/bombers_08` | Viermots, eight o'clock! | alert |
| `axis/bombers_09` | Viermots, nine o'clock! | alert |
| `axis/bombers_10` | Viermots, ten o'clock! | alert |
| `axis/bombers_11` | Viermots, eleven o'clock! | alert |
| `axis/bombers_12` | Viermots, twelve o'clock! | alert |
| `axis/kill_player_1` | Abschuss! Good shooting! | excited |
| `axis/kill_player_2` | Horrido! He's going down! | excited |
| `axis/kill_player_3` | He's burning, well done! | excited |
| `axis/kill_player_4` | Well done, leader! | excited |
| `axis/kill_friend_1` | Abschuss! | excited |
| `axis/kill_friend_2` | Got him! | excited |
| `axis/kill_friend_3` | One Tommy down! | excited |
| `axis/kill_friend_4` | Kill confirmed! | excited |
| `axis/hit_1` | I'm hit! I'm hit! | panicked, engine noise ok |
| `axis/hit_2` | Taking fire, I need help! | panicked, engine noise ok |
| `axis/hit_3` | My engine is failing! | panicked, engine noise ok |
| `axis/hit_4` | I've lost power! | panicked, engine noise ok |
| `axis/smoke_warn` | Leader, you're trailing smoke! Get out of there! | urgent |
| `axis/leader_down` | Leader is down! Leader's gone! | shocked |
| `axis/reply_form_1` | Roger, forming up. |  |
| `axis/reply_form_2` | Copy, on your wing. |  |
| `axis/reply_form_3` | Moving into position. |  |
| `axis/reply_attack_1` | Pauke, pauke! Engaging. | keen |
| `axis/reply_attack_2` | Understood, going in. | keen |
| `axis/reply_attack_3` | Target in sight, attacking! | keen |
| `axis/reply_notarget_1` | Negative, no target in sight. |  |
| `axis/reply_notarget_2` | We don't have eyes on anything, leader. |  |
| `axis/reply_cover_1` | Covering you, leader. |  |
| `axis/reply_cover_2` | Got your six. |  |
| `axis/reply_cover_3` | Roger, we have you covered. |  |
| `axis/reply_rtb_1` | Copy, heading home. |  |
| `axis/reply_rtb_2` | Roger, returning to base. |  |
| `axis/reply_rtb_3` | Going home, good hunting. |  |

**Player (Luftwaffe leader)** - Male, late 20s, Staffelkapitaen. German accent in English, confident, crisp, few words.

| File | Line | Direction |
|---|---|---|
| `axis/order_alone` | Anyone on this frequency? Nobody's flying with me. | dry |
| `axis/order_form_vic` | Form on me, vic formation. | commanding |
| `axis/order_form_echelon` | Form on me, echelon right. | commanding |
| `axis/order_form_line` | Form on me, line abreast. | commanding |
| `axis/order_form_trail` | Form on me, line astern. | commanding |
| `axis/order_attack` | Attack my target! | commanding |
| `axis/order_cover` | Cover me, I'm going in. | commanding |
| `axis/order_rtb` | Break off and return to base. | commanding |

**Luftwaffe pilot** - Male, mid 20s, Austrian (Viennese) accent in English, cheerful.

| File | Line | Direction |
|---|---|---|
| `axis/chatter_03` | Horrido! One Spitfire down near Folkestone. | background radio chatter |
| `axis/chatter_07` | Fuel is getting low, I am turning for home. | background radio chatter |

**Luftwaffe sea rescue** - Male, mid 40s, northern German (Hamburg) naval officer, dry and calm.

| File | Line | Direction |
|---|---|---|
| `axis/chatter_04` | Rescue boat leaving Boulogne for a pilot in the water. | background radio chatter |

**Luftwaffe radar operator** - Male, late 20s, technical NCO, German accent, flat and monotone.

| File | Line | Direction |
|---|---|---|
| `axis/chatter_05` | Large formation forming over Kent. Course south-east. | background radio chatter |

**Luftwaffe flak officer** - Male, mid 50s, gruff Luftwaffe flak officer, heavy German accent, shouting over gunfire.

| File | Line | Direction |
|---|---|---|
| `axis/chatter_09` | Calais flak engaging enemy aircraft over the harbour. | background radio chatter |
