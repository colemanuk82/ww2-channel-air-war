class_name Convoy
extends Node3D
## A group of vehicles (road) or ships (sea) moving along one RoutePath. Add under a node at the world origin.
## Mission-target aware: set target_id + is_mission_target; emits `destroyed` once kill_fraction of the units
## are dead. Signals: unit_destroyed(unit, killer).

signal unit_destroyed(unit: Node, killer: Node)
signal destroyed(node: Node, killer: Node)

var target_id: String = ""
var display_name: String = "Convoy"
var team: String = "Axis"
var is_mission_target: bool = false
var kill_fraction: float = 0.6
var units: Array = []
var dead_count: int = 0
var is_dead: bool = false
var route: RoutePath
var naval: bool = false
var composition: String = "mixed"
var start_s: float = 0.0
var spacing: float = 26.0
var speed: float = 10.0
var wrap: bool = true
var columns: int = 1               # naval: sail in this many parallel columns
var column_gap: float = 110.0
var _built: bool = false


static func create(p_team: String, p_route: RoutePath, p_naval: bool, p_comp: String, p_start_s: float = 0.0, p_speed: float = -1.0) -> Convoy:
	var c := Convoy.new()
	c.team = p_team
	c.route = p_route
	c.naval = p_naval
	c.composition = p_comp
	c.start_s = p_start_s
	c.speed = p_speed if p_speed > 0.0 else (10.0 if not p_naval else 9.0)
	c.spacing = 80.0 if p_naval else 24.0
	if p_naval and p_comp == "neptune":
		# assault waves: landing craft line abreast, row after row, escorts screening the flanks
		c.columns = 5
		c.spacing = 120.0
		c.column_gap = 70.0
	if p_naval and p_comp in ["channel", "kriegsmarine"]:
		c.columns = 2
		c.spacing = 240.0
		c.column_gap = 180.0
	return c


static func land_composition(comp: String, team_name: String) -> Array:
	var tank: String = "panzer4" if team_name == "Axis" else "sherman"
	var arr: Array = _land_comp(comp, tank)
	if team_name == "Axis":
		for i in arr.size():
			if arr[i] == "jeep":
				arr[i] = "kubel"        # Germans did not use the US jeep
	return arr


static func _land_comp(comp: String, tank: String) -> Array:
	match comp:
		"civil":
			return ["car", "car", "truck", "car", "bus", "car", "car"]
		"civil_light":
			return ["car", "car", "car"]
		"tanks":
			return [tank, "halftrack", tank, tank, "halftrack", tank]
		"troops":
			return ["jeep", "troops", "troops", "truck", "troops", "truck"]
		"supply":
			return ["jeep", "truck", "truck", "truck", "truck", "truck", "halftrack", "truck"]
		_:
			return ["jeep", "truck", "truck", tank, "truck", "halftrack", "truck", "artillery", "truck"]


static func sea_composition(comp: String) -> Array:
	match comp:
		"neptune":
			return ["destroyer", "landing_craft", "landing_craft", "landing_craft", "landing_craft", "landing_craft",
				"destroyer", "landing_craft", "landing_craft", "landing_craft", "landing_craft", "landing_craft",
				"freighter", "landing_craft", "landing_craft", "landing_craft", "landing_craft", "landing_craft",
				"freighter", "landing_craft", "landing_craft", "landing_craft", "landing_craft", "landing_craft"]
		"dunkirk":
			return ["destroyer", "fishing_boat", "fishing_boat", "freighter", "fishing_boat", "landing_craft", "fishing_boat", "freighter"]
		"coastal":
			return ["freighter", "fishing_boat", "freighter", "fishing_boat"]
		"fishing":
			return ["fishing_boat", "fishing_boat", "fishing_boat", "fishing_boat", "fishing_boat"]
		"coaster":
			return ["freighter", "freighter", "fishing_boat"]
		"channel":
			# 1940 CW/CE Channel convoy: colliers and coasters in two columns, destroyer + armed trawlers
			return ["destroyer", "trawler", "collier", "collier", "freighter", "collier", "collier", "freighter", "collier", "collier", "freighter", "collier", "trawler", "trawler"]
		"kriegsmarine":
			# German coastal convoy: escort trawlers (Vorpostenboote) round a few merchants
			return ["trawler", "freighter", "collier", "freighter", "trawler", "collier", "trawler"]
		_:
			return ["destroyer", "freighter", "freighter", "freighter", "destroyer"]


func _ready() -> void:
	if is_mission_target:
		add_to_group("mission_target")
	add_to_group("convoy")
	_build()


const ESCORTS := ["destroyer", "cruiser", "battleship", "trawler"]
const SMALL_CRAFT := ["fishing_boat", "landing_craft", "trawler"]


