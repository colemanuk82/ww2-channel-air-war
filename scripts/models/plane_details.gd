class_name PlaneDetails
extends RefCounted
## Small real-world fittings that make an aircraft read as a machine from close range: pitot tubes, radio aerial
## masts and wires, bomb racks / crutches and bomb-bay door seams on the underside, and the seat, armour, harness,
## panel and stick seen through the canopy. Shared by PlaneBuilder (procedural specs) and SpitfireModel. Every part
## is a few primitive meshes with shadows off, so the cost per aircraft is tiny.
## Coordinates are Body space (metres, nose toward -Z, +Y up). The wing dictionaries are the ones returned by
## PlaneBuilder.wing_section / SpitfireModel._wing_section: {x, yc, t, zle, chord}.

const METAL := Color(0.16, 0.16, 0.17)
const STEEL := Color(0.34, 0.35, 0.34)
const OLIVE := Color(0.20, 0.22, 0.14)
const WEBBING := Color(0.52, 0.48, 0.34)
const LEATHER := Color(0.30, 0.20, 0.12)

## Which aircraft carry what underneath. wing = spans (0..1) of underwing racks (a rack each side), belly = a
## centreline rack, crutch = Stuka swing-arm crutch, bay = bomb-bay door seams.
const LOADOUT := {
	"spitfire": {"belly": true, "wing": [0.14]},
	"hurricane": {"wing": [0.32]},
	"typhoon": {"wing": [0.30]},
	"tempest": {"wing": [0.30]},
	"p51": {"wing": [0.34]},
	"p47": {"belly": true, "wing": [0.36]},
	"bf109": {"belly": true},
	"fw190": {"belly": true, "wing": [0.36]},
	"bf110": {"belly": true, "wing": [0.30]},
	"ju87": {"crutch": true, "wing": [0.42]},
	"ju88": {"wing": [0.30], "bay": true},
	"he111": {"bay": true},
	"do17": {"bay": true},
	"mosquito": {"bay": true, "wing": [0.34]},
	"lancaster": {"bay": true},
	"b26": {"bay": true},
	"b25": {"bay": true},
	"a20": {"bay": true},
	"blenheim": {"bay": true},
	"fw200": {"wing": [0.40]},
	"p38": {"wing": [0.26]},
}


static func _mat(c: Color) -> Material:
	return ToonUtil.make_toon(c, {"outline": false, "rim": 0.0, "gloss": 0.5})


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, nm: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, nm: String = "") -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(parent, bm, mat, pos, nm)


## A thin round rod from a to b (wires, struts, tubes).
static func rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, nm: String = "") -> MeshInstance3D:
	var len: float = a.distance_to(b)
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = maxf(len, 0.001)
	cm.radial_segments = 5
	cm.rings = 1
	var mi: MeshInstance3D = _add(parent, cm, mat, (a + b) * 0.5, nm)
	var up: Vector3 = (b - a).normalized()
	var ref: Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x: Vector3 = ref.cross(up).normalized()
	var z: Vector3 = x.cross(up).normalized()
	mi.basis = Basis(x, up, z)
	return mi


## Pitot tube: a short mast off the leading edge carrying a forward-pointing tube with a tapered head.
## root = a point on the underside of the leading edge.
static func pitot(body: Node3D, root: Vector3, length: float = 0.55) -> void:
	var m: Material = _mat(METAL)
	var tip: Vector3 = root + Vector3(0.0, -0.05, -length)
	rod(body, root + Vector3(0.0, 0.07, 0.12), root + Vector3(0.0, -0.05, -0.02), 0.022, m, "PitotMast")
	rod(body, root + Vector3(0.0, -0.05, 0.02), tip, 0.014, m, "Pitot")
	rod(body, tip, tip + Vector3(0.0, 0.0, -0.07), 0.007, _mat(STEEL), "PitotHead")


