extends Node
## Radio (autoload "Radio"): tactical radio between the player and friendly aircraft.
##   Player orders (keys 1-4): 1 form on me (cycles Vic / Echelon / Line abreast / Trail), 2 attack my target,
##   3 cover me, 4 return to base. Friendly pilots answer by callsign.
##   Automatic calls: bandits spotted (with clock position and height), kills, hits, losses, tower / control
##   calls with the wind. Messages go to the HUD log (signal `message`) with a squelch click and, when
##   GameState.radio_voice is on and the OS supports it, text-to-speech.
## Public: Radio.say(sender, text, kind), Radio.order(kind), Radio.player_callsign, Radio.callsign_of(ac).

signal message(sender: String, text: String, kind: int)   # kind: 0 friendly, 1 control/tower, 2 player

enum Kind { FRIENDLY, CONTROL, PLAYER }
enum Formation { VIC, ECHELON, LINE_ABREAST, TRAIL }

const FORMATION_NAMES := ["Vic", "Echelon right", "Line abreast", "Trail"]
const ALLY_CALLS := ["Angel", "Cobra", "Sabre", "Tiger"]
const AXIS_CALLS := ["Adler", "Falke", "Habicht", "Wolf"]

var formation: int = Formation.VIC
var squadron: String = ""
var player_callsign: String = "Red 1"
var voice_ok: bool = false
var voice_id: String = ""
var _voice_male: String = ""
var _voice_female: String = ""

var _spotted: Dictionary = {}       # instance_id -> last call time
var _scan_t: float = 1.0
var _last_bandit_call: float = -99.0
var _tower_called: Dictionary = {}
var _last_msg_t: float = -99.0
var _queue: Array = []
var _channel_free_t: float = 0.0     # earliest time the next call may start
var _last_prio: bool = false
var _tx_open: bool = false           # a recorded transmission is playing (close-squelch when it ends)
var _static_player: AudioStreamPlayer
var _crackle_player: AudioStreamPlayer
var _static_level: float = 0.5       # 0..1 drifting background static strength
var _static_target: float = 0.5
var _crackle_t: float = 3.0
var _form_used: bool = false
var _cool_until: Dictionary = {}     # call key -> time before which the same call is not made again
var _last_pick: Dictionary = {}      # line group -> last index used, so the same line is not repeated back to back
var _hq_intro_done: bool = false
var _chatter_t: float = 0.0        # seconds until the next bit of ambient radio chatter (set on first scan)
var _left_field: bool = false
var _ui_player: AudioStreamPlayer
var _streams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	get_tree().node_added.connect(_on_node_added)
	# no spoken calls during scripted / screenshot runs (they would play through the user's speakers)
	var automated: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot=") or arg.begins_with("--frames=") or arg.begins_with("--quit-after") or arg == "--autopilot":
			automated = true
	if not automated and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
		if voices.is_empty():
			voices = DisplayServer.tts_get_voices_for_language("")
		if not voices.is_empty():
			voice_id = voices[0]
			voice_ok = true
			_voice_male = voices[0]
			_voice_female = voices[0]
			for v in voices:
				var low: String = String(v).to_lower()
				if "zira" in low or "hazel" in low or "susan" in low or "female" in low:
					_voice_female = v
			# male voice for every call, British first (George), then any other male voice
			var best: int = 99
			for v2 in voices:
				var low2: String = String(v2).to_lower()
				var rank: int = 99
				for k in ["george", "ryan", "thomas", "david", "mark", "guy", "male"].size():
					if ["george", "ryan", "thomas", "david", "mark", "guy", "male"][k] in low2 and not "female" in low2:
						rank = k
						break
				if rank < best:
					best = rank
					_voice_male = v2
	print("[radio] voice: %s" % (voice_id if voice_ok else "none (no TTS voice available; calls are text + squelch only)"))


# ------------------------------------------------------------------ helpers
func _player() -> Aircraft:
	for n in get_tree().get_nodes_in_group("aircraft"):
		var a: Aircraft = n as Aircraft
		if a != null and a.player_controlled:
			return a
	return null


func _wingmen() -> Array:
	var out: Array = []
	var pl: Aircraft = _player()
	if pl == null:
		return out
	for n in get_tree().get_nodes_in_group("aircraft"):
		var a: Aircraft = n as Aircraft
		if a == null or a == pl or a.team != pl.team or a.state != Aircraft.State.ALIVE:
			continue
		var p: AIPilot = AIFactory.pilot_of(a)
		if p != null and p.role == AIPilot.Role.WINGMAN and p.leader == pl:
			out.append(a)
	return out


func _squadron_name(team: String) -> String:
	if squadron == "":
		var pool: Array = ALLY_CALLS if team == "Allies" else AXIS_CALLS
		squadron = pool[randi() % pool.size()]
	return squadron


## Callsign: "<Squadron> <n>": the player is 1, wingmen 2, 3, 4 by order of appearance.
func callsign_of(a: Aircraft) -> String:
	if a == null:
		return "Control"
	if a.player_controlled:
		return "%s 1" % _squadron_name(a.team)
	var idx: int = 2
	if a.has_meta("radio_idx"):
		idx = int(a.get_meta("radio_idx"))
	else:
		var used: Array = []
		for w in _wingmen():
			if w != a and (w as Aircraft).has_meta("radio_idx"):
				used.append(int((w as Aircraft).get_meta("radio_idx")))
		while idx in used:
			idx += 1
		a.set_meta("radio_idx", idx)
	return "%s %d" % [_squadron_name(a.team), idx]


