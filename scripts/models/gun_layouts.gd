class_name GunLayouts
extends RefCounted
## Where each fighter's forward guns really sit, and the range they were harmonised to meet at. Positions are offsets in
## the model's own metres from the aircraft's wing-gun marker (MuzzleR), as [x, y, z, mode]:
##   mode 1  x is relative to the marker's x, and the gun is mirrored to the other side
##   mode 2  x is absolute, mirrored to the other side
##   mode 3  x is absolute, a single gun (centreline)
## "conv" is the convergence distance in metres: RAF eight-gun fighters were set at about 250 yards (230 m) in
## 1940-41, the Typhoon and Tempest cannon at about 275 m, USAAF wing guns at roughly 270-300 m; the German cowling
## MGs and engine cannon converge near 300 m, the wing cannon of the Fw 190 about the same.
## Only the guns listed are drawn from: each volley fires from a rotating subset (up to four) so the bullet stream
## comes from different mounts without raising the ammunition cost or the damage per volley.

const LAYOUTS: Dictionary = {
	"spitfire": {"conv": 230.0, "mounts": [[-0.55, 0.0, 0.0, 1], [-0.1, 0.0, 0.05, 1], [0.35, 0.0, 0.1, 1], [0.8, 0.0, 0.15, 1]]},
	"hurricane": {"conv": 230.0, "mounts": [[-0.6, 0.0, 0.0, 1], [-0.15, 0.0, 0.05, 1], [0.3, 0.0, 0.1, 1], [0.75, 0.0, 0.15, 1]]},
	"typhoon": {"conv": 275.0, "mounts": [[-0.3, 0.0, 0.0, 1], [0.35, 0.0, 0.25, 1]]},
	"tempest": {"conv": 275.0, "mounts": [[-0.3, 0.0, 0.0, 1], [0.35, 0.0, 0.25, 1]]},
	"p47": {"conv": 290.0, "mounts": [[-0.45, 0.0, 0.0, 1], [-0.05, 0.0, 0.05, 1], [0.35, 0.0, 0.1, 1], [0.75, 0.0, 0.15, 1]]},
	"p51": {"conv": 280.0, "mounts": [[-0.4, 0.0, 0.0, 1], [0.0, 0.0, 0.08, 1], [0.4, 0.0, 0.16, 1]]},
	"p38": {"conv": 450.0, "mounts": [[-0.16, 0.12, 0.0, 3], [0.16, 0.12, 0.0, 3], [-0.16, -0.12, 0.0, 3], [0.16, -0.12, 0.0, 3], [0.0, 0.0, -0.3, 3]]},
	"bf109": {"conv": 300.0, "mounts": [[0.22, 0.28, 0.0, 2], [0.0, 0.1, -0.4, 3]]},
	"fw190": {"conv": 300.0, "mounts": [[0.3, 0.3, 0.0, 2], [1.5, -0.1, 0.0, 2]]},
	"me262": {"conv": 300.0, "mounts": [[0.3, 0.0, 0.0, 2], [0.25, -0.3, 0.1, 2]]},
	"mosquito": {"conv": 270.0, "mounts": [[0.2, 0.1, 0.0, 2], [0.2, -0.22, 0.2, 2]]},
}


static func convergence(model_id: String, fallback: float) -> float:
	var d: Dictionary = LAYOUTS.get(model_id, {})
	return float(d.get("conv", fallback))


## Build Gun0..GunN markers on the model from the layout (empty when the aircraft has none). sc = the model's scale.
static func make_marks(model: Node3D, model_id: String, sc: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var d: Dictionary = LAYOUTS.get(model_id, {})
	var base: Node3D = model.get_node_or_null("MuzzleR") as Node3D
	if d.is_empty() or base == null:
		return out
	var n: int = 0
	for m in d["mounts"]:
		var e: Array = m
		var mode: int = int(e[3])
		var xs: Array = []
		match mode:
			1:
				var px: float = base.position.x + float(e[0]) * sc
				xs = [px, -px]
			2:
				xs = [float(e[0]) * sc, -float(e[0]) * sc]
			_:
				xs = [float(e[0]) * sc]
		for x in xs:
			var mk := Marker3D.new()
			mk.name = "Gun%d" % n
			n += 1
			mk.position = Vector3(float(x), base.position.y + float(e[1]) * sc, base.position.z + float(e[2]) * sc)
			model.add_child(mk)
			out.append(mk)
	return out