## Radio aerial: a short mast on the spine and a wire down to the fin tip (plus an optional second leg to a
## tailplane tip), with a small insulator at each end.
static func aerial(body: Node3D, mast_base: Vector3, mast_h: float, fin_tip: Vector3, tail_tip: Variant = null) -> void:
	var m: Material = _mat(METAL)
	var wire: Material = _mat(Color(0.05, 0.05, 0.05))
	var top: Vector3 = mast_base + Vector3(0.0, mast_h, 0.0)
	var mast: MeshInstance3D = rod(body, mast_base + Vector3(0.0, -0.03, 0.04), top, 0.02, m, "AerialMast")
	mast.scale = Vector3(1.0, 1.0, 1.0)
	box(body, Vector3(0.05, 0.03, 0.05), top, _mat(Color(0.7, 0.68, 0.6)), "AerialInsulator")
	rod(body, top, fin_tip, 0.0055, wire, "AerialWire")
	if tail_tip is Vector3:
		rod(body, top, tail_tip as Vector3, 0.0045, wire, "AerialWire2")


## Underwing bomb rack on a short pylon, with sway braces, a release unit and a lug under it.
static func wing_rack(body: Node3D, ws: Dictionary, side: float) -> void:
	var m: Material = _mat(METAL)
	var st: Material = _mat(STEEL)
	var x: float = side * float(ws["x"])
	var y0: float = float(ws["yc"]) - float(ws["t"]) * 0.5
	var z: float = float(ws["zle"]) + float(ws["chord"]) * 0.42
	box(body, Vector3(0.09, 0.14, 0.62), Vector3(x, y0 - 0.06, z), m, "RackPylon")
	box(body, Vector3(0.13, 0.07, 0.50), Vector3(x, y0 - 0.15, z), st, "RackBody")
	for k in 2:
		var zz: float = z + (-0.17 if k == 0 else 0.17)
		box(body, Vector3(0.05, 0.05, 0.05), Vector3(x, y0 - 0.20, zz), m, "RackLug")
		box(body, Vector3(0.17, 0.018, 0.04), Vector3(x, y0 - 0.19, zz), st, "RackSwayBrace")
	box(body, Vector3(0.05, 0.03, 0.12), Vector3(x, y0 - 0.12, z - 0.34), m, "RackFairing")


## Centreline rack under the fuselage (an ETC-style rack): faired body, two lugs, sway braces and an arming unit.
static func belly_rack(body: Node3D, z: float, bottom_y: float) -> void:
	var m: Material = _mat(METAL)
	var st: Material = _mat(STEEL)
	box(body, Vector3(0.16, 0.10, 0.80), Vector3(0.0, bottom_y - 0.05, z), m, "BellyRack")
	box(body, Vector3(0.10, 0.06, 0.20), Vector3(0.0, bottom_y - 0.04, z - 0.50), m, "BellyRackNose")
	for k in 2:
		var zz: float = z + (-0.26 if k == 0 else 0.26)
		box(body, Vector3(0.06, 0.06, 0.06), Vector3(0.0, bottom_y - 0.12, zz), st, "BellyLug")
		box(body, Vector3(0.30, 0.02, 0.05), Vector3(0.0, bottom_y - 0.105, zz), st, "BellySwayBrace")
	box(body, Vector3(0.06, 0.04, 0.10), Vector3(0.0, bottom_y - 0.03, z + 0.50), st, "BellyArming")


## Ju 87 style crutch: a forked swing arm slung under the fuselage that throws the bomb clear of the propeller.
static func crutch(body: Node3D, z: float, bottom_y: float) -> void:
	var m: Material = _mat(METAL)
	box(body, Vector3(0.12, 0.10, 0.30), Vector3(0.0, bottom_y - 0.04, z + 0.2), m, "CrutchHousing")
	for side in [-1.0, 1.0]:
		rod(body, Vector3(side * 0.06, bottom_y - 0.07, z + 0.2), Vector3(side * 0.30, bottom_y - 0.30, z - 0.55), 0.028, m, "CrutchArm")
		box(body, Vector3(0.05, 0.05, 0.08), Vector3(side * 0.30, bottom_y - 0.31, z - 0.58), m, "CrutchShoe")
	rod(body, Vector3(-0.30, bottom_y - 0.30, z - 0.55), Vector3(0.30, bottom_y - 0.30, z - 0.55), 0.02, m, "CrutchBar")