# ------------------------------------------------------------------ recorded takes
## Lines with several recorded takes (assets/voice/<side>/<key>_<n>.mp3; tools/make_voice_lines.py and
## tools/make_voice_variants.py). Index n-1 is the text of take n. A take is only used when its file exists, so
## a missing recording never falls back to text-to-speech.
const TAKES := {
	"intro_takeoff": {"Allies": ["You are cleared for take-off. Good luck.", "Runway's clear, you're cleared for take-off. Good hunting.", "You're clear to go. Keep your eyes peeled once you're up.", "Cleared for take-off. The Channel's busy today, so watch yourself.", "Cleared for take-off. Good luck up there."],
		"Axis": ["You are cleared for take-off. Good hunting.", "The runway is clear, take-off approved. Good hunting.", "Cleared for take-off. Keep your eyes open over the coast.", "Take-off approved. Many Tommies about today, so watch yourself.", "Take-off approved. Good luck."]},
	"intro_scramble": {"Allies": ["Scramble, scramble! Enemy aircraft inbound.", "Scramble! Bandits approaching the coast, get airborne!", "Scramble, scramble! Raid coming in, all aircraft get airborne now!"],
		"Axis": ["Alarmstart! Enemy aircraft approaching the coast!", "Alarmstart! Enemy bombers approaching, get airborne!", "Alarm! Alarm! Raid coming in, all aircraft take off now!"]},
	"tower_land": {"Allies": ["Cleared to land, use the brakes.", "You're clear to land. Mind the craters by the perimeter.", "Cleared to land. Welcome home.", "Runway's yours. Cleared to land, and mind the bowser on the left.", "Cleared to land. The kettle's on."],
		"Axis": ["Runway is clear. You are cleared to land.", "Cleared to land. Welcome back.", "The runway is free. Landing approved.", "Landing approved. Watch the bomb craters at the edge of the field.", "Cleared to land. Welcome home."]},
	"tower_land_wind": {"Allies": ["Strong winds, watch your crosswind. Cleared to land.", "It's gusty down here, watch the crosswind. Cleared to land.", "Wind's picked up across the runway. Take care. Cleared to land."],
		"Axis": ["Strong crosswind on the field. Careful on approach, cleared to land.", "Strong gusts on the field. Careful. Landing approved.", "The crosswind is strong today. Landing approved."]},
	"lost_contact": {"Allies": ["lost contact with {who}. Stay sharp.", "we've lost {who}'s signal. Keep a good lookout.", "no contact with {who}. Stay sharp."],
		"Axis": ["lost contact with {who}. Stay alert.", "{who} is not answering. Stay alert.", "we have lost {who}. Watch yourself."]},
	"smoke_warn": {"Allies": ["{sq} leader, you're trailing smoke! Get out of there!", "Leader, you're on fire! Get out of there!", "You're streaming glycol, leader! Head for home!"],
		"Axis": ["{sq} leader, you are trailing smoke! Get out of there!", "Leader, you are burning! Get out!", "You are trailing smoke, leader! Turn for home!"]},
	"leader_down": {"Allies": ["{sq} is down! Leader's gone!", "Leader's bought it! He's gone in!"],
		"Axis": ["{sq} is down! Leader's gone!", "Leader is hit! He is going down!"]},
	"kill_player": {"Allies": ["Splash one!", "Good shooting, leader!", "He's going down!", "Nice one!", "Wizard shooting, leader!", "That's one for the book!", "Smack on, he's had it!", "Flamer! Good show!", "Smashing shooting, leader!", "He's bailing out!", "Cracking shot, leader!", "That's him finished!", "Down he goes! Well done!", "What a shot, leader!", "He's going in, no chute!"],
		"Axis": ["Abschuss! Good shooting!", "Horrido! He's going down!", "He's burning, well done!", "Well done, leader!", "Horrido! Wonderful shooting!", "He is finished, leader!", "Good hit! He is burning!", "Another one for you, leader!", "Wonderful, leader! He is finished!", "He is bailing out!", "Excellent shot, leader!", "That is him finished!", "Down he goes! Well done!", "What a shot, leader!", "He is going in, no parachute!"]},
	"kill_friend": {"Allies": ["Splash one!", "Got him!", "Bandit down!", "Kill confirmed!", "I got him! He's going in!", "Flamer! One destroyed!", "That bandit's had it!", "Scratch one!", "He's had it! Going down in flames!", "Got the blighter!", "Got one! He's gone in!", "Bandit destroyed!", "That's one less Jerry!", "Flamer! He's going down!", "Got him, he's breaking up!"],
		"Axis": ["Abschuss!", "Got him!", "One Tommy down!", "Kill confirmed!", "Horrido! He is down!", "I got him!", "One Spitfire less!", "Abschuss! He is burning!", "He is going down in flames!", "I got the dog!", "Got one! He has crashed!", "Enemy destroyed!", "One Tommy less!", "He is burning! Going down!", "Got him, he is breaking up!"]},
	"hit": {"Allies": ["I'm hit! I'm hit!", "Taking fire, need help!", "Engine's failing!", "I've lost power!", "I've been hit, losing oil pressure!", "Something's hit me, I can't see for smoke!", "They've got me! I'm hit!", "Hit in the wing, I'm all right!", "Petrol's pouring out, I'm hit!", "Christ, they've shot my tail up!", "I'm hit, I'm hit! Going down!", "Bullets in the cockpit, I'm hurt!", "Engine's on fire!", "I'm hit, losing height!", "Can't hold her, I'm hit!"],
		"Axis": ["I'm hit! I'm hit!", "Taking fire, need help!", "Engine's failing!", "I've lost power!", "I am hit, losing oil!", "Smoke in the cockpit, I cannot see!", "They got me! I am hit!", "Hit in the wing, I am all right!", "My fuel is leaking, I am hit!", "They have shot up my tail!", "I am hit! Going down!", "Bullets in the cockpit, I am hurt!", "My engine is on fire!", "I am hit, losing height!", "I cannot hold her, I am hit!"]},
	"reply_form": {"Allies": ["Roger, forming up.", "Copy, on your wing.", "Moving into position.", "Roger, closing up.", "On my way, leader.", "Closing up now.", "Right with you, leader.", "Coming up on your wing.", "Formating now, leader.", "Tucking in.", "On your wing, leader.", "Closing up, roger."],
		"Axis": ["Roger, forming up.", "Copy, on your wing.", "Moving into position.", "Understood, closing up.", "Coming, leader.", "Closing up now.", "With you, leader.", "Coming up on your wing.", "Taking position now.", "Closing in.", "On your wing, leader.", "Closing up, understood."]},
	"reply_attack": {"Allies": ["Tally! Engaging.", "Roger, going in.", "Visual, attacking!", "Going in now!", "Tally-ho! He's mine!", "I've got him, going in!", "Following you in!", "Engaging now!", "He won't get away!", "Going in, cover me!", "Tally-ho! Going down!", "Attacking, leader!"],
		"Axis": ["Pauke, pauke! Engaging.", "Understood, going in.", "Target in sight, attacking!", "Attacking now!", "Horrido! He is mine!", "I have him, attacking!", "Following you in!", "Attacking now!", "He will not get away!", "Going in, cover me!", "Horrido! Going down!", "Attacking, leader!"]},
	"reply_notarget": {"Allies": ["Negative, no target in sight.", "We don't have eyes on anything, leader.", "Can't see a thing, leader.", "Nothing out there, leader.", "Sky's empty this side.", "No joy, leader.", "Can't see anything, leader.", "Nothing in sight from here."],
		"Axis": ["Negative, no target in sight.", "We don't have eyes on anything, leader.", "Nothing in sight, leader.", "Nothing out there, leader.", "The sky is empty this side.", "Nothing seen, leader.", "I see nothing, leader.", "Nothing in sight from here."]},
	"reply_cover": {"Allies": ["Covering you, leader.", "Got your six.", "Roger, we have you covered.", "Right behind you, leader.", "I've got you, leader. Go!", "Watching your tail.", "Your tail's clear, leader.", "I'm on it. Go get him.", "Sticking to you like glue.", "Covering, leader. Go on.", "I'll keep them off you."],
		"Axis": ["Covering you, leader.", "Got your six.", "Roger, we have you covered.", "Right behind you, leader.", "I have you, leader. Go!", "Watching your tail.", "Your tail is clear, leader.", "I have you. Go get him.", "I am staying right behind you.", "Covering, leader. Go.", "I will keep them off you."]},
	"reply_rtb": {"Allies": ["Copy, heading home.", "Roger, returning to base.", "RTB, good hunting.", "Wilco. Heading for home.", "Roger, turning for home.", "Heading back, leader.", "Going home. See you in the mess.", "Breaking off, heading for base.", "Roger, home we go.", "Roger. RTB.", "Heading for the barn."],
		"Axis": ["Copy, heading home.", "Roger, returning to base.", "RTB, good hunting.", "Jawohl. Heading home.", "Understood, turning for home.", "Heading back, leader.", "Going home. See you on the ground.", "Breaking off, heading for base.", "Understood, home we go.", "Understood. Going home.", "Heading for home."]},
}
## Keys whose first take has no _1 suffix on disk (recorded before takes existed).
const UNNUMBERED := ["intro_takeoff", "intro_scramble", "tower_land", "tower_land_wind", "lost_contact", "smoke_warn", "leader_down"]

var _clip_exists: Dictionary = {}


func _side_dir() -> String:
	var pl: Aircraft = _player()
	return "axis" if pl != null and pl.team == "Axis" else "allies"


## True if a recording exists for this clip id on the player's side (cached).
func has_clip(clip: String) -> bool:
	var rel: String = clip if "/" in clip else "%s/%s" % [_side_dir(), clip]
	if _clip_exists.has(rel):
		return bool(_clip_exists[rel])
	var ok: bool = false
	for ext in ["ogg", "wav", "mp3"]:
		if ResourceLoader.exists("%s%s.%s" % [VOICE_DIR, rel, ext]):
			ok = true
			break
	_clip_exists[rel] = ok
	return ok


func _take_clip(key: String, i: int) -> String:
	if i == 0 and key in UNNUMBERED:
		return key
	return "%s_%d" % [key, i + 1]


## Picks a recorded take of `key` (never the same one twice running). Returns [text, clip].
func take(key: String, team: String, fmt: Dictionary = {}) -> Array:
	var lines: Array = TAKES[key]["Axis" if team == "Axis" else "Allies"]
	var avail: Array = []
	for i in lines.size():
		if has_clip(_take_clip(key, i)):
			avail.append(i)
	if avail.is_empty():
		avail = [0]
	var last: int = int(_last_pick.get("take_" + key, -1))
	if avail.size() > 1:
		avail.erase(last)
	var i: int = int(avail[randi() % avail.size()])
	_last_pick["take_" + key] = i
	return [String(lines[i]).format(fmt), _take_clip(key, i)]


## A spotting call clip: bandits_03, bandits_03_b or bandits_03_c, whichever takes are recorded.
func _spot_clip(kind: String, clock: int) -> String:
	var base: String = "%s_%02d" % [kind, clock]
	var opts: Array = [base]
	for sfx in ["_b", "_c", "_d", "_e", "_f"]:
		if has_clip(base + sfx):
			opts.append(base + sfx)
	var last: String = str(_last_pick.get("spot_" + base, ""))
	if opts.size() > 1:
		opts.erase(last)
	var c: String = opts[randi() % opts.size()]
	_last_pick["spot_" + base] = c
	return c


# ------------------------------------------------------------------ say
## clip: id of a recorded line in assets/voice/<allies|axis>/ (see assets/voice/voice_lines.csv). When the file
## exists it is played; otherwise the call is text (plus text-to-speech only if the Radio voice option is on).
## prio: instructor / bomber-crew intercom lines that must follow events closely: they skip the random pause
## between transmissions (they still never talk over another call).
func say(sender: String, text: String, kind: int = Kind.FRIENDLY, delay: float = 0.0, clip: String = "", prio: bool = false) -> void:
	var now: float = Time.get_ticks_msec() * 0.001
	var item: Dictionary = {"t": now + delay, "sender": sender, "text": text, "kind": kind, "clip": clip, "prio": prio}
	# keep the queue ordered by due time (stable for equal times)
	var i: int = _queue.size()
	while i > 0 and float(_queue[i - 1]["t"]) > float(item["t"]):
		i -= 1
	_queue.insert(i, item)


