class_name CrewIntercom
extends Node
## Bomber crew on the intercom when the player flies a bomber (Lancaster / Heinkel crews; lines in
## assets/voice/voice_story.csv under crew/<allies|axis>/). Watches the flight and speaks at the right moments:
## crew check on the runway, take-off, crossing the enemy coast, fighters spotted (gunners) and the pilot's
## corkscrew, gunner kills, flak and hits, the bomb run (doors open, "left, left, steady", bombs gone, doors closed),
## the coast on the way home and the landing.

var ac: Aircraft
var _side: String = "allies"
var _t: float = 0.0
var _step: float = 0.0
var _said: Dictionary = {}          # one-shot lines already used this sortie
var _cool: Dictionary = {}          # key -> time when it may be said again
var _was_ground: bool = true
var _ground_t: float = 0.0
var _over_enemy: bool = false
var _dropped: bool = false
var _drop_t: float = -1.0
var _run_i: int = 0
var _run_t: float = 0.0
var _near: Dictionary = {}          # enemy aircraft instance id -> node, within gunner range
var _last_shells: int = 0

## Crew stations: nav (navigator / observer), wop (wireless operator / radio operator), gun1 (mid-upper or dorsal
## gunner), gun2 (rear or ventral gunner). Each is 0 healthy, WOUNDED or KILLED; the state shows on the crew panel
## and the intercom says so when it changes. gun_factor() tells the turrets how much of their fire is left.
const STATIONS: Array = ["nav", "wop", "gun1", "gun2"]
const STATION_LABEL := {
	"allies": {"nav": "NAVIGATOR", "wop": "WIRELESS OP", "gun1": "MID-UPPER", "gun2": "REAR GUNNER"},
	"axis": {"nav": "OBSERVER", "wop": "RADIO OP", "gun1": "DORSAL GUNNER", "gun2": "VENTRAL GUNNER"},
}
const WOUNDED: int = 1
const KILLED: int = 2
var crew: Dictionary = {}           # station -> 0 healthy, WOUNDED or KILLED
var _crew_panel: Label = null


static func attach(p_ac: Aircraft) -> CrewIntercom:
	var c := CrewIntercom.new()
	c.name = "CrewIntercom"
	c.ac = p_ac
	c._side = "axis" if p_ac.team == "Axis" else "allies"
	p_ac.add_child(c)
	return c


func _ready() -> void:
	ac.bomb_requested.connect(func(_a: Aircraft) -> void: _on_bomb())
	ac.damaged.connect(func(_a: Aircraft, amount: float, health: float) -> void: _on_hit(amount, health))
	_last_shells = GroundKit.shells_fired
	_was_ground = ac.on_ground
	_init_crew()
	_build_crew_panel()


## New sortie (respawn): every one-shot line is available again, and the crew are all back at their posts.
func reset_sortie() -> void:
	_init_crew()
	_said.clear()
	_cool.clear()
	_dropped = false
	_drop_t = -1.0
	_run_i = 0
	_over_enemy = false
	_ground_t = 0.0
	_was_ground = ac.on_ground if ac != null else true


func _say(key: String, delay: float = 0.0) -> void:
	Radio.story("crew/%s/%s" % [_side, key], delay, true)


func _once(key: String, delay: float = 0.0) -> bool:
	if _said.has(key):
		return false
	_said[key] = true
	_say(key, delay)
	return true


func _ready_for(key: String, cooldown: float) -> bool:
	if _t < float(_cool.get(key, -1.0)):
		return false
	_cool[key] = _t + cooldown
	return true


func _process(delta: float) -> void:
	if ac == null or not is_instance_valid(ac) or ac.state != Aircraft.State.ALIVE:
		return
	_t += delta
	_step -= delta
	if _step > 0.0:
		return
	_step = 0.5
	var pos: Vector3 = ac.global_position
	# runway: crew check, then the take-off roll
	if ac.on_ground:
		_ground_t += 0.5
		if _ground_t > 3.0 and not _said.has("check"):
			_said["check"] = true
			for i in 5:
				_say("check_%d" % (i + 1), 0.2 * float(i))
		if ac.speed > ac.stats.stall_speed * 0.6:
			_once("takeoff_1")
	elif _was_ground:
		_once("takeoff_2", 2.0)
	if ac.on_ground and not _was_ground and _said.has("takeoff_2") and ac.speed < 25.0:
		_once("landed", 1.0)
	_was_ground = ac.on_ground
	if ac.on_ground:
		return
	# coasts
	var own: String = ac.team
	var here: String = GroundKit.side_at(pos)
	var enemy_land: bool = here != own and here != "Neutral" and not GroundKit.is_water(pos.x, pos.z)
	if enemy_land and not _over_enemy:
		_once("coast_out")
	if _over_enemy and here == own and not GroundKit.is_water(pos.x, pos.z) and _dropped:
		_once("coast_home")
	if enemy_land:
		_over_enemy = true
	elif here == own and not GroundKit.is_water(pos.x, pos.z):
		_over_enemy = false
	# flak bursting around us over enemy ground
	if enemy_land and GroundKit.shells_fired > _last_shells + 3 and _ready_for("flak", 60.0):
		_say("flak")
	_last_shells = GroundKit.shells_fired
	# fighters: gunners call them, the pilot sometimes corkscrews; a fighter going down close by is a gunner kill
	var spotted: Aircraft = null
	var still: Dictionary = {}
	for n in get_tree().get_nodes_in_group("aircraft"):
		var o: Aircraft = n as Aircraft
		if o == null or o.team == own or o.team == "Neutral" or o.is_in_group("bomber"):
			continue
		var d: float = o.global_position.distance_to(pos)
		if d < 2400.0 and o.state == Aircraft.State.ALIVE:
			still[o.get_instance_id()] = o
			if spotted == null or d < spotted.global_position.distance_to(pos):
				spotted = o
	for id in _near:
		var was = _near[id]
		if not still.has(id) and is_instance_valid(was) and (was as Aircraft).state != Aircraft.State.ALIVE:
			if _ready_for("kill", 15.0):
				_say("gunner_kill_%d" % randi_range(1, 2))
	_near = still
	if spotted != null and _ready_for("fighter", 28.0):
		_say("fighter_%d" % randi_range(1, 4))
		if randf() < 0.6:
			_say("corkscrew_%d" % randi_range(1, 2))
	# bomb run: doors open when the bombs are selected over the target area, directions until the drop
	var bombs_ready: bool = ac.weapon_mode == 2 and ac.bombs > 0 and not _dropped
	if bombs_ready and _over_enemy:
		if _once("doors_open"):
			_run_t = _t + 4.0
		elif _run_i < 3 and _t >= _run_t:
			_run_i += 1
			_say("run_%d" % _run_i)
			_run_t = _t + 4.5
	if _drop_t > 0.0 and _t > _drop_t + 4.0:
		_once("doors_closed")
		_once("after_drop", 1.5)


