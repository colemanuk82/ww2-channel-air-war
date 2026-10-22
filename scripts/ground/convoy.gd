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


func _build() -> void:
	if _built or route == null or route.length < 2.0:
		return
	_built = true
	var list: Array = sea_composition(composition) if naval else land_composition(composition, team)
	var off: float = start_s
	var ni: int = 0     # index among non-escort ships (for column / row placement)
	for i in list.size():
		var t: String = list[i]
		var u: GroundTarget
		var sp: float = speed
		var s0: float = off - float(i) * spacing
		var lat: float = 0.0
		if naval and columns > 1:
			if t in ["destroyer", "trawler"]:
				# escorts screen the flanks of the columns, staggered fore and aft
				var flank: float = maxf(1.6, float(columns) * 0.5 + 0.7)
				lat = column_gap * (flank if i % 2 == 0 else -flank)
				s0 = off - float(ni / columns) * spacing - (spacing * 0.5 if columns > 2 else float(i) * spacing * 0.5)
			else:
				lat = column_gap * (float(ni % columns) - float(columns - 1) * 0.5)
				if columns > 2:
					lat += sin(float(ni) * 2.7) * column_gap * 0.12     # loose, slightly ragged line
				s0 = off - float(ni / columns) * spacing
				ni += 1
		if route.length > 0.0:
			s0 = fposmod(s0, route.length)
		if naval:
			var sh: GroundShip = GroundShip.create(t, team, route, s0, sp)
			sh.wrap = wrap
			sh.lateral = lat
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