## Release queued messages one at a time with a gap so the channel stays readable.
func _pump_queue() -> void:
	if _queue.is_empty():
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var item: Dictionary = _queue[0]
	# wait for the previous transmission (recording or narration) to finish, then a random pause
	var prio: bool = bool(item.get("prio", false))
	if now < float(item["t"]) or (now < _channel_free_t and not prio) or _transmitting():
		return
	_queue.pop_front()
	_last_msg_t = now
	_last_prio = prio
	_channel_free_t = now + (0.4 if prio else _random_gap() + 0.6)     # text-only calls: reading time + a pause
	var sender: String = item["sender"]
	var text: String = item["text"]
	var kind: int = item["kind"]
	print("[radio] %s: %s" % [sender, text])
	message.emit(sender, text, kind)
	_play_squelch()
	if _play_clip(String(item.get("clip", ""))):
		_tx_open = true
		return
	if voice_ok and bool(GameState.get("radio_voice")) and not AudioManager.muted:
		DisplayServer.tts_stop()
		var vol: int = int(clampf(AudioManager.radio_volume * AudioManager.master_volume, 0.0, 1.0) * 100.0)
		var urgent: bool = text.contains("!")
		# all voices male; control rooms calm and lower, pilots a little faster with a per-callsign pitch
		var voice: String = _voice_male
		var pitch: float = 1.0
		var rate: float = 1.12 if urgent else 1.0
		if kind == Kind.CONTROL:
			rate = 0.95 if not urgent else 1.08
			pitch = 0.9
		elif kind == Kind.FRIENDLY:
			var num: int = int(sender.get_slice(" ", sender.get_slice_count(" ") - 1)) if sender.get_slice(" ", sender.get_slice_count(" ") - 1).is_valid_int() else 2
			pitch = clampf(0.92 + float(num) * 0.04, 0.9, 1.08)
		else:
			pitch = 0.97
		var spoken: String = _spoken(text)
		if spoken.strip_edges() == "":
			return
		DisplayServer.tts_speak(_speakable(spoken), voice, vol, pitch, rate)


## What actually gets spoken: the on-screen call minus the phrases full of numbers (wind, headings, distances,
## counts, heights), which made the voice sound like a robot reading a list. Clock positions stay
## ("bandits, two o'clock"), they sound natural.
func _spoken(text: String) -> String:
	var parts: PackedStringArray = []
	var re := RegEx.new()
	re.compile("[^.,!?]+[.,!?]*")
	for m in re.search_all(text):
		var seg: String = m.get_string()
		var has_num: bool = false
		for ch in seg:
			if ch >= "0" and ch <= "9":
				has_num = true
				break
		if has_num and not "o'clock" in seg:
			continue
		parts.append(seg.strip_edges())
	return " ".join(parts)


const _ONES := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const _TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]


func _num_words(n: int) -> String:
	if n < 20:
		return _ONES[n]
	if n < 100:
		return _TENS[n / 10] + ("" if n % 10 == 0 else " " + _ONES[n % 10])
	var out: String = ""
	for ch in str(n):
		out += (" " if out != "" else "") + _ONES[int(ch)]
	return out


## Make the call read like radio speech: numbers as words (headings and wind digit by digit, the way pilots say
## them), "o'clock" kept, and no hard sentence stops that make the voice sound choppy.
func _speakable(t: String) -> String:
	var re := RegEx.new()
	re.compile("\\d+(\\.\\d+)?")
	var out: String = ""
	var last: int = 0
	for m in re.search_all(t):
		out += t.substr(last, m.get_start() - last)
		var tok: String = m.get_string()
		if "." in tok:
			var parts: PackedStringArray = tok.split(".")
			out += _num_words(int(parts[0])) + " point " + _num_words(int(parts[1]))
		elif tok.length() >= 3 and tok.begins_with("0") or tok.length() == 3:
			var digits: String = ""
			for ch in tok:
				digits += (" " if digits != "" else "") + _ONES[int(ch)]
			out += digits                                   # 057 -> "zero five seven", 266 -> "two six six"
		else:
			out += _num_words(int(tok))
		last = m.get_end()
	out += t.substr(last)
	return out.replace("...", ",").replace("! ", ", ").replace(". ", ", ")


const VOICE_DIR := "res://assets/voice/"
var _voice_player: AudioStreamPlayer
var _narr_player: AudioStreamPlayer


func _find_audio(rel: String) -> AudioStream:
	for ext in ["ogg", "wav", "mp3"]:
		var path: String = "%s%s.%s" % [VOICE_DIR, rel, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


## Spoken briefing / narration (clean, not through the radio filter). Radio calls wait until it has finished.
## Returns false when there is no recording for `rel` (path under assets/voice/, no extension).
func narrate(rel: String) -> bool:
	var st: AudioStream = _find_audio(rel)
	if st == null or AudioManager.muted:
		return false
	if _narr_player == null:
		_narr_player = AudioStreamPlayer.new()
		_narr_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_narr_player.bus = &"Narration" if AudioServer.get_bus_index("Narration") >= 0 else &"Master"
		add_child(_narr_player)
	_narr_player.stream = st
	_narr_player.volume_db = linear_to_db(clampf(AudioManager.radio_volume * AudioManager.master_volume, 0.01, 1.0))
	_narr_player.play()
	return true


func stop_narration() -> void:
	if _narr_player != null:
		_narr_player.stop()


func narrating() -> bool:
	return _narr_player != null and _narr_player.playing


## Scripted lines (briefings, training, mission dialogue, bomber crew) from assets/voice/voice_story.csv:
## file id -> [speaker, line]. story(id) says the line with its recording (if generated) and the speaker as sender.
var _story: Dictionary = {}


func _load_story() -> void:
	if not _story.is_empty():
		return
	for csv_name in ["voice_story.csv", "voice_generic.csv", "voice_places.csv"]:
		var f := FileAccess.open(VOICE_DIR + csv_name, FileAccess.READ)
		if f == null:
			continue
		var head: PackedStringArray = f.get_csv_line()
		var fi: int = head.find("file")
		var si: int = head.find("speaker")
		var li: int = head.find("line")
		while not f.eof_reached():
			var row: PackedStringArray = f.get_csv_line()
			if row.size() > maxi(fi, maxi(si, li)):
				_story[row[fi]] = [row[si], row[li]]


func has_story(id: String) -> bool:
	_load_story()
	return _story.has(id)


func story(id: String, delay: float = 0.0, prio: bool = false) -> void:
	_load_story()
	if not _story.has(id):
		return
	var spk: String = String(_story[id][0])
	var sender: String = spk.trim_prefix("RAF ").trim_prefix("Luftwaffe ").capitalize()
	var low: String = spk.to_lower()
	var kind: int = Kind.CONTROL if ("operations" in low or "control" in low or "officer" in low or "instructor" in low) else Kind.FRIENDLY
	say(sender, String(_story[id][1]), kind, delay, id, prio)


## Clear pending calls (new session / quit to menu).
func reset_channel() -> void:
	_queue.clear()
	stop_narration()
	_pending_clip = ""
	if _voice_player != null:
		_voice_player.stop()


## "Radio" audio bus: the recordings are delivered clean, this makes them sound like a 1940s R/T set
## (narrow band-pass, a little drive and compression).
func _radio_bus() -> String:
	var idx: int = AudioServer.get_bus_index("Radio")
	if idx >= 0:
		return "Radio"
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "Radio")
	AudioServer.set_bus_send(idx, "Master")
	var bp := AudioEffectBandPassFilter.new()
	bp.cutoff_hz = 1900.0
	bp.resonance = 0.45
	AudioServer.add_bus_effect(idx, bp)
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 300.0
	AudioServer.add_bus_effect(idx, hp)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	dist.drive = 0.18
	dist.post_gain = -1.0
	AudioServer.add_bus_effect(idx, dist)
	# level the recorded calls to a consistent loudness: compress the peaks, then lift everything with
	# makeup gain so a quiet take is still clearly audible against the engine and the static
	var comp := AudioEffectCompressor.new()
	comp.threshold = -24.0
	comp.ratio = 4.0
	comp.gain = 10.0
	AudioServer.add_bus_effect(idx, comp)
	return "Radio"


## Plays a recorded line for the player's side if it exists. Returns true when something was played.
func _play_clip(clip: String) -> bool:
	if clip == "" or AudioManager.muted:
		return false
	var pl: Aircraft = _player()
	var side: String = "axis" if pl != null and pl.team == "Axis" else "allies"
	# "folder/name" clips (training, missions) are side-specific already; plain ids live in allies/ or axis/
	var rel: String = clip if "/" in clip else "%s/%s" % [side, clip]
	for ext in ["ogg", "wav", "mp3"]:
		var path: String = "%s%s.%s" % [VOICE_DIR, rel, ext]
		if ResourceLoader.exists(path):
			if ResourceLoader.has_cached(path):
				var st: AudioStream = load(path) as AudioStream
				if st == null:
					return false
				_start_voice(st)
				return true
			# not loaded yet: decode it on a worker thread (a first-time clip load stalled the frame by
			# tens of ms) and start it from _process when ready - the channel counts as busy meanwhile
			if ResourceLoader.load_threaded_request(path, "AudioStream") != OK:
				return false
			_pending_clip = path
			_pending_t = 0.0
			return true
	return false


var _pending_clip: String = ""
var _pending_t: float = 0.0


func _start_voice(st: AudioStream) -> void:
	if _voice_player == null:
		_voice_player = AudioStreamPlayer.new()
		_voice_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_voice_player.bus = _radio_bus()
		add_child(_voice_player)
	DisplayServer.tts_stop()
	_voice_player.stream = st
	_voice_player.volume_db = linear_to_db(clampf(AudioManager.radio_volume * AudioManager.master_volume, 0.01, 1.0))
	_voice_player.play()


func _poll_pending_clip(delta: float) -> void:
	if _pending_clip == "":
		return
	_pending_t += delta
	var stt: int = ResourceLoader.load_threaded_get_status(_pending_clip)
	if stt == ResourceLoader.THREAD_LOAD_LOADED:
		var st: AudioStream = ResourceLoader.load_threaded_get(_pending_clip) as AudioStream
		_pending_clip = ""
		if st != null:
			_start_voice(st)
	elif stt != ResourceLoader.THREAD_LOAD_IN_PROGRESS or _pending_t > 5.0:
		_pending_clip = ""


