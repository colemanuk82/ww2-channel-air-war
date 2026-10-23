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

## Cubic Hermite point between a and b with tangents ta, tb at u in 0..1 (parameter = section index).
static func _hermite(a: Vector3, b: Vector3, ta: Vector3, tb: Vector3, u: float) -> Vector3:
	var u2: float = u * u
	var u3: float = u2 * u
	return a * (2.0 * u3 - 3.0 * u2 + 1.0) + ta * (u3 - 2.0 * u2 + u) + b * (-2.0 * u3 + 3.0 * u2) + tb * (u3 - u2)


## Insert `sub - 1` smoothly interpolated sections between every pair (Catmull-Rom through the originals).
## All sections must have the same point count. The original sections are kept exactly.
static func smooth_sections(sections: Array, sub: int) -> Array:
	if sub <= 1 or sections.size() < 3:
		return sections
	var out: Array = []
	var n: int = sections.size()
	for i in range(n - 1):
		var a: PackedVector3Array = sections[i]
		var b: PackedVector3Array = sections[i + 1]
		var pa: PackedVector3Array = sections[maxi(i - 1, 0)]
		var nb: PackedVector3Array = sections[mini(i + 2, n - 1)]
		out.append(a)
		for k in range(1, sub):
			var u: float = float(k) / float(sub)
			var r := PackedVector3Array()
			for j in a.size():
				var ta: Vector3 = (b[j] - pa[j]) * (0.5 if i > 0 else 1.0)
				var tb: Vector3 = (nb[j] - a[j]) * (0.5 if i + 2 < n else 1.0)
				r.append(_hermite(a[j], b[j], ta, tb, u))
			out.append(r)
	out.append(sections[n - 1])
	return out


## Double the points of a closed ring, the new ones lying on the Catmull-Rom curve through the old ones (rounder cross-sections).
static func refine_ring(ring: PackedVector3Array) -> PackedVector3Array:
	var n: int = ring.size()
	var out := PackedVector3Array()
	for i in n:
		var p0: Vector3 = ring[(i - 1 + n) % n]
		var p1: Vector3 = ring[i]
		var p2: Vector3 = ring[(i + 1) % n]
		var p3: Vector3 = ring[(i + 2) % n]
		out.append(p1)
		out.append((-p0 + 9.0 * p1 + 9.0 * p2 - p3) / 16.0)
	return out


## Smooth loft: more sections along the length and rounder rings (ring_passes = how many times the ring is doubled).
static func loft_smooth(sections: Array, sub: int = 3, ring_passes: int = 1, cap_start: bool = true, cap_end: bool = true) -> ArrayMesh:
	var secs: Array = []
	for r in sections:
		var ring: PackedVector3Array = r
		for _k in ring_passes:
			ring = refine_ring(ring)
		secs.append(ring)
	return loft(smooth_sections(secs, sub), cap_start, cap_end)
