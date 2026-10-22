class_name CockpitInterior
extends Node3D
## Procedural period cockpit interior for the player's aircraft.
##
## The .glb aircraft carry an exterior canopy, a pilot figure and the CockpitEye marker, but no cockpit
## shell: the fuselage is a single-surface shell whose inside faces are backfaces and are culled, so from
## the eye you look straight through the aircraft at the world (the "empty bubble"). This node builds that
## missing shell in code - a SOLID cockpit tub (floor, side walls, front and rear bulkheads), an
## instrument panel with live gauges, a reflector gunsight, the windscreen / canopy framing, side
## consoles, a seat, a control stick and a throttle quadrant.
##
## Coordinates are eye-relative because the node is parented to the aircraft's CockpitMount, which sits at
## the model's CockpitEye: +X is right, +Y is up, the nose is -Z (this project's aircraft axes). The panel
## sits ~0.6 m ahead of the eye with its top edge just below the horizon line, so the aircraft's own
## nose/cowling is still visible over it (Aircraft never moves the cockpit camera).
##
## Occlusion: every enclosing surface is a closed box (never a single quad), so the face that looks back at
## the eye is always front-facing and cannot be culled. The tub is deliberately generous and every join is
## an OVERLAP, not a touching seam - the walls run down past the floor into a belly fairing, up above eye
## level into the sill rails, and forward/aft past the bulkheads into corner gussets - so no sliver gap
## survives at a corner. The solid side structure rises to SILL_TOP (a touch above the eye), so a look
## downhill to either side lands on the wall/sill, never on the world beside it, and a full-width glare
## shield closes the panel-top-to-windscreen corner that used to let the world in beside the panel. Every
## enclosing face is kept at least 0.33 m from the eye so the cockpit camera's near plane (0.3 m) never
## clips a hole in it; the wall inner face sits at exactly 0.33 m.
##
## The instruments are not modelled here: HUD.draw_cockpit_panel (the same code that draws the on-screen
## gauges) renders into a SubViewport mapped onto the panel face, so the 3D panel reads the same live
## values as the HUD.

const PANEL_W := 640
const PANEL_H := 512
## Panel centre in eye-relative metres: 0.60 m ahead, top edge ~0.19 m below the eye (~18 deg below the
## horizon at that range), so the gauges sit in the bottom of the view the way they sit in a real cockpit.
const PANEL_CENTRE := Vector3(0.0, -0.38, -0.60)
const PANEL_SIZE := Vector2(0.50, 0.375)
const PANEL_TILT_DEG := -6.0            # top edge a touch forward, as on a real panel
const WINDSCREEN_Z := -0.98             # the model's windscreen line (windscreen frame is ~0.98 m ahead of the eye)
const SIGHT_Z := -0.44                  # reflector sight body / glass, between the eye and the panel
const WALL_X := 0.415                   # side-wall centre: inner face 0.33 m out, clear of the 0.3 m near plane
const INTERIOR_ALPHA := 1.0                # fully opaque: both halves of the interior read as solid structure
const SILL_TOP := -0.10                 # side structure stays BELOW the eye: reaching above it closed off
                                        # the sideways view, which is what made the interior read as a wall

var aircraft: Aircraft = null

var _panel_vp: SubViewport
var _panel_ctrl: Control
var _hud_ref: HUD = null

# Materials (built once in setup; ToonUtil so the interior matches the game's finish).
var _mat_panel: Material
var _mat_wall: Material
var _mat_black: Material
var _mat_metal: Material
var _mat_frame: Material
var _mat_seat: Material
var _mat_reticle: Material


