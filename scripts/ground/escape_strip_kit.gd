class_name EscapeStripKit
extends RefCounted
## Rough landing strips in the farmland near Axis prisoner-of-war camps, for the POW escape missions
## (scripts/modes/pow_escape_mode.gd). A strip is what the resistance and the escape lines used for a night
## pick-up: a long, level pasture or stubble field with the hedges grubbed out, rolled flat, 600-700 m of it,
## nothing marking it by day but a field that is a shade paler where it was rolled. By night a reception
## committee lays three torches in an L (the pick-up flare path; the mission adds the lights).
##
## Each strip sits 1.3-2 km from its camp, on the flattest ground the height data offers, aligned with the
## flattest axis. Positions are worked out when the camps are registered (WorldPopulator._register_pow_camps).
## The strips are static scenery and never targets.

const LENGTH := 640.0
const WIDTH := 44.0
const KEEP_CLEAR := 430.0       # scatter, roads and rails stay this far from the centre

## [strip id, camp id (PowCampKit.CAMPS), name]
const STRIPS := [
	["strip_chalons", "frontstalag_194", "Field strip east of Chalons-sur-Marne"],
	["strip_charleville", "frontstalag_190", "Field strip west of Charleville"],
	["strip_trier", "stalag_12d", "Field strip north of Trier"],
]

## strip id -> {"pos": Vector3 (ground level), "heading": degrees, "camp": Vector3, "camp_id": String, "name": String}
static var placed: Dictionary = {}


static func strip_for_camp(camp_id: String) -> String:
	for s in STRIPS:
		if str(s[1]) == camp_id:
			return str(s[0])
	return ""


## Choose the flattest spot and axis 1.3-2 km from the camp. Deterministic for a given terrain.
static func plan(camp_pos: Vector3) -> Dictionary:
	var best_pos: Vector3 = camp_pos + Vector3(1600.0, 0.0, 0.0)
	var best_h: float = 90.0
	var best_s: float = INF
	for bi in 8:
		var bearing: float = float(bi) * 45.0
		var dir: Vector3 = WorldCoords.heading_to_dir(bearing)
		for dist in [1400.0, 1800.0]:
			var c: Vector3 = camp_pos + dir * float(dist)
			for hi in 12:
				var h: float = float(hi) * 15.0
				var a: Vector3 = WorldCoords.heading_to_dir(h)
				var side: Vector3 = Vector3(-a.z, 0.0, a.x)
				var lo: float = INF
				var hi_y: float = -INF
				var wet: bool = false
				for u in [-1.0, -0.5, 0.0, 0.5, 1.0]:
					for v in [-1.0, 0.0, 1.0]:
						var p: Vector3 = c + a * (float(u) * LENGTH * 0.55) + side * (float(v) * 50.0)
						var y: float = GroundKit.raw_y(p.x, p.z)
						lo = minf(lo, y)
						hi_y = maxf(hi_y, y)
						wet = wet or y < 2.0
				if wet:
					continue
				var score: float = (hi_y - lo) + float(dist) * 0.002
				if score < best_s:
					best_s = score
					best_pos = c
					best_h = h
	return {"pos": best_pos, "heading": best_h}


## The strip's scenery: a rolled strip a shade paler than the field round it, and a hedge-gap marker at each end.
static func build(pos: Vector3, heading: float) -> Node3D:
	var root := Node3D.new()
	root.name = "EscapeStrip"
	root.position = Vector3(pos.x, pos.y, pos.z)
	root.rotation.y = -deg_to_rad(heading)
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(WIDTH, 0.10, LENGTH)
	strip.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.43, 0.46, 0.27)
	m.roughness = 1.0
	strip.material_override = m
	strip.position = Vector3(0.0, 0.07, 0.0)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(strip)
	# wheel ruts where earlier aircraft landed: two darker lines down the strip
	var rut_m := StandardMaterial3D.new()
	rut_m.albedo_color = Color(0.33, 0.34, 0.20)
	rut_m.roughness = 1.0
	for sx in [-4.0, 4.0]:
		var rut := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.8, 0.11, LENGTH * 0.9)
		rut.mesh = rm
		rut.material_override = rut_m
		rut.position = Vector3(float(sx), 0.075, 0.0)
		rut.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rut)
	return root


## World position of the end of the strip an aircraft should touch down at, and the landing direction.
## `approach_from` is where the pilot comes from: the end nearest to it is the threshold, the far end the roll-out.
static func landing_end(id: String, approach_from: Vector3) -> Dictionary:
	var d: Dictionary = placed.get(id, {})
	if d.is_empty():
		return {}
	var pos: Vector3 = d["pos"]
	var dir: Vector3 = WorldCoords.heading_to_dir(float(d["heading"]))
	var e1: Vector3 = pos - dir * (LENGTH * 0.5 - 40.0)
	var e2: Vector3 = pos + dir * (LENGTH * 0.5 - 40.0)
	if approach_from.distance_to(e1) <= approach_from.distance_to(e2):
		return {"threshold": e1, "dir": dir, "far": e2}
	return {"threshold": e2, "dir": -dir, "far": e1}
