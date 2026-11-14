class_name LodCull
extends RefCounted
## Distance culling for detailed scenery: every MeshInstance3D under a freshly built site that has no visibility
## range of its own gets one that grows with its size (a screw-head disappears at 1.4 km, a hangar stays to 12 km),
## and the tiniest parts stop casting sun shadows. Models are built "detailed up close" (many small boxes and
## cylinders each its own draw call and shadow caster); this makes them cost nothing once they are a few pixels
## across, without touching how any model is built. Nodes that already pick their own range (LOD pairs, props,
## guns, vehicles, crew) are left alone.
##
##   LodCull.apply(site_node)      # call after the node has entered the tree (scripted children have built then)

## A part is culled where it is ~RANGE_PER_METRE x its longest side away (about 4 px at 4K, 2 px at 1080p).
const RANGE_PER_METRE: float = 450.0
const MIN_RANGE: float = 1400.0
const MAX_RANGE: float = 12000.0
## Parts with no side longer than this stop casting sun shadows (their shadows are sub-pixel in the cascades).
const SHADOWLESS_BELOW: float = 1.6
const GROUP_KEEP: String = "lod_keep"        # opt out: add a node to this group to leave it and its children alone

static var enabled: bool = true

## Meshes with fewer vertices than this are left as they are (the simplifier cannot make a small mesh cheaper).
const LOD_MIN_VERTS: int = 4500
static var _lod_ok: int = -1        # 1 once ImporterMesh.generate_lods is known to take the expected arguments


## A copy of `mesh` carrying engine mesh-LODs (meshoptimizer simplification): the renderer swaps to the cheaper index
## buffers on its own as the model gets small on screen, with no node or script cost. Detailed one-mesh models
## (cathedrals, ships, bridges, hangars...) are drawn full detail only while close. Returns `mesh` unchanged if it is
## small, already has LODs, or the simplifier is unavailable.
static func with_lods(mesh: ArrayMesh) -> ArrayMesh:
	if not enabled or mesh == null or _lod_ok == 0:
		return mesh
	var verts: int = 0
	for si in mesh.get_surface_count():
		var a: Array = mesh.surface_get_arrays(si)
		verts += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if verts < LOD_MIN_VERTS:
		return mesh
	if _lod_ok < 0:
		_lod_ok = 0
		for md in ClassDB.class_get_method_list("ImporterMesh"):
			if String(md["name"]) == "generate_lods" and (md["args"] as Array).size() == 3:
				_lod_ok = 1
		if _lod_ok == 0:
			return mesh
	var im := ImporterMesh.new()
	for si in mesh.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(si), [], {}, mesh.surface_get_material(si))
	im.generate_lods(25.0, 25.0, [])
	var out: ArrayMesh = im.get_mesh()
	return out if out != null and out.get_surface_count() == mesh.get_surface_count() else mesh


static func apply(root: Node) -> int:
	if not enabled or root == null:
		return 0
	return _walk(root, 1.0)


static func _walk(n: Node, scale_k: float) -> int:
	if n.is_in_group(GROUP_KEEP):
		return 0
	var done: int = 0
	var sk: float = scale_k
	if n is Node3D:
		var s: Vector3 = (n as Node3D).transform.basis.get_scale()
		sk = scale_k * maxf(s.x, maxf(s.y, s.z))
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.mesh != null and mi.visibility_range_end <= 0.0 and mi.visibility_range_begin <= 0.0:
			var ab: AABB = mi.mesh.get_aabb()
			if mi.custom_aabb.size != Vector3.ZERO:
				ab = mi.custom_aabb
			var side: float = ab.get_longest_axis_size() * sk
			var r: float = clampf(side * RANGE_PER_METRE, MIN_RANGE, MAX_RANGE)
			mi.visibility_range_end = r
			mi.visibility_range_end_margin = r * 0.1
			# no FADE_SELF: a fading object is drawn after the clouds and shows through cloud decks
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if side < SHADOWLESS_BELOW and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			done += 1
	for c in n.get_children():
		done += _walk(c, sk)
	return done
