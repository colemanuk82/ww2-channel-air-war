extends Node
## Headless check of the airfield dressing that must stay off the runways and taxi routes (no terrain, no world):
##   godot --headless --path . tools/dbg/dress_check.tscn -- [--styles=a,b] [--out=build/dbg/dress]
## For each style it builds one Airfield, parks aircraft (ParkedAircraft.place), lays the P8 furniture, then runs
## AirfieldActivity.populate (service vehicles) and plans the AirfieldStores stacks. It asserts that
##   * no service-vehicle loop has a leg across (or within 2 m of) a runway,
##   * no crate / drum stack is near a runway, pavement, a taxi-out route, a reserved pad or a parked aircraft,
## writes <out>_<style>.json (local frame: runways, paved, routes, vehicle paths, stacks, parked) for
## tools/dbg/dress_svg.py, and prints near / far triangle counts of every parked type. Prints DRESS OK or DRESS FAIL.

const STYLES := ["triangle", "raf_bomber", "raf_fighter", "night_fighter", "grass", "raf_grass", "cross", "parallel",
	"forward", "lw_fliegerhorst", "lw_field", "raf_satellite", "usaf_alg", "glider_strip"]

var _fails: int = 0


class DbgTerrain:
	extends Node
	func get_terrain_y(_x: float, _z: float) -> float:
		return 0.0
	func get_height_at(_pos: Vector3) -> float:
		return 0.0
	func is_water_at(_pos: Vector3) -> bool:
		return false


func _ready() -> void:
	var a: Dictionary = {}
	for s in OS.get_cmdline_user_args():
		var kv: PackedStringArray = String(s).trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var t := DbgTerrain.new()
	add_child(t)
	t.add_to_group("terrain")
	var styles: Array = STYLES if not a.has("styles") else Array(String(a["styles"]).split(","))
	var out: String = String(a.get("out", "build/dbg/dress"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out.get_base_dir()))
	for st in styles:
		_check_style(String(st), out)
	if not a.has("no-tris"):
		_tris()
	print("DRESS OK" if _fails == 0 else "DRESS FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)


func _check_style(style: String, out: String) -> void:
	var container := Node3D.new()
	add_child(container)
	var af: Airfield = Airfield.create("Dress " + style, Vector3.ZERO, 70.0, 0.0)
	af.style = style
	container.add_child(af)
	af.build_layout()
	af.team = "Allies" if not style.begins_with("lw") else "Axis"
	var axf := Transform3D(Basis(Vector3.UP, af.rotation.y), af.position)
	var inv: Transform3D = axf.affine_inverse()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(style)
	var xf: Array = []
	for pad in af.dispersal_world_points():
		if rng.randf() < 0.3:
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(pad.x, 0.4, pad.z)))
	ParkedAircraft.place(container, xf, af.team, af)
	if style not in ["raf_grass", "lw_field", "raf_satellite", "glider_strip"]:
		AirfieldFurniture.dress(container, af, axf, 0.0, af.team, rng)
	AirfieldActivity.populate(container, af, axf, 0.0, af.team, rng)
	var rws: Array = AirfieldActivity.runways(af)
	# vehicles
	var vpaths: Array = []
	for v in container.find_children("*", "GroundVehicle", true, false):
		var gv: GroundVehicle = v
		if gv.route == null:
			var lp0: Vector3 = inv * gv.position
			if not AirfieldActivity.leg_clear(rws, lp0, lp0, 2.0):
				_fail("%s: idle %s stands on a runway at %s" % [style, gv.vtype, str(lp0)])
			continue
		var pts: PackedVector3Array = gv.route.points
		var row: Array = []
		for i in pts.size():
			var lp: Vector3 = inv * pts[i]
			row.append([snappedf(lp.x, 0.1), snappedf(lp.z, 0.1)])
			if i > 0:
				var lq: Vector3 = inv * pts[i - 1]
				if not AirfieldActivity.leg_clear(rws, Vector3(lq.x, 0, lq.z), Vector3(lp.x, 0, lp.z), 2.0):
					_fail("%s: %s leg %d crosses a runway" % [style, gv.vtype, i])
		vpaths.append([gv.vtype, row])
	# stacks
	var stores: AirfieldStores = container.get_node_or_null("AirfieldStores")
	var stacks: Array = []
	if stores == null:
		_fail("%s: no AirfieldStores node" % style)
	else:
		stores.plan()
		var pl: Array = stores.planned()
		for k in 2:
			for tt in pl[k]:
				var w: Vector3 = (tt as Transform3D).origin
				var lp2: Vector3 = inv * w
				lp2.y = 0.0
				stacks.append(["crates" if k == 0 else "drums", snappedf(lp2.x, 0.1), snappedf(lp2.z, 0.1)])
				if not AirfieldActivity.leg_clear(rws, lp2, lp2, 20.0):
					_fail("%s: stack near a runway at %s" % [style, str(lp2)])
				if af.near_paved(w, 6.0):
					_fail("%s: stack on pavement at %s" % [style, str(lp2)])
				for rt in AirfieldStores.flight_routes(af):
					var pr: PackedVector3Array = rt
					for i in range(1, pr.size()):
						var c: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(lp2.x, lp2.z), Vector2(pr[i - 1].x, pr[i - 1].z), Vector2(pr[i].x, pr[i].z))
						if c.distance_to(Vector2(lp2.x, lp2.z)) < 12.0:
							_fail("%s: stack on a taxi route at %s" % [style, str(lp2)])
				for ps in af.parked_spots:
					if Vector2((ps as Vector3).x - w.x, (ps as Vector3).z - w.z).length() < 12.0:
						_fail("%s: stack on a parked aircraft at %s" % [style, str(lp2)])
	print("%-16s runways %d  vehicles %d  stacks %d (crates %d, drums %d)  parked %d" % [style, rws.size(), vpaths.size(), stacks.size(),
		stacks.filter(func(s: Array) -> bool: return s[0] == "crates").size(), stacks.filter(func(s: Array) -> bool: return s[0] == "drums").size(), af.parked_spots.size()])
	var j: Dictionary = {
		"style": style,
		"runways": rws.map(func(r: Array) -> Array: return [snappedf((r[0] as Vector3).x, 0.1), snappedf((r[0] as Vector3).z, 0.1), snappedf((r[1] as Vector3).x, 0.1), snappedf((r[1] as Vector3).z, 0.1), r[2]]),
		"paved": af._paved.map(func(r: Array) -> Array: return [snappedf((r[0] as Vector3).x, 0.1), snappedf((r[0] as Vector3).z, 0.1), snappedf((r[1] as Vector3).x, 0.1), snappedf((r[1] as Vector3).z, 0.1), r[2]]),
		"routes": AirfieldStores.flight_routes(af).map(func(r: PackedVector3Array) -> Array: return Array(r).map(func(p: Vector3) -> Array: return [snappedf(p.x, 0.1), snappedf(p.z, 0.1)])),
		"vehicles": vpaths,
		"stacks": stacks,
		"parked": af.parked_spots.map(func(p: Vector3) -> Array: return [snappedf((inv * p).x, 0.1), snappedf((inv * p).z, 0.1)]),
		"flight_pads": AirfieldStores.flight_pads(af).map(func(i: int) -> Array: return [snappedf((af._dispersal_local[i] as Vector3).x, 0.1), snappedf((af._dispersal_local[i] as Vector3).z, 0.1)]),
	}
	var f := FileAccess.open("res://%s_%s.json" % [out, style], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(j))
	container.free()