## Pause between transmissions: usually 1-3 s, sometimes a long lull of up to ~6 s.
func _random_gap() -> float:
	return randf_range(1.0, 3.0) if randf() < 0.65 else randf_range(3.0, 6.5)


## True while a recorded call or briefing narration is still playing.
## True while a recorded radio call or briefing is audible (the in-flight music ducks under it).
func voice_active() -> bool:
	return _transmitting()


func _transmitting() -> bool:
	return _pending_clip != "" or (_voice_player != null and _voice_player.playing) or (_narr_player != null and _narr_player.playing)


## Background radio: a low hiss whose strength drifts (reception comes and goes), random crackle bursts of
## different strengths between calls, the static dips while someone is talking, and a squelch tail when a
## recorded transmission ends.
func _update_static(delta: float) -> void:
	var pl: Aircraft = _player()
	var on: bool = pl != null and pl.state == Aircraft.State.ALIVE and not AudioManager.muted and bool(GameState.get("radio_static"))
	if _static_player == null:
		_static_player = AudioStreamPlayer.new()
		_static_player.bus = _radio_bus()
		_static_player.stream = _make_hiss()
		_static_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_static_player)
		_crackle_player = AudioStreamPlayer.new()
		_crackle_player.bus = _radio_bus()
		_crackle_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_crackle_player)
		for i in 4:
			_streams["crackle%d" % i] = _make_crackle(0.12 + 0.18 * float(i), 0.35 + 0.2 * float(i))
		_streams["squelch_close"] = _make_squelch_close()
	if not on or GameState.paused:
		if _static_player.playing:
			_static_player.stop()
		return
	if not _static_player.playing:
		_static_player.play()
	if randf() < delta / 4.0:
		_static_target = randf_range(0.15, 1.0)
	_static_level = move_toward(_static_level, _static_target, delta * 0.35)
	var talking: bool = _transmitting()
	var vol: float = clampf(AudioManager.radio_volume * AudioManager.master_volume, 0.0001, 1.0)
	_static_player.volume_db = linear_to_db(vol) - 42.0 + 9.0 * _static_level - (6.0 if talking else 0.0)
	if _tx_open and not talking:
		_tx_open = false
		_crackle_player.stream = _streams["squelch_close"]
		_crackle_player.volume_db = linear_to_db(vol) - 16.0
		_crackle_player.play()
		_channel_free_t = maxf(_channel_free_t, Time.get_ticks_msec() * 0.001 + (0.35 if _last_prio else _random_gap()))
	_crackle_t -= delta
	if _crackle_t <= 0.0 and not talking:
		_crackle_t = randf_range(2.0, 9.0)
		var k: int = randi() % 4
		_crackle_player.stream = _streams["crackle%d" % k]
		_crackle_player.volume_db = linear_to_db(vol) - 30.0 + 6.0 * float(k) + randf_range(-3.0, 3.0)
		_crackle_player.play()