## Build the whole interior. Called by Aircraft right after this node is added under the CockpitMount.
func setup(a: Aircraft) -> void:
	aircraft = a
	_mat_panel = _interior_mat(Color(0.095, 0.100, 0.105))
	_mat_wall = _interior_mat(Color(0.125, 0.130, 0.135))
	_mat_black = _interior_mat(Color(0.045, 0.048, 0.052))
	_mat_metal = _interior_mat(Color(0.16, 0.17, 0.185))
	_mat_frame = _interior_mat(Color(0.055, 0.057, 0.060), Color(0.0, 0.0, 0.0), 1.0)   # the cage reads solid
	_mat_seat = _interior_mat(Color(0.24, 0.13, 0.07))
	_mat_reticle = _interior_mat(Color(1.0, 0.86, 0.35), Color(1.0, 0.72, 0.18))
	# Only the tub is built. It is the SOLID BOTTOM: floor pan, belly fairing, side walls, sills and
	# bulkheads, all sitting BELOW the sightline (sill top is -0.10, i.e. under the eye) so it never
	# intrudes into the forward view - but with it in place a look down lands on structure instead of
	# seeing the world through the aircraft's own single-sided shell. The panel, consoles, seat and
	# canopy cage stay OUT: the view sits ahead of the glass and the owner wants no visible interior.
	# Panel only: a vertical instrument wall (live gauges plus switches) low in the view. The tub, framing,
	# consoles and seat stay out so nothing blocks the outlook.
	_build_panel()
	_build_switches()


## Rows of toggle switches, knobs and a magneto/engine switch bank on the panel's lower strip.
func _build_switches() -> void:
	var node: Node3D = get_node_or_null("Panel") as Node3D
	if node == null:
		return
	var hw: float = PANEL_SIZE.x * 0.5
	var hh: float = PANEL_SIZE.y * 0.5
	var strip_y: float = -hh - 0.075
	_add_box(node, "SwitchStrip", Vector3(PANEL_SIZE.x + 0.12, 0.11, 0.03), Vector3(0.0, strip_y, -0.045), _mat_metal, Vector3.ZERO)
	for i in 9:
		var x: float = -hw + 0.04 + float(i) * (PANEL_SIZE.x - 0.08) / 8.0
		_add_box(node, "SwitchBase%d" % i, Vector3(0.026, 0.026, 0.012), Vector3(x, strip_y + 0.026, -0.06), _mat_black, Vector3.ZERO)
		var lean: float = -25.0 if i % 3 != 1 else 25.0
		_add_box(node, "Toggle%d" % i, Vector3(0.008, 0.032, 0.008), Vector3(x, strip_y + 0.036, -0.075), _mat_reticle if i % 4 == 0 else _mat_metal, Vector3(lean, 0.0, 0.0))
	for j in 4:
		var kx: float = -hw + 0.07 + float(j) * 0.09
		var knob: MeshInstance3D = _cyl("Knob%d" % j, 0.017, 0.02, Vector3(kx, strip_y - 0.03, -0.065), _mat_black, Vector3(90.0, 0.0, 0.0))
		remove_child(knob)
		node.add_child(knob)
	for k in 3:
		_add_box(node, "Lever%d" % k, Vector3(0.012, 0.05, 0.012), Vector3(hw - 0.06 - float(k) * 0.07, strip_y - 0.025, -0.07), _mat_reticle if k == 0 else _mat_metal, Vector3(-18.0, 0.0, 0.0))


## The interior's finish. INTERIOR_ALPHA sets the opacity (1.0 = solid). It stays a transparent-capable
## material so a single constant can dial the whole interior back if a see-through look is wanted again.
##
## Deliberately NOT the shared toon material: that shader has no blend mode and no alpha output
## (render_mode specular_disabled only), so an alpha in the colour would be ignored. This is a local
## unshaded material instead, which also means it cannot disturb the rest of the game.
func _interior_mat(color: Color, emission: Color = Color(0.0, 0.0, 0.0), alpha: float = INTERIOR_ALPHA) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.disable_receive_shadows = true
	if emission != Color(0.0, 0.0, 0.0):
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.4
	return m


## Show/hide the interior. Hidden in the chase view; the panel SubViewport is parked while hidden so it
## costs nothing to keep around.
func set_active(on: bool) -> void:
	visible = on
	if _panel_vp != null:
		_panel_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on and _panel_ctrl != null:
		_panel_ctrl.queue_redraw()


