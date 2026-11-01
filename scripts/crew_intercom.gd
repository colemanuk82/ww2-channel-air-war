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
var _crew_ui: Control = null        # clickable crew icons (bottom edge)
var _crew_hover: int = -1
var rig: CameraRig = null           # filled lazily from the player's main node
var turrets: DefensiveTurrets = null
var sight: Bombsight = null

const ICON_W: float = 40.0
const ICON_H: float = 46.0
const ICON_GAP: float = 6.0
const CREW_GREEN := Color(0.78, 0.8, 0.8)      # all well: a quiet light grey (amber / red still flag trouble)
const CREW_YELLOW := Color(1.0, 0.78, 0.2)
const CREW_RED := Color(1.0, 0.3, 0.24)
const SLOTS: Array = ["pilot", "nav", "wop", "gun1", "gun2"]
const SHORT_LABEL := {
	"allies": {"pilot": "PILOT", "nav": "BOMB", "wop": "W/OP", "gun1": "GUN 1", "gun2": "GUN 2"},
	"axis": {"pilot": "PILOT", "nav": "OBS", "wop": "RADIO", "gun1": "DORSAL", "gun2": "VENTRAL"},
}


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
	if _crew_ui != null and is_instance_valid(_crew_ui):
		_crew_ui.queue_redraw()
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


## Clickable crew icons down the left edge: pilot, bomb aimer, radio operator, both gunners. Light grey = good,
## amber = wounded or an enemy in range / guns engaging, red = dead. Clicking opens that man's station.
func _build_crew_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CrewStatus"
	layer.layer = 25      # above the bombsight / gunner panels but below the pause and options menus
	add_child(layer)
	_crew_ui = Control.new()
	_crew_ui.name = "CrewIcons"
	# a vertical column down the left edge, centred on the screen's height
	var col_h: float = float(SLOTS.size()) * ICON_H + float(SLOTS.size() - 1) * ICON_GAP
	_crew_ui.anchor_left = 0.0
	_crew_ui.anchor_right = 0.0
	_crew_ui.anchor_top = 0.5
	_crew_ui.anchor_bottom = 0.5
	_crew_ui.offset_left = 10.0
	_crew_ui.offset_right = 10.0 + ICON_W
	_crew_ui.offset_top = -col_h * 0.5
	_crew_ui.offset_bottom = col_h * 0.5
	_crew_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	_crew_ui.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_crew_ui.draw.connect(_draw_crew)
	_crew_ui.gui_input.connect(_crew_input)
	_crew_ui.mouse_exited.connect(func() -> void:
		_crew_hover = -1
		_crew_ui.queue_redraw())
	layer.add_child(_crew_ui)
	_refresh_crew_panel()


func _refresh_crew_panel() -> void:
	if _crew_ui != null and is_instance_valid(_crew_ui):
		_crew_ui.queue_redraw()


func _slot_color(id: String) -> Color:
	if id == "pilot":
		return CREW_YELLOW if not _near.is_empty() else CREW_GREEN
	var st: int = int(crew.get(id, 0))
	if st == KILLED:
		return CREW_RED
	if st == WOUNDED:
		return CREW_YELLOW
	var hot: bool = not _near.is_empty()
	if (id == "gun1" or id == "gun2") and turrets != null and is_instance_valid(turrets) and turrets.engaged:
		hot = true
	return CREW_YELLOW if hot else CREW_GREEN


func _draw_crew() -> void:
	if _crew_ui == null:
		return
	var font: Font = UIKit.font(true)
	var labels: Dictionary = SHORT_LABEL.get(_side, SHORT_LABEL["allies"])
	for i in SLOTS.size():
		var id: String = String(SLOTS[i])
		var y: float = float(i) * (ICON_H + ICON_GAP)
		var hot: bool = _crew_hover == i
		var col: Color = _slot_color(id)
		_crew_ui.draw_rect(Rect2(0.0, y, ICON_W, ICON_H), Color(0.03, 0.035, 0.03, 0.42 if not hot else 0.66))
		_crew_ui.draw_rect(Rect2(0.0, y, ICON_W, ICON_H), Color(col, 0.26 if not hot else 0.8), false, 1.0)
		_draw_bust(_crew_ui, Vector2(ICON_W * 0.5, y + 16.0), col, id)
		var lbl: String = String(labels.get(id, id.to_upper()))
		_crew_ui.draw_string(font, Vector2(2.0, y + ICON_H - 4.0), lbl, HORIZONTAL_ALIGNMENT_CENTER, ICON_W - 4.0, 9, Color(col, 0.95 if hot else 0.72))


