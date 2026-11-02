class_name SpitfireCockpit
extends Node3D
## EXPERIMENTAL interior for the Spitfire and the Bf 109 (every mark of each shares one; "style" picks the look): a modelled cockpit in the style of the later
## bubble-hood marks -- black instrument panel with the flying group and engine instruments, reflector gunsight,
## armoured windscreen, pale "interior green" tub, side consoles, spade-grip stick, rudder pedals, seat and armour.
##
## Everything is built from simple shapes in code; the dial faces are drawn procedurally. No photographs or
## third-party textures are used (the layout follows the RAF Museum's Mk XVI cockpit as a reference only).
##
## Coordinates are eye-relative (the node sits under the aircraft's CockpitMount): +X right, +Y up, nose = -Z,
## metres. Every solid part stays at least ~0.33 m from the eye so the cockpit camera's 0.3 m near plane never
## clips it, which matters because the view turns the full way round (free look).
##
## Instruments: airspeed, altimeter, climb, rate of climb, revs, boost and the artificial horizon / heading card
## follow the aircraft; the minor engine dials are fixed at a plausible cruise reading for now.

const PANEL_PX := Vector2i(1024, 768)
const PANEL_SIZE := Vector2(0.52, 0.39)
const PANEL_CENTRE := Vector3(0.0, -0.335, -0.62)
const PANEL_TILT_DEG := -9.0                 # top edge leans away from the pilot

var GREEN := Color(0.50, 0.57, 0.45)          # interior green (RAF) / RLM 66 grey (Luftwaffe)
var GREEN_DARK := Color(0.33, 0.39, 0.30)
const BLACK := Color(0.045, 0.045, 0.05)
var FRAME := Color(0.12, 0.13, 0.12)
const METAL := Color(0.42, 0.43, 0.44)
const BRASS := Color(0.70, 0.55, 0.22)
const LEATHER := Color(0.30, 0.20, 0.12)
const WEB := Color(0.62, 0.58, 0.46)

var aircraft: Aircraft = null
var style: String = "spitfire"                # "spitfire" | "bf109"
var _fk: float = 1.0                          # frame thickness factor

var _mats: Dictionary = {}
var _vp: SubViewport
var _ctrl: Control
var _stick: Node3D
var _pedal_l: Node3D
var _pedal_r: Node3D
var _throttle: Node3D
var _hidden_pilot: Node3D = null
var _active: bool = false

# smoothed instrument values
var _roll: float = 0.0
var _pitch: float = 0.0


static func style_for_id(id: String) -> String:
	if id.begins_with("spitfire"):
		return "spitfire"
	if id.begins_with("bf109"):
		return "bf109"
	return ""


static func id_supported(id: String) -> bool:
	return style_for_id(id) != ""


static func wanted_for(a: Aircraft) -> bool:
	return a != null and a.stats != null and id_supported(String(a.stats.id))


## Build the cockpit under the aircraft's CockpitMount (or return null when there is none). Hidden until the
## cockpit view is selected (Aircraft.set_cockpit_view shows it).
static func attach(a: Aircraft) -> SpitfireCockpit:
	var mount: Node3D = a.get_cockpit_mount()
	if mount == null:
		return null
	var c := SpitfireCockpit.new()
	c.name = "SpitfireCockpit"
	c.aircraft = a
	c.style = style_for_id(String(a.stats.id))
	mount.add_child(c)
	c.build()
	c.set_active(false)
	a.cockpit_interior = c
	return c


func build() -> void:
	if style == "bf109":
		GREEN = Color(0.33, 0.345, 0.36)       # RLM 02/66 grey, darker than life
		GREEN_DARK = Color(0.21, 0.22, 0.235)
		FRAME = Color(0.10, 0.105, 0.11)
		_fk = 1.35
	else:
		GREEN = Color(0.30, 0.37, 0.27)        # interior green, deliberately darker than the real paint
		GREEN_DARK = Color(0.185, 0.235, 0.165)
	_build_panel()
	_build_coaming_and_sight()
	_build_windscreen()
	_build_hood()
	_build_hood_glass()
	_build_tub()
	_build_ribs()
	_build_left_console()
	_build_right_console()
	_build_stick_and_pedals()
	_build_seat_and_rear()


# ------------------------------------------------------------------ materials and primitives

func _mat(col: Color, rough: float = 0.85, metal: float = 0.0, emit: Color = Color(0, 0, 0), alpha: float = 1.0) -> Material:
	var key: String = "%s_%.2f_%.2f_%s_%.2f" % [col.to_html(), rough, metal, emit.to_html(), alpha]
	if _mats.has(key):
		return _mats[key]
	if emit == Color(0, 0, 0) and alpha > 0.99 and (col == GREEN or col == GREEN_DARK):
		var pm: ShaderMaterial = _paint(col, rough)
		_mats[key] = pm
		return pm
	if emit == Color(0, 0, 0) and alpha < 0.99:
		var glm: ShaderMaterial = _glass(col, alpha, rough)
		_mats[key] = glm
		return glm
	if emit == Color(0, 0, 0) and alpha > 0.99:
		# every other opaque part (switches, wood, brass, leather, trim) takes the same shadow gradient, without the grime
		var sm: ShaderMaterial = _paint(col, rough, metal, 0.0)
		_mats[key] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = 1.6
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.set_meta("base", Color(col.r, col.g, col.b, alpha))
	m.set_meta("lit", emit != Color(0, 0, 0))
	_mats[key] = m
	return m


func _box(parent: Node3D, nm: String, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, nm: String, r: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, nm: String, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A thin bar between two points (frame members, rails, levers).
func _bar(parent: Node3D, nm: String, a: Vector3, b: Vector3, thick: float, mat: Material) -> MeshInstance3D:
	var d: Vector3 = b - a
	var len: float = d.length()
	if len < 0.001:
		return null
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, len + thick * 0.9)
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	var up: Vector3 = Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(d.normalized(), up), (a + b) * 0.5)
	return mi