## Release the panel SubViewport by hand. Left to the tree it survived shutdown and leaked its CanvasItem
## RID plus the whole SubViewport subtree; parking the render target and disconnecting the draw callback
## (which keeps a reference back to this node) before freeing the viewport closes that leak.
func _exit_tree() -> void:
	if _panel_ctrl != null and is_instance_valid(_panel_ctrl) and _panel_ctrl.draw.is_connected(_draw_gauges):
		_panel_ctrl.draw.disconnect(_draw_gauges)
	if _panel_vp != null and is_instance_valid(_panel_vp):
		_panel_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_panel_vp.free()        # frees its Control child (and the gauges) with it
	_panel_ctrl = null
	_panel_vp = null


func _process(_delta: float) -> void:
	# redraw the gauges while the panel is live, so the needles track the live values
	if _panel_ctrl != null and _panel_vp != null \
			and _panel_vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		_panel_ctrl.queue_redraw()


# ---------------------------------------------------------------- the solid cockpit tub

## The surfaces that make looking down and sideways land on structure instead of the world: floor pan,
## belly fairing, two thick side walls, canopy sill rails, front and rear bulkheads, a full-width glare
## shield and four corner gussets. Every panel overlaps its neighbours (see the class comment), so no
## corner sliver can show the world, and every enclosing face is at least 0.33 m from the eye.
func _build_tub() -> void:
	# floor pan: under the seat, the legs and the footwell, meeting both walls
	_box("FloorPan", Vector3(1.00, 0.12, 1.86), Vector3(0.0, -0.80, -0.13), _mat_panel)
	# belly fairing: a wider, lower slab closing the underside outboard of the floor, so a steep downhill
	# look past the wall bottom still lands on structure. Extended well forward so a look down over the
	# nose cannot run off its front edge - that edge was the last place the world showed through.
	_box("BellyFairing", Vector3(1.04, 0.12, 1.86), Vector3(0.0, -0.905, -0.13), _mat_wall)
	_box("NoseFairing", Vector3(0.96, 0.12, 1.95), Vector3(0.0, -0.80, -1.28), _mat_wall)
	# Side walls and canopy sill rails: REMOVED. They were slabs 1.86 m long and 0.94 m tall alongside the
	# pilot, and they read as black blocks either side of the view. The underside is still closed by the
	# floor pan, belly and nose fairings above, which is the see-through that mattered; the cost of
	# dropping the walls is that a hard look straight down the side can see past the aircraft's skin.
	# front bulkhead / footwell: seals everything below and ahead of the instrument panel
	_box("FrontBulkhead", Vector3(1.00, 0.60, 0.08), Vector3(0.0, -0.62, -0.92), _mat_wall, Vector3(-12.0, 0.0, 0.0))
	# glare shield / front coaming: REMOVED. With the side walls and panel gone it closed a corner that no
	# longer exists, and it read as a dark bar across the bottom of the view.
	# rear bulkhead: behind the seat
	_box("RearBulkhead", Vector3(1.00, 0.84, 0.10), Vector3(0.0, -0.40, 0.66), _mat_wall, Vector3(8.0, 0.0, 0.0))
	# corner gussets: REMOVED. They were overlaps where the side walls met the bulkheads; with the walls
	# gone they were just two black blocks sitting in the bottom corners of the view.


# ---------------------------------------------------------------- panel + instruments