## Bomb-bay door seams on the underside of a bomber: two long edges, a centre split and cross seams,
## laid just proud of the hull so they read as panel lines (and open doors' hinge lines).
static func bay_doors(body: Node3D, f: Dictionary, z0: float, z1: float) -> void:
	var seam: Material = _mat(Color(0.05, 0.05, 0.06))
	var mid: float = (z0 + z1) * 0.5
	var d: Array = PlaneBuilder.fus_at(f, mid)
	var hw: float = float(d[0]) * 0.52
	var hh: float = maxf(float(d[1]), 0.001)
	var cy: float = float(d[2])
	var length: float = absf(z1 - z0)
	for side in [-1.0, 1.0]:
		var t: float = clampf(hw / maxf(float(d[0]), 0.001), 0.0, 0.95)
		var y: float = cy - hh * sqrt(maxf(1.0 - t * t, 0.0)) - 0.012
		box(body, Vector3(0.035, 0.018, length), Vector3(side * hw, y, mid), seam, "BayEdge")
	box(body, Vector3(0.03, 0.018, length), Vector3(0.0, cy - hh - 0.012, mid), seam, "BaySplit")
	for k in 4:
		var zz: float = lerpf(z0, z1, float(k) / 3.0)
		var dd: Array = PlaneBuilder.fus_at(f, zz)
		box(body, Vector3(hw * 2.0, 0.018, 0.04), Vector3(0.0, float(dd[2]) - maxf(float(dd[1]), 0.001) - 0.012, zz), seam, "BayCross")


## Fits the underside gear for `id` from the LOADOUT table. `wing_of(t)` returns the wing section dictionary,
## `bottom_y` the fuselage underside height at the wing root, `root_z` a z under the wing root.
static func underside(body: Node3D, id: String, wing_of: Callable, bottom_y: float, root_z: float, f: Dictionary = {}) -> void:
	if not LOADOUT.has(id):
		return
	var lo: Dictionary = LOADOUT[id]
	for t in lo.get("wing", []):
		var ws: Dictionary = wing_of.call(float(t))
		for side in [-1.0, 1.0]:
			wing_rack(body, ws, side)
	if bool(lo.get("belly", false)):
		belly_rack(body, root_z, bottom_y)
	if bool(lo.get("crutch", false)):
		crutch(body, root_z, bottom_y)
	if bool(lo.get("bay", false)) and not f.is_empty():
		var w0: Dictionary = wing_of.call(0.0)
		var zz0: float = float(w0["zle"]) + float(w0["chord"]) * 0.05
		var zz1: float = float(w0["zle"]) + float(w0["chord"]) * 0.98
		bay_doors(body, f, zz0, zz1)


