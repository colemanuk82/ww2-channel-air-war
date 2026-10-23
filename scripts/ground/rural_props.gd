class_name RuralProps
extends RefCounted
## Small countryside details scattered by the landcover tiles (Scatter.tile_landcover_data): corn ricks and
## stook rows on the arable fields - the harvest was still built into thatched ricks by hand in the 1940s - and
## the odd crashed aircraft lying in a field on its scorched scar, as the Kent and Sussex farms saw all through 1940.
## Meshes are built on the main thread (build_tile_nodes) and cached in Scatter._meshes.

const VIS_RICK := 2000.0
const VIS_WRECK := 3200.0


## Corn rick: a round straw stack with a thatched conical cap. ~5 m across, 6 m tall.
static func rick_mesh() -> ArrayMesh:
	if Scatter._meshes.has("rick"):
		return Scatter._meshes["rick"]
	var straw := Color(0.50, 0.43, 0.26)
	var thatch := Color(0.40, 0.33, 0.21)
	var parts: Array = []
	parts.append(GroundKit.cyl_part(2.5, 2.3, 3.4, Vector3(0, 1.7, 0), straw, Vector3.ZERO, 10))
	parts.append(GroundKit.cyl_part(0.2, 2.75, 2.6, Vector3(0, 4.7, 0), thatch, Vector3.ZERO, 10))
	parts.append(GroundKit.cyl_part(0.12, 0.12, 0.8, Vector3(0, 6.3, 0), thatch.darkened(0.2), Vector3.ZERO, 5, false))
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes["rick"] = m
	return m


## A row of stooks (sheaves stood up in pairs to dry) - one instance is a 12 m row of six.
static func stook_mesh() -> ArrayMesh:
	if Scatter._meshes.has("stooks"):
		return Scatter._meshes["stooks"]
	var straw := Color(0.54, 0.47, 0.29)
	var parts: Array = []
	for i in 6:
		parts.append(GroundKit.cyl_part(0.12, 0.55, 1.3, Vector3(0, 0.65, -5.0 + float(i) * 2.0), straw, Vector3.ZERO, 6, false))
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes["stooks"] = m
	return m


## Crashed fighter: a broken fuselage nosed into its own furrow, one wing torn off and lying apart, the tail
## section snapped, on a scorched patch of earth. Neutral weathered paint so it reads as either side's.
static func wreck_mesh() -> ArrayMesh:
	if Scatter._meshes.has("field_wreck"):
		return Scatter._meshes["field_wreck"]
	var scorch := Color(0.13, 0.12, 0.10)
	var earth := Color(0.33, 0.27, 0.19)
	var paint := Color(0.30, 0.32, 0.25)
	var under := Color(0.55, 0.57, 0.52)
	var metal := Color(0.40, 0.40, 0.40)
	var parts: Array = []
	parts.append(GroundKit.cyl_part(9.0, 10.0, 0.12, Vector3(0, 0.04, 0), scorch, Vector3.ZERO, 12, false))
	parts.append(GroundKit.box_part(Vector3(4.0, 0.5, 26.0), Vector3(0, 0.15, 14.0), earth, Vector3.ZERO, false))   # gouge
	parts.append(GroundKit.cyl_part(0.55, 0.75, 6.5, Vector3(0, 0.55, 0.0), paint, Vector3(84, 0, 6)))               # fuselage
	parts.append(GroundKit.cyl_part(0.75, 0.6, 1.6, Vector3(0.1, 0.45, -3.9), metal, Vector3(70, 0, 0)))             # crumpled nose
	parts.append(GroundKit.box_part(Vector3(4.6, 0.18, 1.9), Vector3(-2.4, 0.4, 0.3), paint, Vector3(0, 6, -9)))    # attached wing stub
	parts.append(GroundKit.box_part(Vector3(5.2, 0.18, 1.9), Vector3(6.5, 0.25, 4.5), under, Vector3(0, 38, 172)))  # torn-off wing, upside down
	parts.append(GroundKit.cyl_part(0.3, 0.45, 2.6, Vector3(-1.6, 0.4, 5.8), paint, Vector3(90, 0, -20)))           # snapped tail
	parts.append(GroundKit.box_part(Vector3(0.12, 1.3, 1.1), Vector3(-2.1, 1.05, 6.8), paint, Vector3(0, -20, 18)))   # fin
	parts.append(GroundKit.box_part(Vector3(2.4, 0.1, 0.8), Vector3(-1.9, 0.5, 6.6), paint, Vector3(0, -20, 12)))
	parts.append(GroundKit.box_part(Vector3(0.18, 2.0, 0.2), Vector3(0.3, 0.6, -4.9), Color(0.08, 0.08, 0.08), Vector3(0, 30, 70), false))   # bent prop blade
	for k in 6:   # scattered debris
		var a: float = float(k) * 1.1
		parts.append(GroundKit.box_part(Vector3(0.6 + 0.2 * float(k % 3), 0.15, 0.5), Vector3(cos(a) * (4.0 + float(k)), 0.12, sin(a) * (3.0 + float(k)) + 2.0), metal if k % 2 == 0 else paint, Vector3(0, float(k) * 40.0, 10.0), false))
	var m: ArrayMesh = AirfieldAssets._build(parts)
	Scatter._meshes["field_wreck"] = m
	return m