## Instrument panel with depth: a backplate, a raised bezel frame round the dial opening, and the gauge
## face recessed behind it, so the dials sit in a shallow well rather than on a flat board.
func _build_panel() -> void:
	var node := Node3D.new()
	node.name = "Panel"
	node.position = PANEL_CENTRE
	node.rotation = Vector3(deg_to_rad(PANEL_TILT_DEG), 0.0, 0.0)
	add_child(node)

	var bm := BoxMesh.new()
	bm.size = Vector3(PANEL_SIZE.x + 0.10, PANEL_SIZE.y + 0.10, 0.03)
	var board := MeshInstance3D.new()
	board.name = "PanelBoard"
	board.mesh = bm
	board.material_override = _mat_panel
	board.position = Vector3(0.0, 0.0, -0.06)
	node.add_child(board)

	# raised bezel: a frame standing proud of the board, with the dial opening in the middle
	var hw: float = PANEL_SIZE.x * 0.5
	var hh: float = PANEL_SIZE.y * 0.5
	_panel_bar(node, "BezelTop", Vector3(PANEL_SIZE.x + 0.12, 0.035, 0.05), Vector3(0.0, hh + 0.0175, 0.0))
	_panel_bar(node, "BezelBottom", Vector3(PANEL_SIZE.x + 0.12, 0.035, 0.05), Vector3(0.0, -hh - 0.0175, 0.0))
	_panel_bar(node, "BezelLeft", Vector3(0.035, PANEL_SIZE.y, 0.05), Vector3(-hw - 0.0175, 0.0, 0.0))
	_panel_bar(node, "BezelRight", Vector3(0.035, PANEL_SIZE.y, 0.05), Vector3(hw + 0.0175, 0.0, 0.0))

	# The instrument faces: the HUD's gauge drawing rendered into a SubViewport and mapped onto a quad,
	# set back behind the bezel front so the dials read as recessed.
	_panel_vp = SubViewport.new()
	_panel_vp.name = "PanelView"
	_panel_vp.size = Vector2i(PANEL_W, PANEL_H)
	_panel_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_panel_vp.disable_3d = true
	_panel_vp.transparent_bg = false
	node.add_child(_panel_vp)

	_panel_ctrl = Control.new()
	_panel_ctrl.name = "Gauges"
	_panel_ctrl.size = Vector2(PANEL_W, PANEL_H)
	_panel_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_ctrl.draw.connect(_draw_gauges)
	_panel_vp.add_child(_panel_ctrl)

	var qm := QuadMesh.new()
	qm.size = PANEL_SIZE
	var face := MeshInstance3D.new()
	face.name = "PanelFace"
	face.mesh = qm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_texture = _panel_vp.get_texture()
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA      # the dials ghost through with the rest
	fm.albedo_color = Color(1.0, 1.0, 1.0, INTERIOR_ALPHA)
	face.material_override = fm
	face.position = Vector3(0.0, 0.0, -0.045)
	node.add_child(face)


## The Control's draw callback: hand the panel to the HUD, which owns all the gauge drawing code.
func _draw_gauges() -> void:
	var hud: HUD = _find_hud()
	if hud == null:
		return
	hud.draw_cockpit_panel(_panel_ctrl, float(PANEL_W), float(PANEL_H))


func _find_hud() -> HUD:
	if _hud_ref == null or not is_instance_valid(_hud_ref):
		_hud_ref = get_tree().get_first_node_in_group("hud") as HUD
	return _hud_ref


# ---------------------------------------------------------------- structure around the pilot

func _build_consoles() -> void:
	for s in [-1.0, 1.0]:
		var tag: String = "L" if s < 0.0 else "R"
		_box("Console" + tag, Vector3(0.10, 0.28, 0.60), Vector3(s * 0.30, -0.40, -0.10), _mat_wall)
		# a row of switch boxes on the console top so it reads as equipment, not a plain slab
		for i in 3:
			_box("Switch%s%d" % [tag, i], Vector3(0.07, 0.04, 0.10),
				Vector3(s * 0.30, -0.275, -0.28 + float(i) * 0.18), _mat_metal)
		# a shallow trim strip along the console flank
		_box("Trim" + tag, Vector3(0.02, 0.05, 0.56), Vector3(s * 0.245, -0.44, -0.10), _mat_metal)
	# map case and a stowage pocket on the inward faces of the side walls (kept shallow so they clear the
	# 0.3 m near plane; the wall behind them is the enclosing surface)
	_box("MapCase", Vector3(0.045, 0.20, 0.16), Vector3(-0.325, -0.30, 0.28), _mat_wall)
	_box("StowageBox", Vector3(0.045, 0.12, 0.20), Vector3(0.325, -0.42, -0.30), _mat_wall)


