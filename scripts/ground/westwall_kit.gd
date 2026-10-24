class_name WestwallKit
extends RefCounted
## The Westwall (Siegfried Line) "dragon's teeth" (Hoeckerlinie) south of Aachen: four or five staggered rows of
## reinforced-concrete pyramids on a concrete foundation, rising from about 0.9 m in the front row to 1.5 m at the back,
## running for miles through fields and woods - from the air a pale zig-zag line across the country. Built 1938-40,
## fought through in September-October 1944, and much of it still stands, so it is there at every date.
##
## Sources: Wikipedia - Siegfried Line; Dragon's teeth (fortification); Battle of Aachen; Battle of Huertgen Forest
## (the Scharnhorst line from Monschau / Kalterherberg north by Roetgen, Schmidthof and Brand towards Verlautenheide).
##
## Cost: the line is cut into ~5 km streamed sites. Near: one MultiMesh of 20 m teeth sections (55 frustums merged,
## ~900 triangles each), 2.8 km fade. Far: one MultiMesh of pale strips (the cleared foundation) to 12 km.

const SECTION := 20.0

## The line as lat/lon vertices (north-east bound).
const LINES := {
	"scharnhorst": [[50.5200, 6.2150], [50.5450, 6.2300], [50.5600, 6.2420], [50.5980, 6.2150], [50.6250, 6.2050],
		[50.6480, 6.1970], [50.6700, 6.1880], [50.6900, 6.1800], [50.7120, 6.1780], [50.7300, 6.1700], [50.7450, 6.1650],
		[50.7650, 6.1700], [50.7880, 6.1800]],
}


## Chunks of ~5 km: [line id, first vertex, last vertex, centre].
static func chunks() -> Array:
	var out: Array = []
	for lid in LINES.keys():
		var pts: Array = LINES[lid]
		var i0: int = 0
		var acc: float = 0.0
		for i in range(1, pts.size()):
			acc += _w(pts[i - 1]).distance_to(_w(pts[i]))
			if acc > 5000.0 or i == pts.size() - 1:
				out.append([lid, i0, i, (_w(pts[i0]) + _w(pts[i])) * 0.5])
				i0 = i
				acc = 0.0
	return out


static func _w(ll: Array) -> Vector3:
	return WorldCoords.latlon_to_world(float(ll[0]), float(ll[1]))


static func build(lid: String, i0: int, i1: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Westwall_%s_%d" % [lid, i0]
	var pts: Array = LINES[lid]
	var near: Array = []
	var strips: Array = []
	for i in range(i0, i1):
		var a: Vector3 = _w(pts[i])
		var b: Vector3 = _w(pts[i + 1])
		var L: float = a.distance_to(b)
		var d: Vector3 = (b - a) / L
		var yaw: float = atan2(-d.z, d.x)
		var t: float = SECTION * 0.5
		while t < L:
			var p: Vector3 = a + d * t
			if GroundKit.raw_y(p.x, p.z) > 1.0:
				p.y = GroundKit.ground_y(p.x, p.z) - 0.1
				near.append(Transform3D(Basis(Vector3.UP, yaw), p))
			t += SECTION
		strips.append_array(CampAssets.track_xforms(Transform3D.IDENTITY, a, b, 11.0))
	if not near.is_empty():
		root.add_child(Scatter.multi(teeth_mesh(), near, 2800.0))
	if not strips.is_empty():
		root.add_child(Scatter.multi(Scatter.box_unit(Color(0.62, 0.61, 0.56)), strips, 12000.0))
	return root


## 20 m of teeth along X: five staggered rows of square concrete frustums on a foundation slab.
static func teeth_mesh() -> ArrayMesh:
	if Scatter._meshes.has("dragons_teeth"):
		return Scatter._meshes["dragons_teeth"]
	var conc := Color(0.66, 0.65, 0.60)
	var parts: Array = []
	parts.append(GroundKit.box_part(Vector3(SECTION, 0.35, 9.4), Vector3(0, 0.12, 0), conc.darkened(0.08), Vector3.ZERO, false))
	for r in 5:
		var h: float = 0.9 + 0.15 * float(r)
		var z: float = -3.6 + float(r) * 1.8
		var off: float = 0.9 if r % 2 == 1 else 0.0
		for k in 11:
			var x: float = -SECTION * 0.5 + 0.9 + float(k) * 1.8 + off
			if x > SECTION * 0.5 - 0.4:
				continue
			parts.append(GroundKit.cyl_part(0.22, 0.62, h, Vector3(x, 0.3 + h * 0.5, z), conc, Vector3(0, 45, 0), 4, false))
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes["dragons_teeth"] = m
	return m
