class_name MeshUtil
extends RefCounted
## Procedural mesh helpers (lofted shapes with smooth normals, suitable for inverted-hull outlines).


## Ellipse ring in the XY plane at depth z.
static func ring_xy(z: float, half_w: float, half_h: float, cy: float = 0.0, n: int = 10) -> PackedVector3Array:
	var r := PackedVector3Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		r.append(Vector3(cos(a) * half_w, cy + sin(a) * half_h, z))
	return r


## Rectangle-ish ring (4 points) in the XY plane.
static func rect_xy(z: float, half_w: float, half_h: float, cy: float = 0.0) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-half_w, cy + half_h, z), Vector3(half_w, cy + half_h, z),
		Vector3(half_w, cy - half_h, z), Vector3(-half_w, cy - half_h, z)])


## 6-point airfoil section at span position x. zle = leading edge z, chord along +z, t = thickness.
static func airfoil(x: float, yc: float, zle: float, chord: float, t: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(x, yc, zle),
		Vector3(x, yc + t * 0.6, zle + chord * 0.25),
		Vector3(x, yc + t * 0.35, zle + chord * 0.7),
		Vector3(x, yc, zle + chord),
		Vector3(x, yc - t * 0.25, zle + chord * 0.65),
		Vector3(x, yc - t * 0.5, zle + chord * 0.25)])


## Loft consecutive sections (all the same point count). Winding is fixed per-triangle so
## normals point away from the shape centroid. Returns an ArrayMesh with smooth normals.
static func loft(sections: Array, cap_start: bool = true, cap_end: bool = true) -> ArrayMesh:
	var tris: Array = []
	var n: int = (sections[0] as PackedVector3Array).size()
	var centroid := Vector3.ZERO
	var count: int = 0
	for s in sections:
		for p in (s as PackedVector3Array):
			centroid += p
			count += 1
	centroid /= float(count)
	for i in range(sections.size() - 1):
		var a: PackedVector3Array = sections[i]
		var b: PackedVector3Array = sections[i + 1]
		for j in n:
			var j2: int = (j + 1) % n
			tris.append([a[j], a[j2], b[j2]])
			tris.append([a[j], b[j2], b[j]])
	if cap_start:
		_cap(tris, sections[0] as PackedVector3Array)
	if cap_end:
		_cap(tris, sections[sections.size() - 1] as PackedVector3Array)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var v0: Vector3 = t[0]
		var v1: Vector3 = t[1]
		var v2: Vector3 = t[2]
		var nrm: Vector3 = (v1 - v0).cross(v2 - v0)
		var center: Vector3 = (v0 + v1 + v2) / 3.0
		# Godot front faces are clockwise: outward normal (ccw cross) must point INTO centroid side.
		if nrm.dot(center - centroid) > 0.0:
			var tmp: Vector3 = v1
			v1 = v2
			v2 = tmp
		st.add_vertex(v0)
		st.add_vertex(v1)
		st.add_vertex(v2)
	st.generate_normals()
	return st.commit()


static func _cap(tris: Array, ring: PackedVector3Array) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	for j in ring.size():
		tris.append([c, ring[j], ring[(j + 1) % ring.size()]])


## Disc (thin cylinder) mesh whose axis is X (for roundels on fuselage sides) or Y.
static func disc(radius: float, thickness: float, axis: Vector3 = Vector3.UP, segments: int = 20) -> ArrayMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = thickness
	cm.radial_segments = segments
	cm.rings = 1
	var mesh := ArrayMesh.new()
	var arrays: Array = cm.get_mesh_arrays()
	if axis.is_equal_approx(Vector3.RIGHT):
		var b := Basis(Vector3.BACK, deg_to_rad(90.0))
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			verts[i] = b * verts[i]
			nrms[i] = b * nrms[i]
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrms
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