func _build() -> void:
	if _built or route == null or route.length < 2.0:
		return
	_built = true
	var list: Array = sea_composition(composition) if naval else land_composition(composition, team)
	var stations: Array = _naval_stations(list) if naval else []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(target_id + composition + str(int(start_s)))
	for i in list.size():
		var t: String = list[i]
		var u: GroundTarget
		var sp: float = speed
		var s0: float = start_s - float(i) * spacing
		var lat: float = 0.0
		if naval:
			s0 = start_s + float(stations[i].y)
			lat = float(stations[i].x)
		if route.length > 0.0:
			s0 = fposmod(s0, route.length)
		if naval:
			var sh: GroundShip = GroundShip.create(t, team, route, s0, sp)
			sh.wrap = wrap
			sh.lateral = lat
			sh.wander = 14.0 if t in SMALL_CRAFT else 22.0      # ships never hold station exactly
			sh.wander_phase = rng.randf() * TAU
			if team == "Allies" and composition == "channel" and t == "collier" and i % 3 == 0:
				sh.balloon_alt = 180.0
			u = sh
		else:
			var gv: GroundVehicle = GroundVehicle.create(t, team, route, s0, sp, "move")
			gv.wrap = wrap
			u = gv
		u.set_meta("convoy_id", target_id)
		u.destroyed.connect(_on_unit_destroyed)
		add_child(u)
		units.append(u)


## Where each ship of a naval convoy sails: Vector2(lateral, along) in metres from the head of the convoy (+ lateral =
## starboard, + along = ahead). Modelled on the real practice, compressed so the convoy reads from the air: the merchants
## in two or three columns (more for an invasion fleet) with alternate columns staggered half a station, the leading
## escort ahead, the others screening the flanks along the length of the convoy, and the armed trawlers astern. Small
## craft keep closer together than merchantmen. A little irregularity so no two convoys look drawn with a ruler.
func _naval_stations(list: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(composition + target_id) + list.size()
	var merchants: Array = []
	var escorts: Array = []
	for i in list.size():
		if str(list[i]) in ESCORTS and not (composition == "fishing"):
			escorts.append(i)
		else:
			merchants.append(i)
	var small: int = 0
	for i2 in merchants:
		if str(list[i2]) in SMALL_CRAFT:
			small += 1
	var small_fleet: bool = small * 2 >= maxi(merchants.size(), 1)
	var station: float = 150.0 if small_fleet else 260.0          # fore and aft between ships in a column
	var gap: float = 170.0 if small_fleet else 300.0              # between columns
	var cols: int = columns if columns > 1 else (1 if merchants.size() <= 2 else (2 if merchants.size() <= 6 else 3))
	if composition == "neptune":
		station = 170.0
		gap = 150.0
	var out: Array = []
	out.resize(list.size())
	var rows: int = int(ceil(float(merchants.size()) / float(cols)))
	for k in merchants.size():
		var col: int = k % cols
		var row: int = k / cols
		var lat: float = (float(col) - float(cols - 1) * 0.5) * gap + rng.randf_range(-0.1, 0.1) * gap
		var along: float = -(float(row) * station + (station * 0.5 if col % 2 == 1 else 0.0)) + rng.randf_range(-0.12, 0.12) * station
		out[merchants[k]] = Vector2(lat, along)
	var length: float = float(maxi(rows - 1, 0)) * station + station * 0.5
	var half_w: float = float(cols - 1) * 0.5 * gap
	var flank: float = half_w + gap * 0.9 + 60.0
	var side: float = 1.0
	var placed_lead: bool = false
	var e_n: int = escorts.size()
	for e in e_n:
		var idx: int = escorts[e]
		var typ: String = str(list[idx])
		if not placed_lead and typ != "trawler":
			# the senior escort leads, a little to one side of the centre line
			out[idx] = Vector2(rng.randf_range(-0.25, 0.25) * gap, station * 1.3)
			placed_lead = true
			continue
		if typ == "trawler" and e == e_n - 1 and e_n > 2:
			out[idx] = Vector2(rng.randf_range(-0.3, 0.3) * gap, -length - station * 1.1)    # tail-end Charlie
			continue
		var frac: float = float(e) / float(maxi(e_n - 1, 1))
		out[idx] = Vector2(side * (flank + rng.randf_range(-30.0, 30.0)), lerpf(station * 0.4, -length, frac) + rng.randf_range(-40.0, 40.0))
		side = -side
	if merchants.is_empty() and not escorts.is_empty():
		out[escorts[0]] = Vector2.ZERO
	return out


func _on_unit_destroyed(unit: Node, killer: Node) -> void:
	dead_count += 1
	unit_destroyed.emit(unit, killer)
	if not is_dead and float(dead_count) >= ceilf(float(units.size()) * kill_fraction):
		is_dead = true
		remove_from_group("mission_target")
		add_to_group("destroyed_target")
		destroyed.emit(self, killer)


func is_destroyed() -> bool:
	return is_dead


func alive_count() -> int:
	return units.size() - dead_count


## Centre of the surviving units (for objective markers).
func get_center() -> Vector3:
	var c := Vector3.ZERO
	var n: int = 0
	for u in units:
		if is_instance_valid(u) and not (u as GroundTarget).is_dead:
			c += (u as Node3D).global_position
			n += 1
	if n == 0:
		return global_position
	return c / float(n)