func _build_seat_and_controls() -> void:
	# seat: pan under the pilot, a tall back behind the eye, now solid and wide enough to shut the view aft
	_box("SeatPan", Vector3(0.48, 0.10, 0.40), Vector3(0.0, -0.55, 0.22), _mat_seat)
	_box("SeatBack", Vector3(0.48, 0.68, 0.12), Vector3(0.0, -0.16, 0.38), _mat_seat, Vector3(8.0, 0.0, 0.0))
	_box("SeatHeadrest", Vector3(0.26, 0.18, 0.12), Vector3(0.0, 0.22, 0.40), _mat_seat, Vector3(8.0, 0.0, 0.0))
	# control stick: between the knees, raised and brought forward so it sits in the lower centre of the
	# default forward view instead of dropping out of frame below the panel
	_cyl("Stick", 0.022, 0.58, Vector3(0.0, -0.46, -0.33), _mat_metal, Vector3(-6.0, 0.0, 0.0))
	_box("StickGrip", Vector3(0.055, 0.10, 0.06), Vector3(0.0, -0.19, -0.37), _mat_black)
	_box("StickBase", Vector3(0.10, 0.06, 0.14), Vector3(0.0, -0.72, -0.31), _mat_metal)
	# throttle quadrant on the left console, in view to the left of the panel
	_box("ThrottleQuad", Vector3(0.07, 0.12, 0.20), Vector3(-0.26, -0.20, -0.30), _mat_metal)
	_box("ThrottleLever", Vector3(0.025, 0.10, 0.03), Vector3(-0.26, -0.14, -0.34), _mat_black, Vector3(-30.0, 0.0, 0.0))
	# rudder pedals in the footwell: low and forward, their tops peeking under the panel's lower edge
	for s in [-1.0, 1.0]:
		_box("Pedal" + ("L" if s < 0.0 else "R"), Vector3(0.15, 0.03, 0.11),
			Vector3(s * 0.12, -0.66, -0.79), _mat_metal, Vector3(-16.0, 0.0, 0.0))
	_box("PedalBar", Vector3(0.36, 0.03, 0.07), Vector3(0.0, -0.70, -0.77), _mat_metal)
	# footwell detail
	_box("FootwellRib", Vector3(0.62, 0.03, 0.05), Vector3(0.0, -0.735, -0.55), _mat_metal)


## Windscreen armour-glass frame, glare shield, canopy rails, side glazing and the rear canopy bow - the
## structure the view is framed by from inside, so the opening reads as an aircraft canopy.
func _build_framing() -> void:
	# windscreen: sill rail, top rail and two A-pillars, framing the armoured-glass opening. The sill sits
	# ~0.22 m BELOW the eye line: at -0.02 it was a full-width bar straight across the sightline, which
	# blocked the view out. The posts are lengthened to meet it, so the opening runs from the coaming up.
	_box("WindscreenSill", Vector3(0.86, 0.045, 0.035), Vector3(0.0, -0.22, WINDSCREEN_Z), _mat_frame)
	_box("WindscreenTop", Vector3(0.86, 0.045, 0.035), Vector3(0.0, 0.34, WINDSCREEN_Z), _mat_frame)
	for s in [-1.0, 1.0]:
		var tag: String = "L" if s < 0.0 else "R"
		_box("WindscreenPost" + tag, Vector3(0.045, 0.60, 0.035), Vector3(s * 0.37, 0.06, WINDSCREEN_Z), _mat_frame)
	# armoured front glass: not built - the view is meant to be clear through the cage
	# canopy rails and glazing down each side: the sill rail (in the tub) flows aft into a top rail, with a
	# glazing panel between them, so the sides read as a canopy rather than an open gap
	for s in [-1.0, 1.0]:
		var tag2: String = "L" if s < 0.0 else "R"
		_box("CanopyTopRail" + tag2, Vector3(0.04, 0.04, 1.34), Vector3(s * 0.315, 0.40, -0.31), _mat_frame)
		# strut tying the top rail down to the rear bow leg
		_box("CanopyStrut" + tag2, Vector3(0.04, 0.04, 0.40), Vector3(s * 0.33, 0.30, 0.16), _mat_frame)
	# rear canopy bow behind the head, joining the two top rails
	_box("CanopyBow", Vector3(0.70, 0.045, 0.04), Vector3(0.0, 0.40, 0.34), _mat_frame)
	for s in [-1.0, 1.0]:
		_box("BowLeg" + ("L" if s < 0.0 else "R"), Vector3(0.04, 0.34, 0.04), Vector3(s * 0.33, 0.22, 0.34), _mat_frame)


