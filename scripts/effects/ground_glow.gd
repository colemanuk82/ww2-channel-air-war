class_name GroundGlow
extends MeshInstance3D
## A pool of firelight on the ground: a polar mesh draped over the terrain (so hills don't cut it into a flat
## plate) with an additive, soft-edged, flickering orange shader. Cheap and round, unlike a big OmniLight3D whose
## clustered lighting showed a hard square of lit ground and trees round every fire.
##   GroundGlow.create(parent, radius) -> GroundGlow   (positions itself at the parent's ground point)
##   glow.intensity = 0..1

const RINGS: int = 6
const SEGS: int = 24
const SHADER := "res://shaders/fx_ground_glow.gdshader"

static var _shader: Shader

var radius: float = 40.0
var intensity: float = 1.0:
	set(v):
		intensity = v
		if _mat != null:
			_mat.set_shader_parameter("intensity", v)
		visible = v > 0.01
var _mat: ShaderMaterial


static func create(parent: Node3D, p_radius: float) -> GroundGlow:
	var g := GroundGlow.new()
	g.radius = p_radius
	g.top_level = true
	parent.add_child(g)
	g.global_position = parent.global_position
	g._build()
	return g


func _build() -> void:
	if _shader == null:
		_shader = load(SHADER) as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.render_priority = 2
	var c: Vector3 = global_position
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []        # [ring][seg] -> local vertex
	for ri in RINGS + 1:
		var row: Array = []
		var rr: float = radius * float(ri) / float(RINGS)
		for si in SEGS:
			var a: float = TAU * float(si) / float(SEGS)
			var wx: float = c.x + cos(a) * rr
			var wz: float = c.z + sin(a) * rr
			var wy: float = GroundKit.ground_y(wx, wz)
			if GroundKit.is_water(wx, wz):
				wy = maxf(wy, 0.0)
			row.append(Vector3(wx - c.x, wy - c.y + 0.6 + 0.004 * rr, wz - c.z))
		pts.append(row)
	for ri in RINGS:
		var u0: float = float(ri) / float(RINGS)
		var u1: float = float(ri + 1) / float(RINGS)
		for si in SEGS:
			var sj: int = (si + 1) % SEGS
			var v0: float = float(si) / float(SEGS)
			var v1: float = float(si + 1) / float(SEGS)
			var a0: Vector3 = pts[ri][si]
			var a1: Vector3 = pts[ri][sj]
			var b0: Vector3 = pts[ri + 1][si]
			var b1: Vector3 = pts[ri + 1][sj]
			for q in [[a0, u0, v0], [b0, u1, v0], [b1, u1, v1], [a0, u0, v0], [b1, u1, v1], [a1, u0, v1]]:
				st.set_uv(Vector2(float(q[1]), float(q[2])))
				st.set_normal(Vector3.UP)
				st.add_vertex(q[0])
	mesh = st.commit()
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 20.0
	visibility_range_end = 9000.0