## The cockpit as seen through the canopy from outside: armoured seat back and headrest behind the pilot, a seat
## pan and side rails, harness straps over the shoulders, the instrument panel under the coaming, a reflector
## gunsight, a control column and the rear bulkhead. `eye` is the pilot's eye point (the pilot model sits just
## below it). Bombers also get a second seat behind the pilot for the flight engineer / navigator.
static func cockpit(canopy: Node3D, eye: Vector3, bomber: bool = false) -> void:
	var root := Node3D.new()
	root.name = "CockpitInterior"
	canopy.add_child(root)
	var steel: Material = _mat(Color(0.22, 0.24, 0.20))
	var dark: Material = _mat(Color(0.08, 0.08, 0.09))
	var seat_col: Material = _mat(Color(0.19, 0.21, 0.14))
	var web: Material = _mat(WEBBING)
	var leather: Material = _mat(LEATHER)
	var glass: Material = _mat(Color(0.55, 0.75, 0.85))
	# armoured seat back + headrest plate (behind the pilot, +Z)
	box(root, Vector3(0.36, 0.52, 0.035), eye + Vector3(0.0, -0.34, 0.17), seat_col, "SeatBack")
	box(root, Vector3(0.24, 0.22, 0.03), eye + Vector3(0.0, -0.02, 0.185), steel, "HeadArmour")
	box(root, Vector3(0.20, 0.10, 0.03), eye + Vector3(0.0, -0.13, 0.15), leather, "HeadCushion")
	# seat pan and side rails
	box(root, Vector3(0.36, 0.035, 0.34), eye + Vector3(0.0, -0.56, 0.0), seat_col, "SeatPan")
	for side in [-1.0, 1.0]:
		box(root, Vector3(0.03, 0.14, 0.34), eye + Vector3(side * 0.19, -0.50, 0.0), steel, "SeatRail")
		# harness: shoulder strap from behind the headrest down to the lap
		rod(root, eye + Vector3(side * 0.09, -0.07, 0.15), eye + Vector3(side * 0.06, -0.45, -0.10), 0.014, web, "Harness")
	box(root, Vector3(0.34, 0.025, 0.04), eye + Vector3(0.0, -0.46, -0.10), web, "LapStrap")
	box(root, Vector3(0.07, 0.05, 0.015), eye + Vector3(0.0, -0.46, -0.125), _mat(STEEL), "HarnessBuckle")
	# instrument panel under the coaming, with the reflector gunsight on top
	box(root, Vector3(0.58, 0.20, 0.03), eye + Vector3(0.0, -0.20, -0.50), dark, "Panel")
	box(root, Vector3(0.62, 0.05, 0.10), eye + Vector3(0.0, -0.09, -0.52), dark, "Coaming")
	for k in 3:
		var dial := CylinderMesh.new()
		dial.top_radius = 0.035
		dial.bottom_radius = 0.035
		dial.height = 0.012
		dial.radial_segments = 8
		var dm: MeshInstance3D = _add(root, dial, _mat(Color(0.7, 0.7, 0.62)), eye + Vector3(-0.17 + 0.17 * float(k), -0.19, -0.48))
		dm.rotation.x = deg_to_rad(90.0)
	box(root, Vector3(0.05, 0.05, 0.08), eye + Vector3(0.0, -0.05, -0.43), dark, "SightHousing")
	var sg: MeshInstance3D = box(root, Vector3(0.10, 0.10, 0.006), eye + Vector3(0.0, 0.02, -0.46), glass, "SightGlass")
	sg.rotation.x = deg_to_rad(-25.0)
	# control column with a spade grip, and rudder bar
	rod(root, eye + Vector3(0.0, -0.58, -0.18), eye + Vector3(0.0, -0.33, -0.27), 0.016, dark, "Stick")
	box(root, Vector3(0.11, 0.04, 0.04), eye + Vector3(0.0, -0.31, -0.28), dark, "StickGrip")
	box(root, Vector3(0.34, 0.025, 0.03), eye + Vector3(0.0, -0.60, -0.40), dark, "RudderBar")
	# rear bulkhead behind the seat, and a canopy rail each side
	box(root, Vector3(0.52, 0.46, 0.03), eye + Vector3(0.0, -0.30, 0.33), dark, "RearBulkhead")
	if bomber:
		# second seat behind the pilot, offset to the right: a folding seat with a low back
		var sx: Vector3 = eye + Vector3(0.32, -0.30, 0.95)
		box(root, Vector3(0.34, 0.035, 0.34), sx + Vector3(0.0, -0.20, 0.0), seat_col, "SecondSeat")
		box(root, Vector3(0.34, 0.40, 0.035), sx + Vector3(0.0, 0.0, 0.17), seat_col, "SecondSeatBack")
		box(root, Vector3(0.20, 0.10, 0.06), sx + Vector3(0.0, 0.18, 0.18), leather, "SecondHeadrest")
	for c in root.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