func _quad(parent: Node3D, nm: String, size: Vector2, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ instrument panel

func _build_panel() -> void:
	var pivot := Node3D.new()
	pivot.name = "Panel"
	pivot.position = PANEL_CENTRE
	pivot.rotation_degrees = Vector3(PANEL_TILT_DEG, 0.0, 0.0)
	add_child(pivot)
	# black backing board, a little larger than the face, and a solid block behind it so nothing shows through
	_box(pivot, "Board", Vector3(PANEL_SIZE.x + 0.06, PANEL_SIZE.y + 0.04, 0.02), Vector3(0, 0, -0.012), _mat(BLACK, 0.7))
	_box(pivot, "Behind", Vector3(PANEL_SIZE.x + 0.04, PANEL_SIZE.y + 0.02, 0.10), Vector3(0, 0, -0.07), _mat(Color(0.03, 0.03, 0.035)))
	_vp = SubViewport.new()
	_vp.name = "PanelVP"
	_vp.size = PANEL_PX * 2                    # drawn at 2x and filtered down: crisp, shimmer-free dials
	_vp.size_2d_override = PANEL_PX
	_vp.size_2d_override_stretch = true
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_ctrl = Control.new()
	_ctrl.size = Vector2(PANEL_PX)
	_ctrl.draw.connect(_draw_panel)
	_vp.add_child(_ctrl)
	# the face is sampled with a footprint-sized 4-tap filter (a screen pixel's worth of the panel is averaged), so the
	# fine dial markings do not shimmer as the head or the aircraft moves, whatever the render scale
	var psh := Shader.new()
	psh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
void fragment() {
	// box filter over the screen pixel's footprint on the texture: 4 x 4 taps
	vec2 du = dFdx(UV);
	vec2 dv = dFdy(UV);
	vec3 c = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			vec2 o = du * ((float(i) + 0.5) * 0.25 - 0.5) + dv * ((float(j) + 0.5) * 0.25 - 0.5);
			c += texture(tex, UV + o).rgb;
		}
	}
	ALBEDO = c * 0.0625;
}
"""
	var pm := ShaderMaterial.new()
	pm.shader = psh
	pm.set_shader_parameter("tex", _vp.get_texture())
	var face := MeshInstance3D.new()
	face.name = "Face"
	var qm := QuadMesh.new()
	qm.size = PANEL_SIZE
	face.mesh = qm
	face.material_override = pm
	face.position = Vector3(0, 0, 0.001)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(face)
	# bezel nuts at the corners of the face
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_cyl(pivot, "Screw", 0.006, 0.006, Vector3(sx * (PANEL_SIZE.x * 0.5 + 0.012), sy * (PANEL_SIZE.y * 0.5 - 0.01), 0.004), _mat(METAL, 0.4, 0.8), Vector3(90, 0, 0))
	# the compass bowl low on the centre line, below the panel
	var cmp := _cyl(self, "Compass", 0.045, 0.05, Vector3(0.0, -0.585, -0.50), _mat(Color(0.10, 0.10, 0.11), 0.5, 0.4))
	cmp.rotation_degrees = Vector3(-15, 0, 0)
	_cyl(self, "CompassCard", 0.036, 0.004, Vector3(0.0, -0.558, -0.505), _mat(Color(0.85, 0.82, 0.72)), Vector3(-15, 0, 0))


## At night the panel goes dark and only the radium paint glows: everything is drawn, then dimmed, then the
## luminous marks (queued while drawing) are drawn again on top.
func _draw_panel() -> void:
	_lq.clear()
	_draw_panel_body()
	var na: float = maxf(_night_now, 0.0)
	if na > 0.01:
		_ctrl.draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_PX)), Color(0.0, 0.0, 0.0, 0.9 * na))
		for f in _lq:
			(f as Callable).call()


func _draw_panel_body() -> void:
	var c: Control = _ctrl
	var font: Font = UIKit.font(true)
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_PX)), Color(0.06, 0.06, 0.065))
	if style == "bf109":
		_draw_panel_109(c, font)
		return
	# subtle panel grain: a few faint lighter strokes
	for i in 26:
		var y: float = 20.0 + float(i) * 29.0
		c.draw_line(Vector2(8, y), Vector2(PANEL_PX.x - 8, y + 3.0), Color(1, 1, 1, 0.012), 1.0)
	_draw_switch_strip(c, font)
	var a: Aircraft = aircraft
	var mph: float = 0.0
	var alt_ft: float = 0.0
	var climb_fpm: float = 0.0
	var thr: float = 0.6
	var heading: float = 0.0
	if a != null and is_instance_valid(a):
		mph = a.speed * 2.237
		alt_ft = a.global_position.y / WorldCoords.VERTICAL_SCALE * 3.281
		climb_fpm = a.velocity.y / WorldCoords.VERTICAL_SCALE * 196.85
		thr = clampf(a.throttle, 0.0, 1.0)
		heading = WorldCoords.dir_to_heading(a.get_forward())
	# flying group
	_dial_asi(c, font, Vector2(290, 175), 82.0, mph)
	_dial_horizon(c, font, Vector2(460, 175), 82.0)
	_dial_alt(c, font, Vector2(630, 175), 82.0, alt_ft)
	_dial_vsi(c, font, Vector2(290, 350), 82.0, climb_fpm)
	_dial_di(c, font, Vector2(460, 350), 82.0, heading)
	_dial_turn(c, font, Vector2(630, 350), 82.0)
	# engine group
	_dial_rev(c, font, Vector2(880, 175), 82.0, 600.0 + thr * 2250.0)
	_dial_boost(c, font, Vector2(880, 350), 82.0, -2.0 + thr * 11.0)
	# minor engine dials
	_dial_small(c, font, Vector2(290, 545), 58.0, "OIL PRESS", 0.0, 100.0, 0.74, [0, 50, 100])
	_dial_small(c, font, Vector2(430, 545), 58.0, "FUEL PRESS", 0.0, 20.0, 0.62, [0, 10, 20])
	_dial_small(c, font, Vector2(570, 545), 58.0, "OIL TEMP", 0.0, 120.0, 0.56, [0, 60, 120])
	_dial_small(c, font, Vector2(710, 545), 58.0, "RAD TEMP", 0.0, 140.0, 0.52, [0, 70, 140])
	_dial_small(c, font, Vector2(880, 545), 58.0, "FUEL", 0.0, 100.0, 0.8, [0, 50, 100])
	# lower strip: engraved maker's plate and a lamp
	c.draw_rect(Rect2(Vector2(250, 660), Vector2(640, 52)), Color(0.10, 0.10, 0.11))
	c.draw_string(font, Vector2(268, 693), "MERLIN  .  BOOST  .  RADIATOR  .  FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.78, 0.76, 0.66, 0.55))
	c.draw_circle(Vector2(940, 686), 16.0, Color(0.55, 0.08, 0.06))
	c.draw_arc(Vector2(940, 686), 18.0, 0.0, TAU, 20, Color(0.5, 0.5, 0.5), 3.0)


func _draw_panel_109(c: Control, font: Font) -> void:
	for i in 26:
		var y: float = 20.0 + float(i) * 29.0
		c.draw_line(Vector2(8, y), Vector2(PANEL_PX.x - 8, y + 3.0), Color(1, 1, 1, 0.012), 1.0)
	var a: Aircraft = aircraft
	var kmh: float = 0.0
	var alt_m: float = 0.0
	var climb_fpm: float = 0.0
	var thr: float = 0.6
	var heading: float = 0.0
	if a != null and is_instance_valid(a):
		kmh = a.speed * 3.6
		alt_m = a.global_position.y / WorldCoords.VERTICAL_SCALE
		climb_fpm = a.velocity.y / WorldCoords.VERTICAL_SCALE * 196.85
		thr = clampf(a.throttle, 0.0, 1.0)
		heading = WorldCoords.dir_to_heading(a.get_forward())
	# flying group (metric, German captions: plain ASCII so every font draws them)
	_dial_asi(c, font, Vector2(165, 175), 82.0, kmh, 800.0, 100.0, 50.0, 200.0, "FAHRT  KM/H")
	_dial_alt(c, font, Vector2(375, 175), 82.0, alt_m, "HOEHE  KM")
	_dial_horizon_de(c, font, Vector2(585, 175), 82.0)
	_dial_vsi(c, font, Vector2(165, 350), 82.0, climb_fpm, "STEIGEN")
	_dial_di(c, font, Vector2(375, 350), 82.0, heading)
	_dial_small(c, font, Vector2(585, 350), 82.0, "KRAFTSTOFF", 0.0, 100.0, 0.8, [0, 50, 100])
	# engine group
	_dial_rev(c, font, Vector2(860, 175), 82.0, 600.0 + thr * 2200.0, "DREHZAHL  x1000")
	_dial_small(c, font, Vector2(860, 350), 82.0, "LADEDRUCK  ATA x10", 0.0, 20.0, 0.25 + thr * 0.55, [0, 10, 20])
	# minor engine dials
	_dial_small(c, font, Vector2(165, 545), 58.0, "OELDRUCK", 0.0, 100.0, 0.74, [0, 50, 100])
	_dial_small(c, font, Vector2(345, 545), 58.0, "KRAFTST.DR", 0.0, 20.0, 0.62, [0, 10, 20])
	_dial_small(c, font, Vector2(525, 545), 58.0, "OELTEMP", 0.0, 120.0, 0.56, [0, 60, 120])
	_dial_small(c, font, Vector2(705, 545), 58.0, "KUEHLER", 0.0, 140.0, 0.52, [0, 70, 140])
	_dial_small(c, font, Vector2(880, 545), 58.0, "TANK", 0.0, 100.0, 0.8, [0, 50, 100])
	# lower strip: maker's plate, a row of small toggles and a lamp
	c.draw_rect(Rect2(Vector2(110, 660), Vector2(640, 52)), Color(0.10, 0.10, 0.11))
	c.draw_string(font, Vector2(128, 693), "DB 605  .  LADEDRUCK  .  KUEHLER  .  KRAFTSTOFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.78, 0.76, 0.66, 0.55))
	for i in 4:
		var x: float = 790.0 + float(i) * 50.0
		c.draw_circle(Vector2(x, 686), 13.0, Color(0.26, 0.26, 0.28))
		c.draw_line(Vector2(x, 686), Vector2(x, 664), Color(0.8, 0.8, 0.82), 5.0)
	c.draw_circle(Vector2(985, 686), 14.0, Color(0.55, 0.08, 0.06))


func _draw_switch_strip(c: Control, font: Font) -> void:
	c.draw_rect(Rect2(Vector2(20, 30), Vector2(185, 700)), Color(0.095, 0.095, 0.10))
	c.draw_rect(Rect2(Vector2(20, 30), Vector2(185, 700)), Color(0.5, 0.5, 0.5, 0.25), false, 2.0)
	var labels: Array = ["IGN", "FUEL", "COCK", "PRIME", "NAV", "LAMP", "GUN", "CAM", "SIG"]
	for i in labels.size():
		var y: float = 70.0 + float(i) * 70.0
		c.draw_circle(Vector2(75, y), 15.0, Color(0.26, 0.26, 0.28))
		c.draw_circle(Vector2(75, y), 8.0, Color(0.55, 0.55, 0.57))
		c.draw_line(Vector2(75, y), Vector2(75, y - 22.0) if i % 3 != 1 else Vector2(75, y + 22.0), Color(0.8, 0.8, 0.82), 6.0)
		c.draw_string(font, Vector2(110, y + 7.0), String(labels[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.78, 0.68, 0.7))


# radium luminous paint on ticks, numerals and needles: pale green with a soft glow halo
const LUME := Color(0.60, 0.98, 0.50)
var _lq: Array = []      # luminous draws of this frame, replayed over the night dimming


func _lume_line(c: Control, a: Vector2, b: Vector2, w: float) -> void:
	var f := func() -> void:
		c.draw_line(a, b, Color(LUME, 0.10), w + 9.0)
		c.draw_line(a, b, Color(LUME, 0.22), w + 4.0)
		c.draw_line(a, b, LUME, w)
	f.call()
	_lq.append(f)


func _lume_text(c: Control, font: Font, p: Vector2, s: String, fs: int) -> void:
	var f := func() -> void:
		c.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 9, Color(LUME, 0.10))
		c.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(LUME, 0.24))
		c.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LUME)
	f.call()
	_lq.append(f)


func _lume_poly(c: Control, pts: PackedVector2Array, col: Color = LUME) -> void:
	var f := func() -> void:
		c.draw_colored_polygon(pts, col)
	f.call()
	_lq.append(f)


# a dial: bezel, black face, ticks, numerals
func _dial_face(c: Control, ctr: Vector2, r: float) -> void:
	c.draw_circle(ctr, r + 12.0, Color(0.02, 0.02, 0.02))
	c.draw_circle(ctr, r + 8.0, Color(0.30, 0.30, 0.32))
	c.draw_circle(ctr, r + 3.0, Color(0.16, 0.16, 0.17))
	c.draw_circle(ctr, r, Color(0.035, 0.035, 0.04))


## Ticks and numerals round a dial. Angles in degrees clockwise from 12 o'clock.
func _dial_scale(c: Control, font: Font, ctr: Vector2, r: float, a0: float, a1: float, v0: float, v1: float, major: float, minor: float, num_every: float = 0.0, num_div: float = 1.0, fs: int = 22) -> void:
	var n_minor: int = int(roundf((v1 - v0) / minor))
	for i in n_minor + 1:
		var v: float = v0 + float(i) * minor
		var t: float = (v - v0) / (v1 - v0)
		var ang: float = deg_to_rad(lerpf(a0, a1, t))
		var dir := Vector2(sin(ang), -cos(ang))
		var is_major: bool = absf(fmod(v - v0, major)) < minor * 0.01 or absf(fmod(v - v0, major) - major) < minor * 0.01
		var l: float = r * (0.16 if is_major else 0.08)
		_lume_line(c, ctr + dir * (r * 0.93), ctr + dir * (r * 0.93 - l), 3.0 if is_major else 1.6)
		if num_every > 0.0 and absf(fmod(v - v0, num_every)) < minor * 0.01 and not (a1 - a0 >= 359.0 and i == n_minor):
			var s: String = str(int(roundf(v / num_div)))
			var sz: Vector2 = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var p: Vector2 = ctr + dir * (r * 0.66) + Vector2(-sz.x * 0.5, sz.y * 0.32)
			_lume_text(c, font, p, s, fs)


func _needle(c: Control, ctr: Vector2, r: float, deg: float, len_k: float = 0.85, w: float = 5.0, col: Color = LUME) -> void:
	var ang: float = deg_to_rad(deg)
	var dir := Vector2(sin(ang), -cos(ang))
	var perp := Vector2(-dir.y, dir.x)
	for g in [[5.0, 0.10], [2.5, 0.22]]:
		var gw: float = float(g[0])
		_lume_poly(c, PackedVector2Array([ctr + dir * (r * len_k + gw), ctr + perp * (w + gw), ctr - dir * (r * 0.18 + gw), ctr - perp * (w + gw)]), Color(col, float(g[1])))
	_lume_poly(c, PackedVector2Array([ctr + dir * (r * len_k), ctr + perp * w, ctr - dir * (r * 0.18), ctr - perp * w]), col)
	c.draw_circle(ctr, w * 1.6, Color(0.2, 0.2, 0.22))


func _caption(c: Control, font: Font, ctr: Vector2, r: float, s: String, fs: int = 15) -> void:
	var sz: Vector2 = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	c.draw_string(font, ctr + Vector2(-sz.x * 0.5, r * 0.40), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.83, 0.72, 0.8))


func _dial_asi(c: Control, font: Font, ctr: Vector2, r: float, mph: float, vmax: float = 480.0, major: float = 40.0, minor: float = 20.0, num_every: float = 80.0, cap: String = "AIRSPEED  MPH") -> void:
	_dial_face(c, ctr, r)
	_dial_scale(c, font, ctr, r, 15.0, 345.0, 0.0, vmax, major, minor, num_every, 1.0, 19)
	_caption(c, font, ctr, r, cap)
	_needle(c, ctr, r, lerpf(15.0, 345.0, clampf(mph / vmax, 0.0, 1.0)))


func _dial_alt(c: Control, font: Font, ctr: Vector2, r: float, ft: float, cap: String = "ALTITUDE") -> void:
	_dial_face(c, ctr, r)
	_dial_scale(c, font, ctr, r, 0.0, 360.0, 0.0, 10.0, 1.0, 0.5, 1.0, 1.0, 26)
	_caption(c, font, ctr, r, cap)
	_needle(c, ctr, r, fmod(ft, 10000.0) / 10000.0 * 360.0, 0.55, 7.0)
	_needle(c, ctr, r, fmod(ft, 1000.0) / 1000.0 * 360.0, 0.88, 4.0)


func _dial_vsi(c: Control, font: Font, ctr: Vector2, r: float, fpm: float, cap: String = "RATE OF CLIMB") -> void:
	_dial_face(c, ctr, r)
	# zero at 9 o'clock, 4000 ft/min up / down at the ends
	_dial_scale(c, font, ctr, r, 120.0, 420.0, -4.0, 4.0, 1.0, 0.5, 1.0, 1.0, 22)
	_caption(c, font, ctr, r, cap)
	var k: float = clampf(fpm / 4000.0, -1.0, 1.0)
	_needle(c, ctr, r, 270.0 + k * 150.0)


func _dial_rev(c: Control, font: Font, ctr: Vector2, r: float, rpm: float, cap: String = "ENGINE  R.P.M. x1000") -> void:
	_dial_face(c, ctr, r)
	_dial_scale(c, font, ctr, r, 20.0, 340.0, 0.0, 4.0, 0.5, 0.25, 0.5, 1.0, 20)
	_caption(c, font, ctr, r, cap)
	_needle(c, ctr, r, lerpf(20.0, 340.0, clampf(rpm / 4000.0, 0.0, 1.0)))


func _dial_boost(c: Control, font: Font, ctr: Vector2, r: float, psi: float) -> void:
	_dial_face(c, ctr, r)
	_dial_scale(c, font, ctr, r, 25.0, 335.0, -4.0, 18.0, 2.0, 1.0, 4.0, 1.0, 20)
	_caption(c, font, ctr, r, "BOOST  LB/SQ.IN")
	_needle(c, ctr, r, lerpf(25.0, 335.0, clampf((psi + 4.0) / 22.0, 0.0, 1.0)))


func _dial_small(c: Control, font: Font, ctr: Vector2, r: float, cap: String, v0: float, v1: float, frac: float, nums: Array) -> void:
	_dial_face(c, ctr, r)
	_dial_scale(c, font, ctr, r, 40.0, 320.0, v0, v1, (v1 - v0) / 4.0, (v1 - v0) / 20.0, (v1 - v0) / 2.0, 1.0, 17)
	_caption(c, font, ctr, r, cap, 12)
	_needle(c, ctr, r, lerpf(40.0, 320.0, frac), 0.82, 4.0)


func _dial_turn(c: Control, font: Font, ctr: Vector2, r: float) -> void:
	_dial_face(c, ctr, r)
	for k in [-2, -1, 0, 1, 2]:
		var ang: float = deg_to_rad(float(k) * 18.0)
		var dir := Vector2(sin(ang), -cos(ang))
		_lume_line(c, ctr + dir * r * 0.9, ctr + dir * r * 0.72, 3.0)
	var roll_bias: float = 0.0
	if aircraft != null and is_instance_valid(aircraft):
		roll_bias = clampf(-aircraft.cmd_yaw * 0.5, -1.0, 1.0)
	_needle(c, ctr, r, 0.0, 0.62, 4.0)
	# the ball in its curved glass tube
	c.draw_rect(Rect2(ctr + Vector2(-r * 0.6, r * 0.42), Vector2(r * 1.2, r * 0.26)), Color(0.12, 0.12, 0.13))
	c.draw_circle(ctr + Vector2(roll_bias * r * 0.45, r * 0.55), r * 0.10, Color(0.9, 0.9, 0.85))
	_caption(c, font, ctr, r, "TURN", 14)


func _dial_di(c: Control, font: Font, ctr: Vector2, r: float, heading: float) -> void:
	_dial_face(c, ctr, r)
	for i in 36:
		var ang: float = deg_to_rad(float(i) * 10.0 - heading)
		var dir := Vector2(sin(ang), -cos(ang))
		var major: bool = i % 3 == 0
		_lume_line(c, ctr + dir * r * 0.93, ctr + dir * (r * 0.93 - (r * 0.15 if major else r * 0.07)), 3.0 if major else 1.6)
		if major and i % 9 != 0:
			var s: String = str(i)
			var sz: Vector2 = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
			_lume_text(c, font, ctr + dir * r * 0.66 + Vector2(-sz.x * 0.5, 6.0), s, 17)
		elif i % 9 == 0:
			var s2: String = ["N", "E", "S", "W"][i / 9]
			var sz2: Vector2 = font.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
			_lume_text(c, font, ctr + dir * r * 0.64 + Vector2(-sz2.x * 0.5, 8.0), s2, 24)
	# fixed aircraft symbol
	_lume_line(c, ctr + Vector2(0, -r * 0.22), ctr + Vector2(0, r * 0.25), 4.0)
	_lume_line(c, ctr + Vector2(-r * 0.26, 0), ctr + Vector2(r * 0.26, 0), 4.0)
	_lume_line(c, ctr + Vector2(-r * 0.1, r * 0.2), ctr + Vector2(r * 0.1, r * 0.2), 4.0)
	_lume_poly(c, PackedVector2Array([ctr + Vector2(0, -r * 0.98), ctr + Vector2(-8, -r * 0.84), ctr + Vector2(8, -r * 0.84)]))


func _update_attitude() -> void:
	var a: Aircraft = aircraft
	if a != null and is_instance_valid(a):
		var b: Basis = a.global_transform.basis
		var fwd: Vector3 = -b.z
		var right: Vector3 = b.x
		_pitch = lerpf(_pitch, asin(clampf(fwd.y, -1.0, 1.0)), 0.5)
		_roll = lerpf(_roll, atan2(right.y, b.y.y), 0.5)


## German artificial horizon (Askania / Siemens pattern): scalloped caging bezel marked Los / Fest, a rounded square
## window, a gull-wing horizon bar that banks and rises / falls with the aircraft, a vertical turn pointer and a
## slip-ball tube along the bottom. Bar, pointer, tube and index are radium paint.
func _dial_horizon_de(c: Control, font: Font, ctr: Vector2, r: float) -> void:
	_update_attitude()
	# scalloped caging ring
	var rim := PackedVector2Array()
	for i in 96:
		var ang: float = TAU * float(i) / 96.0
		rim.append(ctr + Vector2(sin(ang), -cos(ang)) * (r + 13.0 + 3.0 * cos(ang * 16.0)))
	c.draw_colored_polygon(rim, Color(0.075, 0.065, 0.055))
	c.draw_circle(ctr, r + 4.0, Color(0.16, 0.16, 0.17))
	c.draw_circle(ctr, r, Color(0.03, 0.03, 0.035))
	for k in 4:
		var sa: float = TAU * (float(k) + 0.5) / 4.0
		var sp: Vector2 = ctr + Vector2(sin(sa), -cos(sa)) * (r - 7.0)
		c.draw_circle(sp, 3.2, Color(0.22, 0.2, 0.18))
		c.draw_line(sp - Vector2(2.4, 1.2), sp + Vector2(2.4, 1.2), Color(0.05, 0.05, 0.05), 1.2)
	c.draw_string(font, ctr + Vector2(-r - 13.0, -r * 0.2), "Los", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.83, 0.72, 0.8))
	c.draw_string(font, ctr + Vector2(-r - 16.0, r * 0.62), "Fest", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.83, 0.72, 0.8))
	# window
	var win := Rect2(ctr + Vector2(-r * 0.66, -r * 0.62), Vector2(r * 1.32, r * 1.0))
	c.draw_rect(win, Color(0.012, 0.012, 0.014))
	# horizon bar: banks with the aircraft, drops as the nose climbs
	var n := Vector2(sin(_roll), -cos(_roll))
	var along := Vector2(-n.y, n.x)
	var off: float = clampf(_pitch / deg_to_rad(30.0), -1.0, 1.0) * r * 0.38
	var mid: Vector2 = ctr + Vector2(0.0, -r * 0.12) - n * off
	var shape: Array = [[-0.82, 0.07], [-0.7, 0.0], [-0.13, 0.0], [-0.06, -0.075], [0.0, -0.02], [0.06, -0.075], [0.13, 0.0], [0.7, 0.0], [0.82, 0.07]]
	var prev: Vector2 = Vector2.ZERO
	for i in shape.size():
		var q: Vector2 = mid + along * float(shape[i][0]) * r + n * float(shape[i][1]) * r
		if i > 0:
			_lume_line(c, prev, q, 4.5)
		prev = q
	# turn pointer: hangs from the top, swings with the rate of turn
	var turn: float = clampf(tan(clampf(_roll, -1.3, 1.3)) * 0.35, -1.0, 1.0) * deg_to_rad(18.0)
	var piv: Vector2 = ctr + Vector2(0.0, r * 0.42)
	var dirv := Vector2(sin(turn), -cos(turn))
	var top: Vector2 = piv + dirv * r * 0.98
	_lume_line(c, piv, top, 3.0)
	var pv := Vector2(-dirv.y, dirv.x)
	_lume_poly(c, PackedVector2Array([top + pv * 6.0, top - pv * 6.0, top - pv * 6.0 + dirv * 13.0, top + pv * 6.0 + dirv * 13.0]))
	# slip tube with its ball, and the index under it
	var tube := Rect2(ctr + Vector2(-r * 0.56, r * 0.5), Vector2(r * 1.12, r * 0.15))
	_lume_poly(c, PackedVector2Array([tube.position, Vector2(tube.end.x, tube.position.y), tube.end, Vector2(tube.position.x, tube.end.y)]), Color(LUME, 0.42))
	var slip: float = 0.0
	if aircraft != null and is_instance_valid(aircraft):
		slip = clampf(-aircraft.cmd_yaw * 0.6, -1.0, 1.0)
	# the ball and the centre marks sit in front of the luminous tube, so they are replayed with it at night
	var ball := func() -> void:
		c.draw_circle(Vector2(ctr.x + slip * r * 0.42, tube.get_center().y), r * 0.075, Color(0.03, 0.03, 0.03))
		for sx in [-0.09, 0.09]:
			c.draw_line(Vector2(ctr.x + sx * r, tube.position.y), Vector2(ctr.x + sx * r, tube.end.y), Color(0.03, 0.03, 0.03), 2.0)
	ball.call()
	_lq.append(ball)
	_lume_poly(c, PackedVector2Array([Vector2(ctr.x, tube.end.y + 13.0), Vector2(ctr.x - 6.0, tube.end.y + 4.0), Vector2(ctr.x + 6.0, tube.end.y + 4.0)]))


func _dial_horizon(c: Control, font: Font, ctr: Vector2, r: float) -> void:
	_dial_face(c, ctr, r)
	_update_attitude()
	var off: float = clampf(_pitch / deg_to_rad(40.0), -1.0, 1.0) * r * 0.8   # horizon sinks as the nose climbs
	var n := Vector2(sin(_roll), -cos(_roll))     # screen "up" of the rotating card
	# half-planes: sky above the horizon line (dot(p, n) > -off), ground below
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 48
	for i in steps:
		var ang: float = TAU * float(i) / float(steps)
		pts.append(Vector2(sin(ang), -cos(ang)) * (r - 1.0))
	var sky: PackedVector2Array = _clip_half(pts, n, -off)
	var gnd: PackedVector2Array = _clip_half(pts, -n, off)
	if sky.size() >= 3:
		c.draw_colored_polygon(_offset(sky, ctr), Color(0.22, 0.38, 0.62))
	if gnd.size() >= 3:
		c.draw_colored_polygon(_offset(gnd, ctr), Color(0.36, 0.24, 0.14))
	var along := Vector2(-n.y, n.x)
	var mid: Vector2 = ctr - n * off
	c.draw_line(mid - along * r, mid + along * r, Color(0.95, 0.95, 0.9), 3.0)
	# pitch ladder marks
	for k in [-2, -1, 1, 2]:
		var o: Vector2 = mid + n * float(k) * r * 0.22
		c.draw_line(o - along * r * 0.18, o + along * r * 0.18, Color(0.95, 0.95, 0.9, 0.8), 2.0)
	# fixed aircraft symbol
	c.draw_line(ctr + Vector2(-r * 0.55, 0), ctr + Vector2(-r * 0.18, 0), Color(1.0, 0.85, 0.3), 5.0)
	c.draw_line(ctr + Vector2(r * 0.18, 0), ctr + Vector2(r * 0.55, 0), Color(1.0, 0.85, 0.3), 5.0)
	c.draw_circle(ctr, 6.0, Color(1.0, 0.85, 0.3))
	c.draw_arc(ctr, r, 0.0, TAU, 48, Color(0.02, 0.02, 0.02), 3.0)


## Clip a polygon to the half plane dot(p, n) >= d (Sutherland-Hodgman, one edge).
func _clip_half(poly: PackedVector2Array, n: Vector2, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cnt: int = poly.size()
	for i in cnt:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % cnt]
		var dp: float = p.dot(n) - d
		var dq: float = q.dot(n) - d
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p.lerp(q, dp / (dp - dq)))
	return out


func _offset(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + by)
	return out


# ------------------------------------------------------------------ coaming, gunsight, windscreen

func _build_coaming_and_sight() -> void:
	# glare shield above the panel, running forward to the windscreen base
	_box(self, "Coaming", Vector3(0.66, 0.025, 0.40), Vector3(0.0, -0.105, -0.76), _mat(GREEN_DARK, 0.9), Vector3(-4, 0, 0))
	_box(self, "CoamingFront", Vector3(0.70, 0.12, 0.03), Vector3(0.0, -0.11, -0.97), _mat(GREEN_DARK, 0.9))
	# reflector gunsight: base plate, body, angled glass and a lit ring-and-dot reticle
	var sight := Node3D.new()
	sight.name = "Gunsight"
	sight.position = Vector3(0.0, -0.08, -0.60)
	if style == "bf109":
		sight.scale = Vector3(1.25, 1.1, 1.0)     # the big square Revi housing
	add_child(sight)
	_box(sight, "Base", Vector3(0.11, 0.025, 0.12), Vector3(0, 0, 0), _mat(BLACK, 0.5, 0.4))
	_cyl(sight, "Body", 0.034, 0.06, Vector3(0, 0.03, -0.02), _mat(BLACK, 0.5, 0.4))
	_box(sight, "Hood", Vector3(0.09, 0.012, 0.08), Vector3(0, 0.085, -0.03), _mat(BLACK, 0.5, 0.4))
	_box(sight, "FrameL", Vector3(0.006, 0.075, 0.006), Vector3(-0.045, 0.08, 0.02), _mat(BLACK, 0.5, 0.4), Vector3(-30, 0, 0))
	_box(sight, "FrameR", Vector3(0.006, 0.075, 0.006), Vector3(0.045, 0.08, 0.02), _mat(BLACK, 0.5, 0.4), Vector3(-30, 0, 0))
	_quad(sight, "Glass", Vector2(0.085, 0.075), Vector3(0, 0.08, 0.02), Vector3(-30, 0, 0), _mat(Color(0.7, 0.85, 0.9), 0.1, 0.0, Color(0, 0, 0), 0.14))
	var gold: Material = _mat(Color(1.0, 0.8, 0.3), 0.5, 0.0, Color(1.0, 0.72, 0.18))
	var ring := MeshInstance3D.new()
	ring.name = "Reticle"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.0155
	tm.outer_radius = 0.0175
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = gold
	ring.position = Vector3(0, 0.08 + 0.078, 0.02 - 0.03)
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sight.add_child(ring)
	_ball(sight, "Dot", 0.0016, Vector3(0, 0.08 + 0.078, 0.02 - 0.03), gold)


func _build_windscreen() -> void:
	var fm: Material = _mat(FRAME, 0.55, 0.3)
	var gm: Material = _mat(Color(0.65, 0.82, 0.78), 0.05, 0.0, Color(0, 0, 0), 0.10)
	# armoured front panel: flat, between two posts, under a rounded top bow
	var base_z: float = -0.90
	var top_z: float = -0.62
	var base_y: float = -0.075
	var top_y: float = 0.185
	var half_b: float = 0.15
	var half_t: float = 0.125
	_bar(self, "ArmourPostL", Vector3(-half_b, base_y, base_z), Vector3(-half_t, top_y, top_z), 0.022 * _fk, fm)
	_bar(self, "ArmourPostR", Vector3(half_b, base_y, base_z), Vector3(half_t, top_y, top_z), 0.022 * _fk, fm)
	_bar(self, "ArmourBase", Vector3(-half_b, base_y, base_z), Vector3(half_b, base_y, base_z), 0.024 * _fk, fm)
	# rounded top: a few segments of an arc
	var prev: Vector3 = Vector3(-half_t, top_y, top_z)
	for i in range(1, 17):
		var t: float = float(i) / 16.0
		var ang: float = PI - PI * t
		var p := Vector3(cos(ang) * half_t, top_y + sin(ang) * 0.06, top_z - sin(ang) * 0.02)
		_bar(self, "ArmourBow%d" % i, prev, p, 0.022 * _fk, fm)
		prev = p
	_quad(self, "ArmourGlass", Vector2(half_b * 2.0 - 0.02, 0.33), Vector3(0, (base_y + top_y) * 0.5, (base_z + top_z) * 0.5), Vector3(-45.0 + 0.0, 0, 0), gm)
	# the side quarter-light frames run from the armoured post out to the cockpit sill on each side
	for s in [-1.0, 1.0]:
		var side: float = float(s)
		_bar(self, "QuarterTop", Vector3(side * half_t, top_y - 0.01, top_z), Vector3(side * 0.34, 0.10, -0.38), 0.024 * _fk, fm)
		_bar(self, "QuarterBase", Vector3(side * half_b, base_y, base_z), Vector3(side * 0.36, -0.14, -0.75), 0.026 * _fk, fm)
		_bar(self, "QuarterPost", Vector3(side * 0.36, -0.14, -0.75), Vector3(side * 0.34, 0.10, -0.38), 0.028 * _fk, fm)
		_quad(self, "QuarterGlass", Vector2(0.50, 0.26), Vector3(side * 0.255, 0.03, -0.62), Vector3(0, -side * 62.0, 0), gm)


func _build_hood() -> void:
	# the bubble hood: sill rails and three bows overhead. The glass itself is clear, so only the frame shows.
	var fm: Material = _mat(FRAME, 0.55, 0.3)
	for s in [-1.0, 1.0]:
		var side: float = float(s)
		_bar(self, "SillRail", Vector3(side * 0.40, -0.12, -0.38), Vector3(side * 0.40, -0.12, 0.92), 0.04 * _fk, fm)
	for z in [-0.34, 0.42, 0.95]:
		var prev := Vector3(-0.40, -0.12, z)
		var segs: int = 28
		var h: float = 0.52 if z < 0.0 else (0.50 if z < 0.9 else 0.30)
		for i in range(1, segs + 1):
			var t: float = float(i) / float(segs)
			var ang: float = PI - PI * t
			var p := Vector3(cos(ang) * 0.40, -0.12 + sin(ang) * (h + 0.12), z)
			_bar(self, "Bow", prev, p, 0.028 * _fk, fm)
			prev = p


## One smooth glass bubble over the hood: a lofted half-ellipse tube through the bow positions, smooth-shaded so
## the sun and sky slide across it without facets. Clear enough to see through, with a faint tint.
func _hood_h(z: float) -> float:
	if z <= -0.34:
		return 0.52
	if z < 0.42:
		return lerpf(0.52, 0.50, (z + 0.34) / 0.76)
	if z < 0.95:
		return lerpf(0.50, 0.30, (z - 0.42) / 0.53)
	return 0.30


func _hood_pt(z: float, u: float) -> Vector3:
	var ang: float = PI - PI * u
	return Vector3(cos(ang) * 0.395, -0.12 + sin(ang) * (_hood_h(z) + 0.115), z)


func _build_hood_glass() -> void:
	var nu: int = 28
	var nv: int = 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nv:
		var z0: float = lerpf(-0.34, 0.95, float(j) / float(nv))
		var z1: float = lerpf(-0.34, 0.95, float(j + 1) / float(nv))
		for i in nu:
			var u0: float = float(i) / float(nu)
			var u1: float = float(i + 1) / float(nu)
			var a: Vector3 = _hood_pt(z0, u0)
			var b: Vector3 = _hood_pt(z0, u1)
			var c: Vector3 = _hood_pt(z1, u1)
			var d: Vector3 = _hood_pt(z1, u0)
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "HoodGlass"
	mi.mesh = st.commit()
	mi.material_override = _glass(Color(0.70, 0.86, 0.90), 0.10, 0.03)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ the tub

func _build_tub() -> void:
	var g: Material = _mat(GREEN, 0.9)
	var gd: Material = _mat(GREEN_DARK, 0.9)
	# floor and a belly pan
	_box(self, "Floor", Vector3(0.80, 0.03, 1.60), Vector3(0, -0.68, -0.15), gd)
	# side walls rising to the sill ledge, with an inward lean
	for s in [-1.0, 1.0]:
		var side: float = float(s)
		_box(self, "Wall", Vector3(0.04, 0.60, 1.60), Vector3(side * 0.37, -0.40, -0.15), g, Vector3(0, 0, side * 6.0))
		_box(self, "Ledge", Vector3(0.12, 0.03, 1.40), Vector3(side * 0.43, -0.125, -0.05), g)
		_box(self, "WallUpper", Vector3(0.04, 0.12, 1.30), Vector3(side * 0.37, -0.13, 0.05), g)
	_box(self, "FrontBulkhead", Vector3(0.84, 0.95, 0.04), Vector3(0, -0.60, -0.96), gd)
	# forward bulkhead is the instrument-panel block; the rear one closes the tub behind the seat
	_box(self, "RearBulkhead", Vector3(0.80, 0.72, 0.04), Vector3(0, -0.34, 0.60), gd)
	# tunnel (fuselage frame) down the middle ahead of the seat
	_box(self, "Tunnel", Vector3(0.16, 0.14, 0.42), Vector3(0, -0.60, -0.30), gd)


func _build_left_console() -> void:
	var g: Material = _mat(GREEN, 0.9)
	var blk: Material = _mat(BLACK, 0.6, 0.2)
	var met: Material = _mat(METAL, 0.4, 0.6)
	var brass: Material = _mat(BRASS, 0.4, 0.7)
	# throttle quadrant on the port wall
	_box(self, "ThrottleBox", Vector3(0.05, 0.09, 0.30), Vector3(-0.335, -0.30, -0.18), blk)
	_box(self, "QuadrantSlot", Vector3(0.012, 0.02, 0.26), Vector3(-0.30, -0.26, -0.18), met)
	_throttle = Node3D.new()
	_throttle.name = "Throttle"
	_throttle.position = Vector3(-0.30, -0.28, -0.08)
	add_child(_throttle)
	_bar(_throttle, "Lever", Vector3(0, 0, 0), Vector3(-0.015, 0.14, 0.0), 0.012, blk)
	_ball(_throttle, "Knob", 0.022, Vector3(-0.015, 0.155, 0.0), blk)
	var pitch_lever := Node3D.new()
	pitch_lever.position = Vector3(-0.30, -0.28, -0.20)
	add_child(pitch_lever)
	_bar(pitch_lever, "Lever", Vector3(0, 0, 0), Vector3(-0.012, 0.12, 0.0), 0.010, blk)
	_ball(pitch_lever, "Knob", 0.016, Vector3(-0.012, 0.132, 0.0), _mat(Color(0.55, 0.12, 0.10)))
	# elevator trim wheel
	var trim := _cyl(self, "TrimWheel", 0.055, 0.015, Vector3(-0.355, -0.34, 0.12), blk, Vector3(0, 0, 90))
	_cyl(trim, "Hub", 0.014, 0.02, Vector3(0, 0, 0), met)
	# undercarriage / flap selector box, with lettering plate
	_box(self, "GearBox", Vector3(0.04, 0.07, 0.10), Vector3(-0.345, -0.28, 0.30), blk)
	_box(self, "GearLever", Vector3(0.012, 0.07, 0.012), Vector3(-0.31, -0.25, 0.30), brass, Vector3(0, 0, 14))
	# oxygen / hydraulic bits along the lower wall
	_cyl(self, "Cock1", 0.016, 0.05, Vector3(-0.33, -0.43, -0.05), met, Vector3(0, 0, 90))
	_cyl(self, "Cock2", 0.016, 0.05, Vector3(-0.33, -0.46, 0.10), brass, Vector3(0, 0, 90))
	_box(self, "ConsolePlate", Vector3(0.012, 0.16, 0.28), Vector3(-0.348, -0.46, 0.30), g)


func _build_right_console() -> void:
	var blk: Material = _mat(BLACK, 0.6, 0.2)
	var met: Material = _mat(METAL, 0.4, 0.6)
	var red: Material = _mat(Color(0.65, 0.12, 0.10))
	# radio control box and fuse panel on the starboard wall
	_box(self, "RadioBox", Vector3(0.05, 0.10, 0.14), Vector3(0.34, -0.30, -0.10), blk)
	_cyl(self, "RadioKnobA", 0.013, 0.02, Vector3(0.31, -0.30, -0.14), met, Vector3(0, 0, 90))
	_cyl(self, "RadioKnobB", 0.013, 0.02, Vector3(0.31, -0.30, -0.06), met, Vector3(0, 0, 90))
	_box(self, "FusePanel", Vector3(0.03, 0.12, 0.22), Vector3(0.355, -0.30, 0.22), blk)
	for i in 4:
		_cyl(self, "Fuse%d" % i, 0.008, 0.015, Vector3(0.335, -0.26 + float(i % 2) * 0.05, 0.15 + float(i / 2) * 0.12), red, Vector3(0, 0, 90))
	# flap handle and pump
	_bar(self, "FlapLever", Vector3(0.31, -0.24, 0.35), Vector3(0.30, -0.14, 0.30), 0.012, met)
	_ball(self, "FlapKnob", 0.014, Vector3(0.30, -0.135, 0.30), red)
	# map case and a pencil of switches along the lower starboard wall
	_box(self, "MapCase", Vector3(0.014, 0.10, 0.20), Vector3(0.352, -0.46, -0.08), _mat(LEATHER, 0.8))
	_box(self, "CockStrip", Vector3(0.03, 0.04, 0.26), Vector3(0.34, -0.52, 0.22), blk)


# ------------------------------------------------------------------ stick and pedals

func _build_stick_and_pedals() -> void:
	var blk: Material = _mat(BLACK, 0.6, 0.2)
	var met: Material = _mat(METAL, 0.4, 0.6)
	var red: Material = _mat(Color(0.65, 0.12, 0.10))
	_stick = Node3D.new()
	_stick.name = "Stick"
	_stick.position = Vector3(0.0, -0.64, -0.30)
	add_child(_stick)
	_cyl(_stick, "Shaft", 0.013, 0.25, Vector3(0, 0.125, 0), met)
	_cyl(_stick, "Boot", 0.04, 0.07, Vector3(0, 0.035, 0), blk)
	# spade grip: a D-shaped frame with the gun button on top
	var top := Vector3(0, 0.25, 0)
	_box(_stick, "GripHead", Vector3(0.08, 0.025, 0.04), top, blk)
	_box(_stick, "GripL", Vector3(0.016, 0.05, 0.03), top + Vector3(-0.032, 0.032, 0.0), blk)
	_box(_stick, "GripR", Vector3(0.016, 0.05, 0.03), top + Vector3(0.032, 0.032, 0.0), blk)
	_box(_stick, "GripTop", Vector3(0.08, 0.016, 0.03), top + Vector3(0, 0.06, 0.0), blk)
	_cyl(_stick, "FireButton", 0.009, 0.012, top + Vector3(0.0, 0.074, 0.0), red)
	# rudder pedals on their rails
	_pedal_l = Node3D.new()
	_pedal_l.position = Vector3(-0.12, -0.55, -0.62)
	add_child(_pedal_l)
	_pedal_r = Node3D.new()
	_pedal_r.position = Vector3(0.12, -0.55, -0.62)
	add_child(_pedal_r)
	for pd in [_pedal_l, _pedal_r]:
		_box(pd, "Plate", Vector3(0.11, 0.12, 0.012), Vector3(0, 0, 0), blk, Vector3(-30, 0, 0))
		_box(pd, "Strap", Vector3(0.10, 0.02, 0.016), Vector3(0, 0.05, 0.004), _mat(LEATHER, 0.8), Vector3(-30, 0, 0))
		_bar(pd, "Arm", Vector3(0, -0.04, 0.01), Vector3(0, -0.10, 0.28), 0.02, met)
	_box(self, "FootRail", Vector3(0.50, 0.015, 0.05), Vector3(0, -0.66, -0.55), met)


# ------------------------------------------------------------------ seat and rear

func _build_seat_and_rear() -> void:
	var gd: Material = _mat(GREEN_DARK, 0.9)
	var leather: Material = _mat(LEATHER, 0.8)
	var web: Material = _mat(WEB, 0.9)
	var met: Material = _mat(METAL, 0.4, 0.6)
	# bucket seat (the pilot's own body is hidden in this view, so the seat is what you see behind you):
	# a dished pan with bolsters, a shaped back with side wings, the armour plate and a padded headrest
	_box(self, "SeatPan", Vector3(0.40, 0.04, 0.40), Vector3(0, -0.60, 0.16), gd, Vector3(-5, 0, 0))
	_box(self, "SeatCushion", Vector3(0.33, 0.05, 0.34), Vector3(0, -0.565, 0.16), leather, Vector3(-5, 0, 0))
	for sd in [-1.0, 1.0]:
		var sx: float = float(sd)
		_box(self, "SeatBolster", Vector3(0.035, 0.12, 0.34), Vector3(sx * 0.195, -0.54, 0.16), gd)
		_box(self, "SeatWing", Vector3(0.10, 0.46, 0.03), Vector3(sx * 0.17, -0.30, 0.355), gd, Vector3(0, -sx * 28.0, 0))
	_box(self, "SeatBack", Vector3(0.30, 0.50, 0.04), Vector3(0, -0.29, 0.37), gd, Vector3(8, 0, 0))
	_box(self, "BackCushion", Vector3(0.26, 0.34, 0.04), Vector3(0, -0.25, 0.345), leather, Vector3(8, 0, 0))
	_box(self, "HeadArmour", Vector3(0.30, 0.26, 0.03), Vector3(0, 0.05, 0.43), gd, Vector3(10, 0, 0))
	_box(self, "HeadPad", Vector3(0.20, 0.13, 0.05), Vector3(0, 0.06, 0.395), leather, Vector3(10, 0, 0))
	# harness: shoulder straps up from the lap, over the seat back, and the Sutton-type lap belt
	for s in [-1.0, 1.0]:
		var side: float = float(s)
		_bar(self, "Strap", Vector3(side * 0.07, -0.46, 0.30), Vector3(side * 0.09, 0.05, 0.38), 0.035, web)
		_bar(self, "LapBelt", Vector3(side * 0.20, -0.50, 0.25), Vector3(side * 0.05, -0.50, 0.18), 0.04, web)
	_box(self, "Buckle", Vector3(0.07, 0.07, 0.015), Vector3(0, -0.48, 0.17), met)
	# radio shelf and battery behind the armour, seen when looking aft
	_box(self, "RadioShelf", Vector3(0.50, 0.06, 0.30), Vector3(0, -0.30, 0.62), gd)
	_box(self, "RadioSet", Vector3(0.34, 0.22, 0.22), Vector3(0, -0.12, 0.64), _mat(Color(0.14, 0.15, 0.14), 0.5, 0.3))
	for i in 4:
		_cyl(self, "SetKnob%d" % i, 0.014, 0.02, Vector3(-0.12 + float(i) * 0.08, -0.10, 0.525), met, Vector3(90, 0, 0))


# ------------------------------------------------------------------ worn paint, ribs and rivets

const PAINT_SHADER := """shader_type spatial;
render_mode cull_disabled;
uniform vec3 base = vec3(0.07, 0.1, 0.06);
uniform float rough = 0.85;
uniform float metal_k = 0.0;
uniform float grime = 1.0;
uniform float dim = 1.0;
varying vec3 lp;
varying float cy;
uniform mat4 root_inv;
float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vn(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}
void vertex() {
	lp = VERTEX;
	cy = (root_inv * (MODEL_MATRIX * vec4(VERTEX, 1.0))).y;
}
void fragment() {
	vec3 p = lp;
	float big = fbm(p * 3.5);
	float fine = fbm(p * 30.0);
	float dirt = (smoothstep(0.34, 0.74, big) * 0.75 + (1.0 - fine) * 0.2) * grime;
	float grease = smoothstep(0.62, 0.9, fbm(p * vec3(6.0, 1.5, 6.0) + vec3(4.1))) * grime;
	float scuff = smoothstep(0.70, 0.78, fbm(p * vec3(16.0, 3.0, 16.0) + vec3(9.7))) * grime;
	float chip = smoothstep(0.80, 0.86, fbm(p * 45.0 + vec3(2.2))) * grime;
	vec3 col = base * (1.0 - dirt * 0.5) * (0.9 + 0.2 * fine);
	col = mix(col, col * 1.45 + vec3(0.012, 0.014, 0.01), smoothstep(0.52, 0.68, fbm(p * 2.2 + vec3(7.3))) * 0.55);
	col = mix(col, col * vec3(0.55, 0.5, 0.42), grease * 0.7);
	vec3 metal = vec3(0.16, 0.16, 0.15);
	col = mix(col, metal, clamp(scuff * 0.5 + chip * 0.7, 0.0, 0.85));
	float g = smoothstep(-0.36, -0.03, cy);
	ALBEDO = col * dim * mix(0.012, 0.95, g * g);   // black in the footwell, fading up to the lit sill
	ROUGHNESS = mix(rough, 0.4, clamp(scuff + chip, 0.0, 1.0));
	METALLIC = max(metal_k, clamp(scuff * 0.4 + chip * 0.6, 0.0, 0.7));
	SPECULAR = 0.5 * mix(0.08, 1.0, g);
}
"""


func _paint(col: Color, rough: float = 0.85, metal: float = 0.0, grime: float = 1.0) -> ShaderMaterial:
	var key: String = "paint_%s_%.2f_%.2f_%.2f" % [col.to_html(), rough, metal, grime]
	if _mats.has(key):
		return _mats[key]
	if _paint_shader == null:
		_paint_shader = Shader.new()
		_paint_shader.code = PAINT_SHADER
	var m := ShaderMaterial.new()
	m.shader = _paint_shader
	var lc: Color = col.srgb_to_linear()
	m.set_shader_parameter("base", Vector3(lc.r, lc.g, lc.b))
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal_k", metal)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("dim", 1.0)
	_mats[key] = m
	return m


var _paint_shader: Shader = null
var _rain_now: float = 0.0
var _force_rain: bool = OS.get_cmdline_user_args().has("--glass-rain")


const GLASS_SHADER := """shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 tint = vec3(0.45, 0.70, 0.80);
uniform float alpha = 0.10;
uniform float rough = 0.05;
uniform float rain = 0.0;
uniform float dim = 1.0;
uniform mat4 root_inv;
varying vec3 cp;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	cp = (root_inv * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
}
void fragment() {
	// water beads and runs live on the glass itself: cp is the point's place in the cockpit, so they stay put on the
	// panes and the frame bars hide them
	vec2 uv = vec2(cp.x, cp.y * 0.75 - cp.z * 0.65);
	float bead = 0.0;
	float ring = 0.0;
	float trail = 0.0;
	if (rain > 0.02) {
		for (int layer = 0; layer < 2; layer++) {
			float scale = layer == 0 ? 30.0 : 58.0;
			vec2 g = uv * scale + float(layer) * 17.3;
			vec2 id = floor(g);
			vec2 f = fract(g);
			float h = h21(id + float(layer) * 13.1);
			float on = step(h, rain * 0.85);
			float run = step(0.72, h21(id + 4.2));
			float r = mix(0.08, 0.15, h21(id + 9.1)) * (layer == 0 ? 1.0 : 0.62);
			vec2 c = vec2(0.22 + 0.56 * h21(id + 1.7), 0.22 + 0.56 * h21(id + 2.9));
			if (run > 0.5) {
				c.y = 0.12 + 0.76 * fract(h21(id + 3.3) - TIME * 0.025 * (0.6 + h));
			}
			vec2 d = f - c;
			float dist = length(d);
			bead = max(bead, smoothstep(r, r * 0.6, dist) * on);
			ring = max(ring, smoothstep(r * 0.55, r, dist) * smoothstep(r * 1.2, r, dist) * on);
			trail = max(trail, run * on * step(0.0, d.y) * smoothstep(r * 0.4, 0.0, abs(d.x)) * smoothstep(0.42, 0.0, d.y));
		}
	}
	vec3 base = tint * dim;
	ALBEDO = mix(base, vec3(0.75, 0.82, 0.88) * dim, clamp(bead * 0.8 + trail * 0.4, 0.0, 1.0));
	ALBEDO = mix(ALBEDO, vec3(0.02) * dim, ring * 0.5);
	ALPHA = clamp(alpha + bead * 0.40 + ring * 0.22 + trail * 0.16, 0.0, 0.7);
	ROUGHNESS = rough;
	SPECULAR = 0.9;
}
"""
var _glass_shader: Shader = null


func _glass(col: Color, alpha: float, rough: float = 0.05) -> ShaderMaterial:
	var key: String = "glass_%s_%.2f_%.2f" % [col.to_html(), alpha, rough]
	if _mats.has(key):
		return _mats[key]
	if _glass_shader == null:
		_glass_shader = Shader.new()
		_glass_shader.code = GLASS_SHADER
	var m := ShaderMaterial.new()
	m.shader = _glass_shader
	var lc: Color = col.srgb_to_linear()
	m.set_shader_parameter("tint", Vector3(lc.r, lc.g, lc.b))
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("rough", rough)
	_mats[key] = m
	return m


## Inner face of a side wall at height y (the wall leans inward 6 degrees towards the top).
func _wall_in(y: float) -> float:
	return 0.350 - 0.105 * (y + 0.40)


## A batch of rivet heads as one MultiMesh.
func _rivets(nm: String, pts: PackedVector3Array, mat: Material) -> void:
	if pts.is_empty():
		return
	var sm := SphereMesh.new()
	sm.radius = 0.0045
	sm.height = 0.0075
	sm.radial_segments = 6
	sm.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
	var inst := MultiMeshInstance3D.new()
	inst.name = nm
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


## Pressed stiffening beads on the inside of the side walls, as on the real Spitfire tub: long, slightly raked
## raised ribs (some in pairs) with a row of rivets down each flank, a seam under the top rail, and chipped
## bare-metal paint along the rail edge.
func _build_ribs() -> void:
	var bead_mat: Material = _paint(GREEN.lightened(0.06), 0.8)
	var rivet_mat: Material = _paint(GREEN.lightened(0.10), 0.7, 0.0, 0.0)
	var chip_mat: Material = _mat(Color(0.55, 0.55, 0.53), 0.35, 0.7)
	var pts := PackedVector3Array()
	var is109: bool = style == "bf109"
	var tilt: float = -3.0 if is109 else -7.0
	var bw: float = 0.050 if is109 else 0.024
	var bt: float = 0.005 if is109 else 0.006
	var rv: float = 0.0 + bw * 0.5 + 0.008
	var t: float = deg_to_rad(tilt)
	var d := Vector3(0.0, cos(t), sin(t))      # bead axis (in the wall plane, ignoring the small wall lean)
	var perp := Vector3(0.0, -sin(t), cos(t))
	var zs: Array = [-0.74, -0.34, -0.22, 0.12, 0.42, 0.52]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1940
	for sd in [-1.0, 1.0]:
		var side: float = float(sd)
		var lean: float = side * 6.0
		for z in zs:
			var zc: float = float(z)
			var ym: float = -0.40
			var cx: float = side * (_wall_in(ym) - 0.005)
			_box(self, "Bead", Vector3(bt, 0.50, bw), Vector3(side * (_wall_in(ym) - bt * 0.5), ym, zc), bead_mat, Vector3(tilt, 0, lean))
			var u: float = -0.24
			while u <= 0.24:
				for off in [-rv, rv]:
					var q: Vector3 = Vector3(0, ym, zc) + d * u + perp * float(off)
					pts.append(Vector3(side * (_wall_in(q.y) - 0.006), q.y, q.z))
				u += 0.045
		if is109:
			_box(self, "Rail109", Vector3(0.006, 0.04, 1.40), Vector3(side * (_wall_in(-0.34) - 0.003), -0.34, -0.12), bead_mat, Vector3(0, 0, lean))
			var rz: float = -0.80
			while rz < 0.55:
				for ry in [-0.014, 0.014]:
					pts.append(Vector3(side * (_wall_in(-0.34 + ry) - 0.008), -0.34 + ry, rz))
				rz += 0.045
		# seam strip just under the rail, riveted
		_box(self, "Seam", Vector3(0.006, 0.022, 1.40), Vector3(side * (_wall_in(-0.21) - 0.003), -0.21, -0.12), bead_mat, Vector3(0, 0, lean))
		var zz: float = -0.80
		while zz < 0.55:
			pts.append(Vector3(side * (_wall_in(-0.21) - 0.008), -0.21, zz))
			zz += 0.05
		# chipped bare metal along the inner edge of the sill ledge
		var cz: float = -0.72
		while cz < 0.58:
			var ln: float = rng.randf_range(0.02, 0.09)
			_box(self, "Chip", Vector3(0.012, 0.004, ln), Vector3(side * 0.372, -0.1085, cz), chip_mat)
			cz += ln + rng.randf_range(0.05, 0.22)
	_rivets("Rivets", pts, rivet_mat)


# ------------------------------------------------------------------ run time
var _night_now := -1.0
var _hole_mi: MeshInstance3D = null
var _twin_mi: MeshInstance3D = null
var _twin_old: Material = null
var _twin_mat: ShaderMaterial = null


## The airframe skin is a solid hull whose top rises through the cockpit floor and lower panel. While the
## interior is shown, the skin shader (aircraft_pbr) discards a box around the cockpit so the interior shows clean.
func _set_fuselage_hole(on: bool) -> void:
	if not on:
		if _hole_mi != null and is_instance_valid(_hole_mi):
			_hole_mi.set_instance_shader_parameter("hole_a", Vector4(0, 0, 0, 0))
		_hole_mi = null
		if _twin_mi != null and is_instance_valid(_twin_mi):
			_twin_mi.material_override = _twin_old
		_twin_mi = null
		return
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var fus: MeshInstance3D = aircraft.find_child("Fuselage", true, false) as MeshInstance3D
	if fus == null:
		return
	var sm: ShaderMaterial = fus.material_override as ShaderMaterial
	if sm == null or sm.shader == null or not sm.shader.code.contains("hole_a"):
		return
	var to_local: Transform3D = fus.global_transform.affine_inverse() * global_transform
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for k in 8:
		var c := Vector3(-0.455 if (k & 1) == 0 else 0.455, -1.2 if (k & 2) == 0 else -0.28, -0.93 if (k & 4) == 0 else 0.62)
		var q: Vector3 = to_local * c
		lo = lo.min(q)
		hi = hi.max(q)
	fus.set_instance_shader_parameter("hole_a", Vector4(lo.x, lo.y, lo.z, 1.0))
	fus.set_instance_shader_parameter("hole_b", hi)
	_hole_mi = fus
	# the hull's black "inside faces" twin (Aircraft._ensure_blackout) must be cut the same way, or its black
	# faces fill the cockpit and fight the interior surfaces
	var twin: MeshInstance3D = fus.get_node_or_null("Blackout") as MeshInstance3D
	if twin != null:
		if _twin_mat == null:
			var sh := Shader.new()
			sh.code = "shader_type spatial;\nrender_mode unshaded, cull_front;\nuniform vec3 lo;\nuniform vec3 hi;\nvarying vec3 lp;\nvoid vertex() { lp = VERTEX; }\nvoid fragment() {\n\tif (all(greaterThan(lp, lo)) && all(lessThan(lp, hi))) { discard; }\n\tALBEDO = vec3(0.0);\n}\n"
			_twin_mat = ShaderMaterial.new()
			_twin_mat.shader = sh
		_twin_mat.set_shader_parameter("lo", lo)
		_twin_mat.set_shader_parameter("hi", hi)
		_twin_old = twin.material_override
		twin.material_override = _twin_mat
		_twin_mi = twin


## At night the structure goes black and only the instruments (unshaded panel texture) and the sight stay lit.
func _apply_night() -> void:
	var na: float = 0.0
	na = clampf((0.55 - TimeOfDay.light_level) / 0.4, 0.0, 1.0)
	if absf(na - _night_now) < 0.01:
		return
	_night_now = na
	var k: float = 1.0 - 0.985 * na
	for m in _mats.values():
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("dim", k)
			continue
		var mm: StandardMaterial3D = m as StandardMaterial3D
		if mm == null or bool(mm.get_meta("lit", false)):
			continue
		var b: Color = mm.get_meta("base", Color.WHITE)
		mm.albedo_color = Color(b.r * k, b.g * k, b.b * k, b.a)


func set_active(on: bool) -> void:
	_active = on
	visible = on
	_set_fuselage_hole(on)
	_night_now = -1.0
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on and _ctrl != null:
		_ctrl.queue_redraw()
	# the exterior model's pilot figure sits at the eye: hide it while the interior is shown
	if aircraft != null and is_instance_valid(aircraft):
		if on and _hidden_pilot == null:
			var p: Node3D = aircraft.find_child("Pilot", true, false) as Node3D
			if p != null and p.visible:
				_hidden_pilot = p
				p.visible = false
		elif not on and _hidden_pilot != null and is_instance_valid(_hidden_pilot):
			_hidden_pilot.visible = true
			_hidden_pilot = null


func _process(_delta: float) -> void:
	if not _active or aircraft == null or not is_instance_valid(aircraft):
		return
	if _ctrl != null:
		_ctrl.queue_redraw()
	_apply_night()
	_rain_now = 0.0
	if WeatherManager != null and WeatherManager.rain_fx != null:
		_rain_now = clampf(WeatherManager.rain_fx.intensity, 0.0, 1.0)
	if _force_rain:
		_rain_now = 0.8       # debug: --glass-rain
	var ri := Projection(global_transform.affine_inverse())
	for pm in _mats.values():
		if pm is ShaderMaterial:
			(pm as ShaderMaterial).set_shader_parameter("root_inv", ri)
			(pm as ShaderMaterial).set_shader_parameter("rain", _rain_now)
	# the stick follows the control inputs, the pedals the rudder
	if _stick != null:
		_stick.rotation = Vector3(aircraft.cmd_pitch * 0.30, 0.0, -aircraft.cmd_roll * 0.40)
	if _pedal_l != null:
		_pedal_l.position.z = -0.62 - aircraft.cmd_yaw * 0.03
		_pedal_r.position.z = -0.62 + aircraft.cmd_yaw * 0.03
	if _throttle != null:
		_throttle.rotation.x = -clampf(aircraft.throttle, 0.0, 1.0) * 0.9 + 0.45


func _exit_tree() -> void:
	_set_fuselage_hole(false)
	if _ctrl != null and is_instance_valid(_ctrl) and _ctrl.draw.is_connected(_draw_panel):
		_ctrl.draw.disconnect(_draw_panel)
	if _vp != null and is_instance_valid(_vp):
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_vp.free()
	_ctrl = null
	_vp = null