## Reflector gunsight: a mounting bracket from the glare shield, a lamp body below the sight line, a hood,
## a tinted reflector plate at eye level and a modest ring-and-cross reticle on the glass.
func _build_gunsight() -> void:
	_box("SightPost", Vector3(0.04, 0.13, 0.04), Vector3(0.0, -0.125, SIGHT_Z), _mat_metal)
	_box("SightArmL", Vector3(0.03, 0.03, 0.10), Vector3(-0.055, -0.055, SIGHT_Z), _mat_metal)
	_box("SightArmR", Vector3(0.03, 0.03, 0.10), Vector3(0.055, -0.055, SIGHT_Z), _mat_metal)
	_box("SightBody", Vector3(0.10, 0.10, 0.12), Vector3(0.0, -0.06, SIGHT_Z), _mat_metal)
	_box("SightHood", Vector3(0.14, 0.03, 0.08), Vector3(0.0, -0.005, SIGHT_Z - 0.03), _mat_black, Vector3(-24.0, 0.0, 0.0))

	var gz: float = SIGHT_Z + 0.07
	var tilt: float = 12.0
	_quad("SightGlass", Vector2(0.16, 0.13), Vector3(0.0, 0.0, gz), Vector3(tilt, 0.0, 0.0),
		ToonUtil.make_glass({"opacity": 0.14, "tint": Color(0.5, 0.68, 0.5), "rim": 0.45}))

	# reticle: a small ring (TorusMesh lies in XZ, so +90 deg about X makes its hole face the pilot) plus a
	# short cross and a centre dot
	var ring := TorusMesh.new()
	ring.inner_radius = 0.028
	ring.outer_radius = 0.031
	ring.rings = 24
	ring.ring_segments = 8
	var ri := MeshInstance3D.new()
	ri.name = "Reticle"
	ri.mesh = ring
	ri.material_override = _mat_reticle
	ri.position = Vector3(0.0, 0.0, gz - 0.002)
	ri.rotation = Vector3(deg_to_rad(90.0 + tilt), 0.0, 0.0)
	add_child(ri)

	_box("ReticleBarH", Vector3(0.08, 0.0014, 0.0014), Vector3(0.0, 0.0, gz), _mat_reticle, Vector3(tilt, 0.0, 0.0))
	_box("ReticleBarV", Vector3(0.0014, 0.08, 0.0014), Vector3(0.0, 0.0, gz), _mat_reticle, Vector3(tilt, 0.0, 0.0))
	var dm := SphereMesh.new()
	dm.radius = 0.0025
	dm.height = 0.005
	dm.radial_segments = 8
	dm.rings = 4
	var di := MeshInstance3D.new()
	di.name = "ReticleDot"
	di.mesh = dm
	di.material_override = _mat_reticle
	di.position = Vector3(0.0, 0.0, gz)
	add_child(di)


# ---------------------------------------------------------------- primitives

func _box(nm: String, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _add_box(self, nm, size, pos, mat, rot_deg)


func _panel_bar(parent: Node3D, nm: String, size: Vector3, pos: Vector3) -> MeshInstance3D:
	return _add_box(parent, nm, size, pos, _mat_frame, Vector3.ZERO)


func _add_box(parent: Node3D, nm: String, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	parent.add_child(mi)
	return mi


func _quad(nm: String, size: Vector2, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = size
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = qm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	add_child(mi)
	return mi


func _cyl(nm: String, radius: float, height: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	add_child(mi)
	return mi