func _tris() -> void:
	for id in ["spitfire", "hurricane", "typhoon", "tempest", "mosquito", "p47", "p51", "p38", "blenheim", "lancaster", "b26", "b25", "a20", "c47",
			"bf109", "fw190", "bf110", "ju87", "he111", "ju88", "do17", "ju52", "fw200"]:
		var near: ArrayMesh = ParkedAircraft.mesh_for(id)
		var far: ArrayMesh = ParkedAircraft.far_mesh_for(id)
		if near == null or far == null:
			_fail("parked %s: no mesh" % id)
			continue
		var nt: int = _count(near)
		var ft: int = _count(far)
		var lods: int = 0
		for si in near.get_surface_count():
			lods = maxi(lods, near.surface_get_lod_count(si) if near.has_method("surface_get_lod_count") else 0)
		var nb: AABB = near.get_aabb()
		var fb: AABB = far.get_aabb()
		print("parked %-10s near %6d tris (%d LODs)  far %4d tris  near box %s  far box %s" % [id, nt, lods, ft, str(nb.size.snapped(Vector3.ONE * 0.1)), str(fb.size.snapped(Vector3.ONE * 0.1))])
		if ft > 600:
			_fail("parked %s: far stand-in has %d tris" % [id, ft])
		if absf(fb.size.x - nb.size.x) > nb.size.x * 0.1 or fb.position.y < -0.05:
			_fail("parked %s: far stand-in does not fit the model (%s vs %s)" % [id, str(fb), str(nb)])


func _count(m: ArrayMesh) -> int:
	var n: int = 0
	for si in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(si)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n