func _on_bomb() -> void:
	if ac.weapon_mode != 2:
		return
	if not _said.has("bombs_gone"):
		_said["bombs_gone"] = true
		_say("bombs_gone")
		_dropped = true
		_drop_t = _t


func _on_hit(amount: float, health: float) -> void:
	_crew_hit(amount)
	if amount < 2.0 or not _ready_for("hit", 20.0):
		return
	if health < ac.stats.max_health * 0.5 and not _said.has("hit_2"):
		_said["hit_2"] = true
		_say("hit_2")
	else:
		_say("hit_%d" % (1 if randf() < 0.6 else 3))


## Every station starts at its post, healthy.
func _init_crew() -> void:
	for s in STATIONS:
		crew[s] = 0
	_refresh_crew_panel()


## Crew panel, bottom left: one line per station, red when a man is dead, amber when one is wounded.
func _build_crew_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CrewStatus"
	layer.layer = 5
	add_child(layer)
	_crew_panel = Label.new()
	_crew_panel.name = "CrewPanel"
	_crew_panel.add_theme_font_size_override("font_size", 16)
	_crew_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	layer.add_child(_crew_panel)
	_refresh_crew_panel()


func _refresh_crew_panel() -> void:
	if _crew_panel == null:
		return
	var labels: Dictionary = STATION_LABEL.get(_side, STATION_LABEL["allies"])
	var lines: PackedStringArray = PackedStringArray(["CREW"])
	var worst: int = 0
	for s in STATIONS:
		var st: int = int(crew.get(s, 0))
		worst = maxi(worst, st)
		var word: String = "OK" if st == 0 else ("WOUNDED" if st == WOUNDED else "KILLED")
		lines.append(String(labels[s]).rpad(15) + word)
	_crew_panel.text = "\n".join(lines)
	var col: Color = Color(0.85, 0.95, 0.85)
	if worst == WOUNDED:
		col = Color(1.0, 0.75, 0.2)
	elif worst == KILLED:
		col = Color(1.0, 0.3, 0.25)
	_crew_panel.add_theme_color_override("font_color", col)
	_crew_panel.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_crew_panel.add_theme_constant_override("shadow_offset_x", 1)
	_crew_panel.add_theme_constant_override("shadow_offset_y", 1)


## A hit on the aircraft can cost a crew member. Small hits rarely do; heavy hits hurt more. A wounded man can be
## killed by a later hit, and a healthy man can be killed outright by a heavy one. The skipper or commander then
## reports it on the intercom (the casualty's own line when he is only wounded).
func _crew_hit(amount: float) -> void:
	if amount < 2.0:
		return
	var alive: Array = []
	for s in STATIONS:
		if int(crew.get(s, 0)) < KILLED:
			alive.append(s)
	if alive.is_empty() or randf() > clampf(amount / 60.0, 0.03, 0.2):
		return
	var who: String = alive[randi() % alive.size()]
	var st: int = int(crew.get(who, 0))
	if st == 0:
		if amount >= 10.0 and randf() < 0.15:
			_crew_set(who, KILLED)
		else:
			_crew_set(who, WOUNDED)
	elif randf() < 0.5:
		_crew_set(who, KILLED)


func _crew_set(s: String, st: int) -> void:
	crew[s] = st
	_say("%s_%s" % [s, "wounded" if st == WOUNDED else "killed"], 0.4)
	_refresh_crew_panel()


## Share of a defensive gun's fire the crew can still deliver: all of it, half when the gunner is wounded, none when
## he is dead. mount is the turret's mount name from defensive_turrets.gd (dorsal, tail, ventral, nose, waist_*).
func gun_factor(mount: String) -> float:
	var s: String = ""
	if mount == "dorsal":
		s = "gun1"
	elif mount == "tail" or mount == "ventral":
		s = "gun2"
	else:
		return 1.0
	var st: int = int(crew.get(s, 0))
	if st == KILLED:
		return 0.0
	if st == WOUNDED:
		return 0.5
	return 1.0