## Small pilot bust. The role mark distinguishes the bomb aimer, radio operator and gunners.
func _draw_bust(c: Control, p: Vector2, col: Color, id: String) -> void:
	c.draw_circle(p + Vector2(0, -4), 4.0, col)
	c.draw_colored_polygon(PackedVector2Array([
		p + Vector2(-9, 10), p + Vector2(-7, 1), p + Vector2(-3, -1),
		p + Vector2(3, -1), p + Vector2(7, 1), p + Vector2(9, 10)
	]), col)
	match id:
		"nav":
			c.draw_circle(p + Vector2(0, -4), 8.5, Color(col, 0.55), false, 1.0)
			c.draw_line(p + Vector2(-8, -4), p + Vector2(8, -4), col, 1.0)
			c.draw_line(p + Vector2(0, -12), p + Vector2(0, 4), col, 1.0)
		"wop":
			for rr in [5.0, 9.0]:
				c.draw_arc(p + Vector2(0, -4), rr, -0.8, 0.8, 10, col, 1.0)
		"gun1", "gun2":
			c.draw_line(p + Vector2(-4, 9), p + Vector2(-1, -2), col, 1.4)
			c.draw_line(p + Vector2(4, 9), p + Vector2(1, -2), col, 1.4)


func _crew_input(event: InputEvent) -> void:
	if _crew_ui == null:
		return
	if event is InputEventMouseMotion:
		var i: int = _slot_at(event.position)
		if i != _crew_hover:
			_crew_hover = i
			_crew_ui.queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var i: int = _slot_at(mb.position)
			if i >= 0:
				_open_slot(String(SLOTS[i]))
				_crew_ui.accept_event()


func _slot_at(p: Vector2) -> int:
	if _crew_ui == null or p.x < 0.0 or p.x > ICON_W or p.y < 0.0 or p.y > _crew_ui.size.y:
		return -1
	var i: int = int(p.y / (ICON_H + ICON_GAP))
	if i < 0 or i >= SLOTS.size():
		return -1
	var off: float = p.y - float(i) * (ICON_H + ICON_GAP)
	return i if off <= ICON_H else -1


func _open_slot(id: String) -> void:
	match id:
		"pilot":
			var r: CameraRig = _get_rig()
			if r != null:
				r.set_cockpit(true)
		"nav":
			var s: Bombsight = _get_sight()
			if s != null:
				s.set_active(true)
		"wop":
			var s2: Bombsight = _get_sight()
			if s2 != null:
				s2.set_map(true)
		"gun1":
			_open_gun(0)
		"gun2":
			_open_gun(1)


func _open_gun(which: int) -> void:
	var t: DefensiveTurrets = _get_turrets()
	if t == null:
		return
	var idx: int = -1
	if which == 0:
		idx = t.index_of_name("dorsal")
		if idx < 0:
			idx = t.index_of_name("nose")
		if idx < 0:
			idx = 0
	else:
		idx = t.index_of_name("tail")
		if idx < 0:
			idx = t.index_of_name("ventral")
		if idx < 0:
			idx = maxi(t.turret_count() - 1, 0)
	t.view_turret(idx)


func _get_rig() -> CameraRig:
	if rig == null or not is_instance_valid(rig):
		rig = null
		if ac != null:
			var p: Node = ac.get_parent()
			if p != null:
				rig = p.get_node_or_null("CameraRig") as CameraRig
	return rig


func _get_turrets() -> DefensiveTurrets:
	if turrets == null or not is_instance_valid(turrets):
		turrets = null
		if ac != null:
			turrets = ac.get_node_or_null("DefensiveTurrets") as DefensiveTurrets
	return turrets


func _get_sight() -> Bombsight:
	if sight == null or not is_instance_valid(sight):
		sight = null
		if ac != null:
			var p: Node = ac.get_parent()
			if p != null:
				sight = p.get_node_or_null("Bombsight") as Bombsight
	return sight


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