## Looping band-limited hiss (the Radio bus filters it further).
func _make_hiss() -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = rate * 3
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var f: float = 0.0
	var g: float = 0.0
	for i in n:
		f += (randf_range(-1.0, 1.0) - f) * 0.6
		g += (randf_range(-1.0, 1.0) - g) * 0.02          # slow wobble in the hiss level
		bytes.encode_s16(i * 2, int(clampf(f * (0.7 + 0.3 * g), -1.0, 1.0) * 9000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


## Crackle burst: a cluster of sharp pops in noise, length `secs`, density `dens`.
func _make_crackle(secs: float, dens: float) -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(secs * rate)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var f: float = 0.0
	var pop: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		if randf() < dens * 0.004:
			pop = randf_range(0.5, 1.0) * (1.0 if randf() > 0.5 else -1.0)
		pop *= 0.93
		f += (randf_range(-1.0, 1.0) - f) * 0.7
		var env: float = sin(PI * t)
		bytes.encode_s16(i * 2, int(clampf((f * 0.35 + pop) * env, -1.0, 1.0) * 24000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


## Squelch tail when a transmission ends: a short rush of noise that cuts off.
func _make_squelch_close() -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(0.22 * rate)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var f: float = 0.0
	for i in n:
		var t: float = float(i) / float(rate)
		f += (randf_range(-1.0, 1.0) - f) * 0.65
		var env: float = minf(t * 60.0, 1.0) * (1.0 - smoothstep(0.15, 0.22, t))
		bytes.encode_s16(i * 2, int(clampf(f * env, -1.0, 1.0) * 20000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


func _play_squelch() -> void:
	if _ui_player == null:
		_ui_player = AudioStreamPlayer.new()
		_ui_player.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		add_child(_ui_player)
		_streams["click"] = _make_squelch()
	_ui_player.stream = _streams["click"]
	_ui_player.volume_db = -14.0 + linear_to_db(maxf(AudioManager.radio_volume * AudioManager.master_volume, 0.0001))
	_ui_player.play()


## Short band-limited noise burst with a tick: the "mic key" squelch.
func _make_squelch() -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(0.16 * rate)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var f: float = 0.0
	for i in n:
		var t: float = float(i) / float(rate)
		f += (randf_range(-1.0, 1.0) - f) * 0.5
		var env: float = exp(-t * 22.0) * minf(t * 400.0, 1.0)
		var tone: float = sin(TAU * 1400.0 * t) * 0.25 * exp(-t * 30.0)
		bytes.encode_s16(i * 2, int(clampf((f * 0.8 + tone) * env, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


# ------------------------------------------------------------------ input / orders
func _unhandled_input(event: InputEvent) -> void:
	if GameState.paused:
		return
	if event.is_action_pressed("radio_form"):
		order("form")
	elif event.is_action_pressed("radio_attack"):
		order("attack")
	elif event.is_action_pressed("radio_cover"):
		order("cover")
	elif event.is_action_pressed("radio_rtb"):
		order("rtb")


func order(kind: String) -> void:
	var pl: Aircraft = _player()
	if pl == null or pl.state != Aircraft.State.ALIVE:
		return
	var wm: Array = _wingmen()
	var me: String = callsign_of(pl)
	if wm.is_empty():
		say(me, "Anyone on this frequency? Nobody's flying with me.", Kind.PLAYER, 0.0, "order_alone")
		return
	match kind:
		"form":
			var already_forming: bool = _all_forming(wm)
			if _form_used and already_forming:
				formation = (formation + 1) % FORMATION_NAMES.size()
			_form_used = true
			_apply_formation(wm, pl)
			say(me, "%s, form on me, %s." % [_flight_name(pl), FORMATION_NAMES[formation].to_lower()], Kind.PLAYER, 0.0, "order_form_" + ["vic", "echelon", "line", "trail"][formation])
			# the whole flight answers the first order only; a repeat (or a change of shape) gets one reply, not a chorus
			if already_forming:
				_reply_all(wm.slice(0, 1), AIPilot.Order.FORM, ["Roger, changing formation."], "reply_form_change")
			else:
				_reply_all(wm, AIPilot.Order.FORM, [], "reply_form")
		"attack":
			var tgt: Aircraft = _player_target(pl)
			if tgt == null:
				say(me, "%s, attack my target." % _flight_name(pl), Kind.PLAYER, 0.0, "order_attack")
				_reply_all(wm, AIPilot.Order.FORM, [], "reply_notarget")
				return
			say(me, "%s, attack my target, %s." % [_flight_name(pl), _describe(tgt, pl)], Kind.PLAYER, 0.0, "order_attack")
			for w in wm:
				var p: AIPilot = AIFactory.pilot_of(w)
				p.set_order(AIPilot.Order.ATTACK, tgt)
			_reply_all(wm, AIPilot.Order.ATTACK, [], "reply_attack")
		"cover":
			say(me, "%s, cover me, I'm going in." % _flight_name(pl), Kind.PLAYER, 0.0, "order_cover")
			_reply_all(wm, AIPilot.Order.COVER, [], "reply_cover")
		"rtb":
			say(me, "%s, break off and return to base." % _flight_name(pl), Kind.PLAYER, 0.0, "order_rtb")
			_reply_all(wm, AIPilot.Order.RTB, [], "reply_rtb")


func _all_forming(wm: Array) -> bool:
	for w in wm:
		if AIFactory.pilot_of(w).order != AIPilot.Order.FORM:
			return false
	return true


func _flight_name(pl: Aircraft) -> String:
	return "%s flight" % _squadron_name(pl.team)


func _reply_all(wm: Array, ord: int, lines: Array, clip: String = "") -> void:
	var i: int = 0
	for w in wm:
		var p: AIPilot = AIFactory.pilot_of(w)
		if ord != AIPilot.Order.ATTACK:
			p.set_order(ord, null)
		if lines.is_empty() and TAKES.has(clip):
			var tk: Array = take(clip, (w as Aircraft).team)      # recorded takes; each wingman gets a different one
			say(callsign_of(w), tk[0], Kind.FRIENDLY, 1.0 + float(i) * 1.1, tk[1])
		else:
			var li: int = _pick_index(clip if clip != "" else "reply_%d" % ord, lines.size())
			say(callsign_of(w), lines[li], Kind.FRIENDLY, 1.0 + float(i) * 1.1, ("%s_%d" % [clip, li + 1]) if clip != "" else "")
		i += 1


## Offsets in the leader's frame (x right, y up, z back) for wingman k of n.
func formation_offset(k: int, n: int) -> Vector3:
	var s: float = 1.0
	match formation:
		Formation.VIC:
			return Vector3((70.0 if k % 2 == 0 else -70.0) * (1.0 + float(k / 2) * 0.9) * s, -4.0 - float(k) * 1.5, 90.0 * (1.0 + float(k / 2) * 0.9))
		Formation.ECHELON:
			return Vector3(75.0 * float(k + 1), -4.0 - float(k) * 2.0, 85.0 * float(k + 1))
		Formation.LINE_ABREAST:
			return Vector3((80.0 if k % 2 == 0 else -80.0) * (1.0 + float(k / 2)), -2.0, 8.0)
		_:
			return Vector3(0.0, -6.0 - float(k) * 3.0, 105.0 * float(k + 1))
	return Vector3(70, -5, 90)


func _apply_formation(wm: Array, pl: Aircraft) -> void:
	for i in wm.size():
		AIFactory.pilot_of(wm[i]).set_leader(pl, formation_offset(i, wm.size()))


## Enemy nearest to the player's nose, in front and within 7 km.
func _player_target(pl: Aircraft) -> Aircraft:
	var best: Aircraft = null
	var best_score: float = 1.0e9
	var f: Vector3 = pl.get_forward()
	for n in get_tree().get_nodes_in_group("aircraft"):
		var o: Aircraft = n as Aircraft
		if o == null or o.team == pl.team or o.team == "Neutral" or o.state != Aircraft.State.ALIVE:
			continue
		var rel: Vector3 = o.global_position - pl.global_position
		var d: float = rel.length()
		if d > 7000.0 or d < 1.0:
			continue
		var ang: float = acos(clampf(f.dot(rel / d), -1.0, 1.0))
		var score: float = d * (1.0 + ang * 2.0)
		if score < best_score:
			best_score = score
			best = o
	return best


# ------------------------------------------------------------------ descriptions
## "11 o'clock high" etc, relative to the observer's nose.
func clock_position(from: Aircraft, to_pos: Vector3) -> String:
	var rel: Vector3 = to_pos - from.global_position
	var f: Vector3 = from.get_forward()
	var f_flat := Vector2(f.x, f.z).normalized()
	var r_flat := Vector2(rel.x, rel.z)
	if r_flat.length() < 1.0 or f_flat.length() < 0.01:
		return "overhead"
	var ang: float = rad_to_deg(f_flat.angle_to(r_flat.normalized()))     # + = to the right (x right, z down)
	var clock: int = int(round(fposmod(ang, 360.0) / 30.0))
	if clock == 0:
		clock = 12
	var dh: float = rel.y / WorldCoords.VERTICAL_SCALE
	var level: String = "high" if dh > 250.0 else ("low" if dh < -250.0 else "level")
	return "%d o'clock %s" % [clock, level]


func clock_number(from: Aircraft, to_pos: Vector3) -> int:
	var rel: Vector3 = to_pos - from.global_position
	var f: Vector3 = from.get_forward()
	var ang: float = rad_to_deg(Vector2(f.x, f.z).normalized().angle_to(Vector2(rel.x, rel.z).normalized()))
	var clock: int = int(round(fposmod(ang, 360.0) / 30.0))
	return 12 if clock == 0 else clock


func _describe(t: Aircraft, from: Aircraft) -> String:
	var d: float = t.global_position.distance_to(from.global_position)
	return "%s, %s" % [clock_position(from, t.global_position), "%.1f miles" % (d / 1609.0 * 1.0)]


# ------------------------------------------------------------------ automatic calls
func _process(delta: float) -> void:
	var lp: Aircraft = _player()
	if lp != null and lp.process_mode == Node.PROCESS_MODE_DISABLED:
		if _static_player != null and _static_player.playing:
			_static_player.stop()
		return          # loading screen: the aircraft is frozen, keep the frequency quiet until the sortie starts
	_update_static(delta)
	_poll_pending_clip(delta)
	_pump_queue()
	_scan_t -= delta
	if _scan_t > 0.0 or GameState.paused:
		return
	_scan_t = 1.0
	var pl: Aircraft = _player()
	if pl == null or pl.state != Aircraft.State.ALIVE:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	var wm: Array = _wingmen()
	if not _hq_intro_done:
		_hq_intro_done = true
		var wind: Vector3 = pl.wind
		var wd: String = "%03d at %d" % [int(WorldCoords.dir_to_heading(Vector3(-wind.x, 0.0, -wind.z))), int(round(wind.length()))]
		_chatter_t = randf_range(60.0, 120.0)
		# only on the runway (or a scramble with wingmen), and not the instant the screen fades in
		if pl.on_ground or not wm.is_empty():
			var tk: Array = take("intro_scramble" if not wm.is_empty() else "intro_takeoff", pl.team)
			say("Control", "%s, this is Control. Wind %s. %s" % [callsign_of(pl), wd, tk[0]], Kind.CONTROL, randf_range(3.0, 8.0), tk[1])
		for w in wm:
			callsign_of(w)
		if not wm.is_empty():
			_apply_formation(wm, pl)
	# bandit calls: a wingman (or the control room) reports enemies within 5.5 km
	if now - _last_bandit_call > 16.0:
		var caller: Aircraft = pl
		if not wm.is_empty():
			caller = wm[randi() % wm.size()]
		var closest: Aircraft = null
		var cd: float = 5500.0
		var group: int = 0
		for n in get_tree().get_nodes_in_group("aircraft"):
			var o: Aircraft = n as Aircraft
			if o == null or o.team == pl.team or o.team == "Neutral" or o.state != Aircraft.State.ALIVE:
				continue
			var d: float = o.global_position.distance_to(pl.global_position)
			if d < 5500.0:
				group += 1
				if d < cd:
					cd = d
					closest = o
		if closest != null and now - float(_spotted.get(closest.get_instance_id(), -99.0)) > 40.0:
			_spotted[closest.get_instance_id()] = now
			_last_bandit_call = now
			var heavy: String = "Bombers" if closest.is_in_group("bomber") else "Bandits"
			var who: String = callsign_of(caller) if caller != pl else "Control"
			var cnt: String = "" if group < 2 else " %d aircraft," % group
			# well above or below: say so ("three o'clock high"), with its own recorded calls
			var dy: float = (closest.global_position.y - pl.global_position.y) / WorldCoords.VERTICAL_SCALE
			var hl: String = "high" if dy > 300.0 else ("low" if dy < -300.0 else "")
			var skind: String = "bombers" if heavy == "Bombers" else "bandits"
			var snum: int = clock_number(pl, closest.global_position)
			var sclip: String = _spot_clip(skind, snum)
			if hl != "":
				var hb: String = "%s_%02d_%s" % [skind, snum, hl]
				var hopts: Array = []
				for hc in [hb, hb + "2"]:
					if has_clip(hc):
						hopts.append(hc)
				if not hopts.is_empty():
					sclip = hopts[randi() % hopts.size()]
			say(who, "%s!%s %s%s, %s." % [heavy, cnt, clock_position(pl, closest.global_position), (" " + hl) if hl != "" else "", "%.1f miles" % (cd / 1609.0)], Kind.CONTROL if caller == pl else Kind.FRIENDLY, 0.0, sclip)
	# ambient chatter at random intervals, kept out of the way of combat calls
	_chatter_t -= 1.0
	if _chatter_t <= 0.0:
		_chatter_t = randf_range(70.0, 150.0)
		if now - _last_bandit_call > 20.0 and _queue.is_empty():
			_ambient_chatter(pl)
	# tower: approach to a friendly airfield, but only after having been well away from every field
	var nearest: float = 1.0e9
	for n0 in get_tree().get_nodes_in_group("airfield"):
		var af0: Airfield = n0 as Airfield
		if af0 != null and af0.team == pl.team:
			nearest = minf(nearest, Vector2(pl.global_position.x - af0.global_position.x, pl.global_position.z - af0.global_position.z).length())
	if nearest > 9000.0:
		_left_field = true
		_tower_called.clear()
	for n in get_tree().get_nodes_in_group("airfield"):
		var af: Airfield = n as Airfield
		if af == null or af.team != pl.team or _tower_called.has(af.airfield_name) or not _left_field:
			continue
		var dd: float = Vector2(pl.global_position.x - af.global_position.x, pl.global_position.z - af.global_position.z).length()
		if dd < 4500.0 and pl.altitude_agl > 40.0 and not pl.on_ground:
			_tower_called[af.airfield_name] = true
			var w2: Vector3 = pl.wind
			var tt: Array = take("tower_land" if w2.length() < 16.0 else "tower_land_wind", pl.team)
			say("%s Tower" % af.airfield_name, "%s, runway heading %03d, wind %03d at %d. %s" % [callsign_of(pl), int(af.heading_deg), int(WorldCoords.dir_to_heading(Vector3(-w2.x, 0.0, -w2.z))), int(round(w2.length())), tt[0]], Kind.CONTROL, 0.0, tt[1])
			break


## Background traffic on the frequency: sector control vectors, other squadrons, coastal and weather reports.
const CHATTER_ALLIES := [
	["Sector Control", "All Hornchurch aircraft, bandits angels one-five over Dover. Vector one-two-zero."],
	["Sector Control", "Hello Blue Leader, Sector Control. Twenty-plus bandits approaching Dungeness, angels twelve."],
	["Biggin Control", "Tiger squadron, pancake, pancake. Refuel and stand by."],
	["Red Leader", "Tally-ho! Tally-ho! Bandits nine o'clock low."],
	["Coastguard Dover", "Convoy entering the Downs, balloons flying. Fighter cover requested."],
	["Observer Corps", "Raid four-two crossing the coast at Beachy Head, heading north."],
	["Tangmere Control", "Weather: cloud base two thousand feet over the Isle of Wight, visibility good."],
	["Green Two", "Green Leader, I've got a glycol leak, returning to base."],
	["Sector Control", "Hello all aircraft, enemy fighters sweeping over Folkestone. Keep a good lookout."],
	["Yellow Leader", "Yellow section, buster! Bombers heading for Manston."],
	["Air-Sea Rescue", "Launch away from Ramsgate, searching for a pilot down off the North Foreland."],
	["Sector Control", "Hello Red Leader, vector two-seven-zero, angels eighteen. Bandits over Maidstone."],
	["Sector Control", "All aircraft, plots fading over the Channel. Resume patrol."],
	["Blue Leader", "Blue section, line astern, follow me down. Keep it tight."],
	["Green Leader", "Green Two, you're straggling. Close up, there's a good chap."],
	["Red Three", "Red Three here. Bandit destroyed, one damaged, coming home."],
	["Observer Corps", "Raid five-one, fifteen-plus, over Ashford at ten thousand. Heading north-west."],
	["Coastguard Dover", "Two ships of the convoy hit off Folkestone. Lifeboat launched."],
	["Air-Sea Rescue", "Picked him up off Margate. Cold and cross, but he'll do."],
	["Sector Control", "Hello all aircraft, balloons are flying over Dover. Keep clear below five thousand."],
	["Sector Control", "Hello Tiger Leader, bandits angels two-zero over Canterbury. Buster."],
	["Red Leader", "Red section, break left! Break left!"],
	["Green Leader", "Yellow Two, keep your eyes on the sun."],
	["Blue Three", "Blue Three, I have a Messerschmitt on my tail!"],
	["Observer Corps", "Thirty-plus over Hastings, height twelve thousand, heading north."],
	["Coastguard Dover", "Shelling from the French coast again. Dover harbour hit."],
	["Sector Control", "All aircraft, pancake, pancake. Raid has turned back."],
	["Red Leader", "Tally-ho! Bombers dead ahead. Line astern, go!"],
	["Sector Control", "Hello Red Leader, your bandits are now over Ashford. Vector one-one-zero."],
	["Green Leader", "Green section, reforming over Biggin. Anybody seen Green Three?"],
	["Blue Three", "I am out of ammunition. Returning to base."],
	["Observer Corps", "One aircraft down in flames near Tenterden. Parachute seen."],
	["Sector Control", "Hello all aircraft, Diver warning. Flying bombs over Hythe."],
	["Red Leader", "Keep it tight, chaps. Here they come."],
	["Sector Control", "Hello Blue Leader, vector zero-nine-zero, angels fifteen. Many bandits."],
	["Sector Control", "All aircraft, raid crossing the coast at Dungeness. Height twenty thousand."],
	["Sector Control", "Hello Gannic Leader, orbit Maidstone, angels twelve."],
	["Sector Control", "Bandits now over Tonbridge. Buster, buster."],
	["Sector Control", "Hello Red Leader, there are forty-plus heading for Biggin Hill."],
	["Sector Control", "All aircraft, keep a sharp lookout over the estuary."],
	["Sector Control", "Hello Tiger Leader, return to base. Raid has passed."],
	["Sector Control", "Hello all aircraft, enemy reconnaissance over Portsmouth, very high."],
	["Red Leader", "Line astern, chaps. Follow me in."],
	["Red Leader", "Steady. Wait for it. Now, go!"],
	["Red Leader", "Bombers below! Head-on attack, follow me!"],
	["Red Leader", "Tally-ho! Snappers above, watch yourselves."],
	["Red Leader", "Reform on me over the coast. Who's still with me?"],
	["Green Leader", "Green section, line abreast. Keep your eyes open."],
	["Green Leader", "Green Two, where the devil are you?"],
	["Green Leader", "Watch the sun, there's always one up there."],
	["Green Leader", "Nice and easy, let them come to us."],
	["Green Leader", "Pancaking now. Green section, follow me down."],
	["Blue Three", "I got a Dornier. He went into the sea."],
	["Blue Three", "My windscreen is covered in oil, I cannot see!"],
	["Blue Three", "One Messerschmitt destroyed near Ashford."],
	["Blue Three", "I have lost the others. Returning alone."],
	["Blue Three", "Bombers turning back over the coast. I follow."],
	["Observer Corps", "Raid six-two, twenty-plus, over Rye. Heading west."],
	["Observer Corps", "Single aircraft low over Romney Marsh. Hostile."],
	["Observer Corps", "Dogfight overhead at Lydd. Aircraft falling."],
	["Observer Corps", "Raid seven-three, fifty-plus, height fifteen thousand over Deal."],
	["Observer Corps", "Bombers turning south over Canterbury."],
	["Coastguard Dover", "Aircraft down in the sea off Folkestone. Launch on its way."],
	["Coastguard Dover", "Convoy clear of the Downs, heading west."],
	["Coastguard Dover", "E-boats reported off the Goodwin Sands."],
	["Coastguard Dover", "Dover balloons coming down. Gale warning."],
	["Air-Sea Rescue", "Launch one-four-seven, searching off Dungeness."],
	["Air-Sea Rescue", "Got him! Wet through, but he's laughing."],
	["Air-Sea Rescue", "No sign of the dinghy. Widening the search."],
	["Biggin Control", "Biggin calling. Runway clear of craters now, you may land."],
	["Biggin Control", "Hello all Biggin aircraft, the field has been bombed. Land at Kenley."],
	["Yellow Leader", "Yellow section, rejoin. We'll go round again."],
	["Yellow Leader", "Watch the escort, they're coming down!"],
	["Yellow Leader", "Yellow One, ammunition gone. Heading home."],
	["Sector Control", "Hello Blue Leader, many bandits approaching Manston from the east."],
	["Sector Control", "All aircraft, the Hornchurch squadron is engaged. Support them."],
	["Sector Control", "Hello Red Leader, steer three-four-zero. Bandits at angels eighteen."],
	["Sector Control", "Raid has split. Half heading for Croydon, half for the docks."],
	["Sector Control", "Hello Green Leader, you are clear to pancake. Well done."],
	["Sector Control", "All aircraft, there are friendly fighters over Gravesend."],
	["Sector Control", "Hello Tiger Leader, investigate a single bandit off Beachy Head."],
	["Sector Control", "Raid three-one is turning back. Chase them out over the sea."],
	["Red Leader", "Hold your fire till you're close. Make it count."],
	["Red Leader", "There's the escort, up sun. Watch them."],
	["Red Leader", "Good show, everybody. Let's go home."],
	["Red Leader", "Stay with me, Red Two, don't straggle."],
	["Green Leader", "There's a Heinkel on his own down there. He's ours."],
	["Green Leader", "Watch out for the rear gunner, he's still firing."],
	["Green Leader", "Climb, climb! Get above them!"],
	["Green Leader", "That was close. Everyone all right?"],
	["Blue Three", "I have hit his engine. He is smoking."],
	["Blue Three", "Heinkel destroyed. Two parachutes."],
	["Blue Three", "I see bombers, many bombers, over the river."],
	["Blue Three", "My radio is bad. Can you hear me?"],
	["Observer Corps", "Aircraft crashed near Faversham. Burning."],
	["Observer Corps", "Raid eight-one, thirty-plus, over Maidstone at fifteen thousand."],
	["Observer Corps", "Very high aircraft over Ashford, leaving trails."],
	["Observer Corps", "Bombs falling on Dover harbour."],
	["Coastguard Dover", "Dornier down in the sea off St Margaret's. Crew in a dinghy."],
	["Coastguard Dover", "Heavy guns firing from Gris-Nez. Shells falling on the town."],
	["Coastguard Dover", "Visibility down to two miles over the Strait."],
	["Air-Sea Rescue", "Launch returning to Dover with two survivors."],
	["Air-Sea Rescue", "Dye marker seen! Turning towards it now."],
	["Air-Sea Rescue", "We're being shot at! Fighter cover wanted."],
	["Biggin Control", "Biggin aircraft, the runway is clear. Watch the crater by the hangar."],
	["Yellow Leader", "Yellow section, buster. They're going for the airfield."],
	["Yellow Leader", "Break, Yellow Two, break! One behind you!"],
	["Yellow Leader", "Got him. One Messerschmitt destroyed over Lympne."],
	["Sector Control", "Hello all aircraft, enemy fighters strafing Hawkinge."],
	["Sector Control", "Hello Red Leader, your bandits are above you now."],
	["Sector Control", "Hello Red Leader, raid is approaching Kenley. Buster."],
	["Sector Control", "All aircraft, bandits over the Isle of Sheppey."],
	["Sector Control", "Hello Blue Leader, pancake at Hawkinge. Refuel and stand by."],
	["Sector Control", "Hello all aircraft, weather closing in from the west."],
	["Red Leader", "Here they come. Pick your targets."],
	["Red Leader", "Red section, follow me through. Don't stop."],
	["Green Leader", "Two of them on the deck, heading for France."],
	["Green Leader", "Green section, short bursts. Save your ammo."],
	["Blue Three", "I am following one Dornier. He is low over the sea."],
	["Blue Three", "My guns are empty. I come home."],
	["Observer Corps", "Parachute coming down near Hythe."],
	["Observer Corps", "Twelve-plus, low, crossing the coast at Hastings."],
	["Coastguard Dover", "Convoy under attack off Dover. Several ships hit."],
	["Air-Sea Rescue", "Two in the water off Ramsgate. Going in now."],
	["Yellow Leader", "Yellow section, orbit here. Wait for them."],
	["Yellow Leader", "Bombers heading home. Let's give them a send-off."],
	["Biggin Control", "Biggin calling. Field is clear, land at your discretion."],
	["Sector Control", "Hello Tiger Leader, well done. Raid has broken up."],
	["Sector Control", "Hello Red Leader, many bandits over Deal. Angels twenty."],
	["Red Leader", "Steady, chaps. Let them come."],
	["Green Leader", "Green Three, you're on fire! Get out!"],
	["Blue Three", "I attack the leader. Cover me."],
	["Observer Corps", "Raid nine-four over Dungeness. Forty-plus."],
	["Yellow Leader", "Watch your fuel, Yellow section."],
	["Air-Sea Rescue", "Searching off Folkestone. Light's going."],
	["Sector Control", "All aircraft, stand down. Good work today."],
	["Coastguard Dover", "Mines reported in the harbour approach."],
	["Red Leader", "Snappers coming down! Break!"],
	["Sector Control", "Hello Blue Leader, bandits over Dover, angels fifteen."],
	["Red Leader", "Red section, go!"],
	["Green Leader", "Green Two, close up."],
	["Blue Three", "One Heinkel is smoking. I follow him."],
	["Observer Corps", "Ten-plus over Rye, heading north."],
	["Yellow Leader", "Yellow section, line astern."],
	["Sector Control", "All aircraft, raid is over Canterbury."],
	["Red Leader", "Watch your tails, chaps."],
	["Coastguard Dover", "Aircraft in the sea off Deal."],
	["Air-Sea Rescue", "Launch away from Dover."],
	["Sector Control", "Hello Green Leader, pancake."],
	["Green Leader", "Tally-ho! Bandits below!"],
	["Blue Three", "I am hit, but I am all right."],
	["Yellow Leader", "Home, Yellow section."],
	["Red Leader", "Good hunting, everyone."],
	["Red Leader", "Break left!"],
	["Green Leader", "Watch it, Green Two!"],
	["Sector Control", "Bandits over Hythe."],
	["Yellow Leader", "Yellow, follow me."],
	["Blue Three", "I see them!"],
	["Red Leader", "Go, go, go!"],
	["Observer Corps", "Aircraft down near Lydd."],
	["Sector Control", "All aircraft, pancake."],
]
const CHATTER_AXIS := [
	["Jafü 2", "All Jagdgruppen: enemy convoy in the Strait of Dover, escort the Stukas. Angels four thousand."],
	["Kanal Control", "Achtung, Spitfires reported over Cap Gris-Nez, height five thousand."],
	["Rot Eins", "Horrido! One Spitfire down near Folkestone."],
	["Seenotdienst", "Rescue boat leaving Boulogne for a pilot in the water, quadrant Anton Dora."],
	["Freya Wissant", "Large formation forming over Kent. Course one-four-zero."],
	["Kanal Control", "Weather: haze over the Channel, cloud base six hundred metres at Calais."],
	["Gelb Zwei", "Gelb Eins, fuel is getting low, I am turning for home."],
	["Kanal Control", "Bombers turning for home over Dungeness, cover them across the coast."],
	["Flak Calais", "Calais flak engaging enemy aircraft over the harbour."],
	["Jafü 2", "All Staffeln, the Stukas are over the target. Hold your height above them."],
	["Kanal Control", "Achtung, Hurricanes climbing over Dungeness. Strength twelve."],
	["Schwarm Blau", "Two Spitfires below us, I am going down. Cover me."],
	["Freya Wissant", "Plots over Kent are breaking up. Enemy fighters landing."],
	["Seenotdienst", "Seaplane on its way to the pilot off Cap Gris-Nez."],
	["Flak Boulogne", "Boulogne flak! Aircraft over the harbour, open fire!"],
	["Gelb Drei", "My radiator is hit. I am going home at low level."],
	["Jafü 2", "Bomber formation returning over Calais. All fighters, escort them home."],
	["Jafü 2", "All Schwärme, Spitfires above you over Dover. Watch the sun."],
	["Rot Drei", "Achtung, Spitfire behind me! Get him off!"],
	["Freya Wissant", "Twelve enemy fighters climbing over Hawkinge."],
	["Flak Dünkirchen", "Dunkirk flak engaging. Low flyers over the harbour!"],
	["Jafü 2", "Return to base. Fuel reserves must not be risked."],
	["Rot Drei", "I have hit a Hurricane. He is smoking badly."],
	["Freya Wissant", "Formation over the Thames estuary. Course east."],
	["Jafü 2", "Stukas are going in. Hold the fighters off them."],
	["Jafü 2", "All aircraft, the bombers are over the target. Hold your positions."],
	["Rot Drei", "Rot Drei here. One Hurricane down, I am coming home."],
	["Freya Wissant", "Enemy fighters landing at Manston. They will be up again soon."],
	["Jafü 2", "Sea rescue reports a pilot picked up off Calais."],
	["Flak Dünkirchen", "Cease fire! Our own aircraft overhead!"],
	["Rot Drei", "I am out of ammunition. Returning home."],
	["Jafü 2", "All Staffeln, enemy fighters over Canterbury. Height six thousand."],
	["Jafü 2", "Free hunt over Kent approved. Good hunting."],
	["Jafü 2", "Bombers are forming over Cap Blanc-Nez. Join them now."],
	["Jafü 2", "Close escort, stay with the bombers. Do not chase."],
	["Jafü 2", "All aircraft, return. Fuel is the priority."],
	["Jafü 2", "Spitfires climbing from Manston. Watch your height."],
	["Jafü 2", "The raid on London is complete. Cover the withdrawal."],
	["Jafü 2", "Enemy convoy off Dover. Stukas are on their way."],
	["Kanal Control", "Weather over Kent is clearing. Visibility good."],
	["Kanal Control", "Strong wind from the west. Watch your fuel coming home."],
	["Kanal Control", "Hurricanes over Folkestone. Strength twenty."],
	["Kanal Control", "Enemy fighters landing. Now is the time."],
	["Rot Drei", "I have him! Spitfire burning!"],
	["Rot Drei", "Red light on, the fuel is nearly gone."],
	["Rot Drei", "Two Hurricanes below. I go down."],
	["Rot Drei", "Where is my Rottenflieger? I have lost him."],
	["Rot Drei", "My engine is coughing. I go home low."],
	["Rot Drei", "A Spitfire went into the sea. Nobody got out."],
	["Gelb Eins", "Gelb Schwarm, follow me. We go in from the sun."],
	["Gelb Eins", "Achtung, Spitfires behind! Break right!"],
	["Gelb Eins", "The bombers are burning. We came too late."],
	["Gelb Eins", "Back over the Channel. Everybody here?"],
	["Freya Wissant", "Enemy formation forming over the Thames."],
	["Freya Wissant", "Twenty aircraft climbing south of London."],
	["Freya Wissant", "Single aircraft crossing the Channel at low level."],
	["Freya Wissant", "Plots over Dover are fading. They have landed."],
	["Freya Wissant", "A large formation is coming over the sea toward Calais."],
	["Flak Calais", "Calais flak! Enemy bombers over the docks!"],
	["Flak Calais", "Barrage fire! All guns, fire!"],
	["Flak Calais", "One bomber hit! He is going down!"],
	["Flak Calais", "Hold your fire, our fighters are passing over."],
	["Seenotdienst", "Seaplane landing beside the dinghy now."],
	["Seenotdienst", "Pilot rescued off Boulogne. He is alive."],
	["Seenotdienst", "Searching off Gris-Nez. No sign yet."],
	["Seenotdienst", "Rescue buoy in quadrant Berta. Two men aboard."],
	["Kanal Control", "All aircraft, Tommies are attacking our airfields. Return carefully."],
	["Jafü 2", "Weiss Schwarm, you are cleared for a free hunt."],
	["Gelb Eins", "Spitfire on my tail, I cannot shake him!"],
	["Rot Drei", "Bomber down near Maidstone. Parachutes seen."],
	["Freya Wissant", "Enemy fighters moving east along the coast."],
	["Jafü 2", "All aircraft, Spitfires over Dungeness. Height seven thousand."],
	["Jafü 2", "The Stukas need cover over the convoy. Go now."],
	["Jafü 2", "Second wave forming over Calais. Join them."],
	["Jafü 2", "Enemy fighters gathering over London. Expect strong defence."],
	["Jafü 2", "All aircraft, the bombers are returning. Bring them home."],
	["Jafü 2", "Weiss Schwarm, return to base. Well done."],
	["Kanal Control", "Haze building over the Channel. Fly on instruments if needed."],
	["Kanal Control", "Enemy convoy leaving the Downs. Report its course."],
	["Kanal Control", "Spitfires over Gris-Nez! Fighters scramble!"],
	["Rot Drei", "I see the bombers burning ahead."],
	["Rot Drei", "Spitfire in my sights. Firing!"],
	["Rot Drei", "I am hit in the radiator. Coolant is boiling."],
	["Rot Drei", "Over the coast now. Home soon."],
	["Gelb Eins", "Stay together! Do not chase them down."],
	["Gelb Eins", "The English are everywhere today."],
	["Gelb Eins", "One Hurricane down. He hit the trees."],
	["Gelb Eins", "Gelb Zwei is missing. Anyone see him?"],
	["Freya Wissant", "Enemy fighters climbing over Biggin Hill."],
	["Freya Wissant", "Formation of thirty over Dover, course south."],
	["Freya Wissant", "Contacts low over the water, approaching Boulogne."],
	["Freya Wissant", "Plots over Kent are increasing. Many aircraft."],
	["Flak Calais", "Searchlights on! Bombers over the harbour!"],
	["Flak Calais", "Reload! Keep firing!"],
	["Flak Calais", "Low flyer over the airfield! Light flak, fire!"],
	["Seenotdienst", "Boat leaving Calais. Pilot reported in quadrant Cäsar."],
	["Seenotdienst", "We have him. Cold, but alive."],
	["Seenotdienst", "English fighters over the rescue boat. Help needed."],
	["Kanal Control", "All Staffeln, change frequency. The English are listening."],
	["Jafü 2", "Rot Schwarm, a single Spitfire over Dunkirk. Get him."],
	["Gelb Eins", "Four Spitfires below. We attack from the sun."],
	["Rot Drei", "Bomber hit by flak. Falling behind the formation."],
	["Freya Wissant", "Enemy bombers forming over the Thames. Many."],
	["Jafü 2", "Good work today. All Staffeln, land and refuel."],
	["Kanal Control", "Night fighters are up. Stay clear of the searchlights."],
	["Flak Calais", "Barrage balloons up over the port. Watch your height."],
	["Seenotdienst", "Searching in the dark. Fire a flare if you hear us."],
	["Jafü 2", "All aircraft, Hurricanes over the Thames. Height five thousand."],
	["Jafü 2", "Rot Schwarm, escort the Stukas home."],
	["Jafü 2", "Enemy bombers over Boulogne. All fighters, scramble."],
	["Kanal Control", "Cloud base falling over the coast. Watch out."],
	["Rot Drei", "Spitfire down near Dover. I saw it crash."],
	["Rot Drei", "My ammunition is finished. I turn for home."],
	["Gelb Eins", "Bombers below, they are being attacked. Down!"],
	["Gelb Eins", "Gelb Schwarm, climb. They are above us."],
	["Freya Wissant", "Enemy fighters heading toward Calais. Low."],
	["Freya Wissant", "Large formation now over Ashford. Course south-east."],
	["Flak Calais", "Enemy fighter shot down over the beach!"],
	["Flak Calais", "Ammunition! More ammunition to gun three!"],
	["Seenotdienst", "Dinghy sighted. Two men waving."],
	["Seenotdienst", "Rescue complete. Returning to Boulogne."],
	["Kanal Control", "Bombers back over France. Well done, everyone."],
	["Jafü 2", "Weiss Schwarm, free hunt over Dover approved."],
	["Gelb Eins", "Two Hurricanes burning. Good work, Gelb Schwarm."],
	["Rot Drei", "Back over the coast. My compass is shot away."],
	["Jafü 2", "All aircraft, enemy fighters over Calais. Climb."],
	["Gelb Eins", "Stay with me, Gelb Zwei."],
	["Rot Drei", "Spitfire behind me! Help!"],
	["Freya Wissant", "Enemy raid over Kent, forty aircraft."],
	["Flak Calais", "All guns, open fire!"],
	["Kanal Control", "Land at Wissant. Your field is bombed."],
	["Seenotdienst", "Searching in quadrant Anton. Nothing yet."],
	["Jafü 2", "All Staffeln, well done today. Land and rest."],
	["Gelb Eins", "Fuel is low. Gelb Schwarm, home."],
	["Rot Drei", "Hurricane on fire over Folkestone."],
	["Jafü 2", "All aircraft, Spitfires over Folkestone."],
	["Gelb Eins", "Gelb Schwarm, attack!"],
	["Rot Drei", "I have one! He is burning!"],
	["Freya Wissant", "Twenty aircraft over Dover."],
	["Flak Calais", "Fire! Fire!"],
	["Kanal Control", "Return to base now."],
	["Jafü 2", "Bombers over the target."],
	["Gelb Eins", "Watch the sun!"],
	["Rot Drei", "Fuel low. Going home."],
	["Seenotdienst", "Boat on its way."],
	["Jafü 2", "Free hunt approved."],
	["Gelb Eins", "Spitfires above us!"],
	["Rot Drei", "Hurricane down near Dover."],
	["Kanal Control", "Weather is clearing."],
	["Freya Wissant", "Enemy fighters landing."],
	["Gelb Eins", "Break right!"],
	["Rot Drei", "I see them!"],
	["Jafü 2", "Spitfires over Dover."],
	["Gelb Eins", "Follow me!"],
	["Flak Calais", "Open fire!"],
	["Rot Drei", "He is down!"],
	["Freya Wissant", "Aircraft over Deal."],
	["Jafü 2", "All aircraft, return."],
]


func _ambient_chatter(pl: Aircraft) -> void:
	var lines: Array = CHATTER_AXIS if pl.team == "Axis" else CHATTER_ALLIES
	# only lines with a recording (the newer chatter may not be generated yet); never the same one twice running
	var avail: Array = []
	for k in lines.size():
		if has_clip("chatter_%02d" % (k + 1)) and k != int(_last_pick.get("chatter", -1)):
			avail.append(k)
	if avail.is_empty():
		avail = range(mini(lines.size(), 9))
	var ci: int = int(avail[randi() % avail.size()])
	_last_pick["chatter"] = ci
	var ln: Array = lines[ci]
	var sender: String = String(ln[0])
	say(sender, String(ln[1]), Kind.CONTROL if "Control" in sender or "Jafü" in sender or "Freya" in sender or "Observer" in sender else Kind.FRIENDLY, 0.0, "chatter_%02d" % (ci + 1))


func _on_node_added(n: Node) -> void:
	var a: Aircraft = n as Aircraft
	if a == null:
		return
	a.destroyed.connect(_on_destroyed)
	a.damaged.connect(_on_damaged.bind(a))


func _on_destroyed(victim: Aircraft, killer: Node) -> void:
	var pl: Aircraft = _player()
	if pl == null or victim == null:
		return
	if victim == pl:
		for w in _wingmen():
			var ld: Array = take("leader_down", pl.team, {"sq": _squadron_name(pl.team)})
			say(callsign_of(w), ld[0], Kind.FRIENDLY, 0.8, ld[1])
			break
		return
	var wm: Array = _wingmen()
	if victim.team == pl.team:
		if victim.has_meta("radio_idx") or wm.has(victim):
			var lc: Array = take("lost_contact", pl.team, {"who": callsign_of(victim)})
			say("Control", "%s, %s" % [callsign_of(pl), lc[0]], Kind.CONTROL, 1.0, lc[1])
		return
	var k: Aircraft = killer as Aircraft
	if k != null and k.player_controlled:
		if not wm.is_empty():
			var kp: Array = take("kill_player", pl.team)
			say(callsign_of(wm[randi() % wm.size()]), kp[0], Kind.FRIENDLY, 0.6, kp[1])
	elif k != null and k.team == pl.team:
		var kf: Array = take("kill_friend", pl.team)
		say(callsign_of(k), kf[0], Kind.FRIENDLY, 0.4, kf[1])


func _on_damaged(_ac: Aircraft, amount: float, health: float, a: Aircraft) -> void:
	var pl: Aircraft = _player()
	if pl == null:
		return
	if a == pl:
		if health < 35.0 and amount > 0.5 and randf() < 0.5 and _cooled("smoke_warn", 25.0):
			for w in _wingmen():
				var sw: Array = take("smoke_warn", pl.team, {"sq": _squadron_name(pl.team)})
				say(callsign_of(w), sw[0], Kind.FRIENDLY, 0.5, sw[1])
				break
		return
	if a.team == pl.team and wm_member(a) and health < 40.0 and randf() < 0.5 and _cooled("hit_" + callsign_of(a), 20.0):
		var ht: Array = take("hit", pl.team)
		say(callsign_of(a), ht[0], Kind.FRIENDLY, 0.0, ht[1])


## True (and starts the cooldown) if this call key has not been made in the last `secs` seconds.
func _cooled(key: String, secs: float) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < float(_cool_until.get(key, -1.0)):
		return false
	_cool_until[key] = now + secs
	return true


## A random index in 0..n-1 that is never the one used last time for this group, so lines do not repeat back to back.
func _pick_index(group: String, n: int) -> int:
	if n <= 1:
		return 0
	var last: int = int(_last_pick.get(group, -1))
	var choices: Array = []
	for k in n:
		if k != last:
			choices.append(k)
	var pick: int = int(choices[randi() % choices.size()])
	_last_pick[group] = pick
	return pick


func wm_member(a: Aircraft) -> bool:
	return _wingmen().has(a)
