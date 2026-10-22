class_name BarrageBalloon
extends GroundTarget
## Silver barrage balloon on a cable. NODE ORIGIN = balloon centre (so weapons hit the balloon); the winch is
## `altitude` below. Place with position.y = ground_y + altitude. Enemy aircraft touching balloon/cable take damage.

var altitude: float = 320.0
var _check_t: float = 0.0
var _sway_t: float = randf() * 10.0
var _balloon: Node3D
var _cable_cd: float = 0.0
const CABLE_R: float = 4.0       # wing reach either side of the wire (world units)
const CABLE_DMG: float = 25.0    # damage a wing strike on the cable does


static func create(p_team: String = "Allies", p_altitude: float = 320.0) -> BarrageBalloon:
	var b := BarrageBalloon.new()
	b.team = p_team
	b.altitude = p_altitude
	b.max_health = 18.0
	b.hit_radius = 22.0
	b.points = 60
	b.kind = "balloon"
	b.display_name = "Barrage balloon"
	b.add_to_group("balloon_cable")   # the HUD draws the cable as a hazard mark on the chart
	b.explosion_size = 1.4
	b.smoke_scale = 1.2
	b.smoke_height = 0.0
	b._check_t = randf() * 0.2
	return b


## Swept wing-strike test: the aircraft moved from `prev` to `cur` this step. True when that path passes within
## `radius` of the vertical cable (winch at `base`, balloon at `top`) and the point of closest approach is below
## the balloon. Swept, so a fast aircraft cannot step over the thin wire between two frames.
static func cable_hit(prev: Vector3, cur: Vector3, base: Vector3, top: Vector3, radius: float) -> bool:
	var a := Vector2(prev.x - base.x, prev.z - base.z)
	var d := Vector2(cur.x - prev.x, cur.z - prev.z)
	var t: float = 0.0
	if d.length_squared() > 0.000001:
		t = clampf(-a.dot(d) / d.length_squared(), 0.0, 1.0)
	var closest: Vector2 = a + d * t
	if closest.length() > radius:
		return false
	var y: float = lerpf(prev.y, cur.y, t)
	return y > base.y and y < top.y


func _build_intact(root: Node3D) -> void:
	# winch truck
	GroundKit.box(root, Vector3(5.0, 2.6, 8.0), Vector3(0, 1.4 - altitude, 0), GroundKit.COL_ALLY_VEH)
	# cable
	GroundKit.cyl(root, 0.12, 0.12, altitude, Vector3(0, -altitude * 0.5, 0), Color(0.15, 0.15, 0.15), Vector3.ZERO, 4, false)
	_balloon = Node3D.new()
	root.add_child(_balloon)
	var silver: Color = Color(0.7, 0.74, 0.78)
	GroundKit.sphere(_balloon, 7.0, Vector3(0, 0, 0), silver, Vector3(1.0, 0.9, 2.2), true)
	for a in [0.0, 120.0, 240.0]:
		GroundKit.box(_balloon, Vector3(0.4, 7.0, 7.0), Vector3(0, 0, 13.0), silver.darkened(0.2), Vector3(0, 0, a), false)
	_balloon.rotation.y = randf() * TAU


func _build_wreck(root: Node3D) -> void:
	GroundKit.box(root, Vector3(5.0, 1.6, 8.0), Vector3(0, 0.8 - altitude, 0), wreck_color, Vector3(0, 12, 4))
	GroundKit.box(root, Vector3(6.0, 0.15, 10.0), Vector3(3, 0.2 - altitude, 2), Color(0.35, 0.36, 0.38), Vector3(0, 40, 0), false)


func _process(delta: float) -> void:
	if is_dead:
		return
	_sway_t += delta
	if _balloon:
		_balloon.rotation.z = sin(_sway_t * 0.6) * 0.05
	_cable_cd -= delta
	_check_cables(delta)
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.15
	var top: Vector3 = global_position
	for a in get_tree().get_nodes_in_group("aircraft"):
		if not GroundKit.aircraft_alive(a):
			continue
		var tm: String = str(a.get("team"))
		if tm == team or tm == "Neutral":
			continue
		var p: Vector3 = (a as Node3D).global_position
		if p.distance_to(top) < 16.0:
			a.call("take_damage", 55.0, self)
			die(a)
			return


## Cable strikes run every frame (the wire is thin and a fast aircraft covers many units per 0.15 s check).
## Enemy aircraft and the player's own aircraft can be hit; friendly AI keep clear of their own wires.
func _check_cables(delta: float) -> void:
	if is_dead or _cable_cd > 0.0:
		return
	var top: Vector3 = global_position
	var base: Vector3 = top - Vector3(0, altitude, 0)
	for a in get_tree().get_nodes_in_group("aircraft"):
		if not GroundKit.aircraft_alive(a):
			continue
		var tm: String = str(a.get("team"))
		if tm == "Neutral" or (tm == team and not bool(a.get("player_controlled"))):
			continue
		var cur: Vector3 = (a as Node3D).global_position
		var prev: Vector3 = cur - (a.get("velocity") as Vector3) * delta
		if cable_hit(prev, cur, base, top, CABLE_R):
			_cable_cd = 0.8
			a.call("take_damage", CABLE_DMG, self)
			return
