class_name TargetSpotter
extends Node
## "There it is!": when a building the player has been sent to destroy comes into view - close enough to make out,
## ahead of the camera, and not hidden by hills or cloud - a voice calls it (one of five recorded call-outs) and
## a faint red X is laid over it. The X is a Decal, so it lies on the roof and the ground around the building;
## it pulses gently and goes when the building is destroyed.
## The mode supplies the buildings through strike_targets() (ModeBase); only GroundStructures are called out.

const RANGE_M := 4500.0           # slant distance (real metres) at which a building can be picked out in daylight
const NIGHT_RANGE_K := 0.5        # ... and how much of that remains on a dark night
const VIEW_COS := 0.82            # within ~35 degrees of where the camera looks
const CHECK_EVERY := 0.25
const CLIPS := 5                  # assets/voice/mode/target/target_spotted_1..5

var mode: Node                    # the ModeBase that owns this
var _t: float = 0.0
var _clock: float = 0.0
var _last_clip: int = 0
var _test_done: bool = false
var _test_hold: float = 0.0       # --spot-test: the aircraft is held at the test pose while the scenery there loads
var _seen: Dictionary = {}        # instance id -> {"node": GroundStructure, "mark": Decal}
static var _tex: ImageTexture
static var _tex_emit: ImageTexture


func _process(delta: float) -> void:
	_clock += delta
	# the marks pulse gently every frame; dead or freed targets lose theirs
	for id in _seen.keys():
		var e: Dictionary = _seen[id]
		var mk: Variant = e.get("mark")
		var tn: Variant = e.get("node")
		if mk == null or not is_instance_valid(mk):
			continue
		if tn == null or not is_instance_valid(tn) or bool((tn as Node).get("is_dead")):
			(mk as Node).queue_free()
			e["mark"] = null
			continue
		(mk as Decal).modulate.a = 0.42 + 0.14 * sin(_clock * 2.4)
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK_EVERY
	if mode == null or not is_instance_valid(mode) or not bool(mode.get("running")) or not mode.has_method("strike_targets"):
		return
	var pv: Variant = mode.get("player")
	if pv == null or not is_instance_valid(pv):
		return
	var pl: Aircraft = pv as Aircraft
	if pl == null or pl.state != Aircraft.State.ALIVE:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	if _test_hold > 0.0 or (not _test_done and "--spot-test" in OS.get_cmdline_user_args()):
		_spot_test(pl)
		return
	var range_m: float = RANGE_M * lerpf(NIGHT_RANGE_K, 1.0, clampf(TimeOfDay.light_level, 0.0, 1.0))
	for tv in mode.call("strike_targets"):
		if tv == null or not is_instance_valid(tv) or not (tv is GroundStructure):
			continue
		var t: GroundStructure = tv
		if t.is_dead or _seen.has(t.get_instance_id()):
			continue
		if _in_sight(t, pl, cam, range_m):
			_spotted(t, pl)
			break          # one call at a time


## Debug (--spot-test): put the player 3.6 km short of the first strike building, 400 m up and heading for it.
func _spot_test(pl: Aircraft) -> void:
	for tv in mode.call("strike_targets"):
		if tv is GroundStructure and is_instance_valid(tv):
			if not _test_done:
				_test_done = true
				_test_hold = 75.0
			_test_hold -= CHECK_EVERY
			var tp: Vector3 = (tv as Node3D).global_position
			var from: Vector3 = tp + Vector3(-1500.0, 0.0, 0.0)
			from.y = GroundKit.ground_y(from.x, from.z) + 300.0 * WorldCoords.VERTICAL_SCALE
			var to: Vector3 = tp - from
			pl.reset_pose(from, rad_to_deg(atan2(to.x, -to.z)), true, 100.0)
			if _test_hold <= 0.0:
				print("[spotter] test pose released ", from, " -> ", tp)
			return


func _in_sight(t: GroundStructure, pl: Aircraft, cam: Camera3D, range_m: float) -> bool:
	var top: Vector3 = t.global_position + Vector3(0.0, maxf(t.hit_radius * 0.3, 6.0), 0.0)
	var d: Vector3 = top - pl.global_position
	var slant: float = Vector3(d.x, d.y / WorldCoords.VERTICAL_SCALE, d.z).length()
	if slant > range_m:
		return false
	var to: Vector3 = top - cam.global_position
	if to.length() < 1.0:
		return false
	var on_screen: bool = cam.is_position_in_frustum(top) and (-cam.global_transform.basis.z).dot(to.normalized()) >= VIEW_COS
	if not on_screen and not _bomb_aimer_sees(pl, top):
		return false
	var cf: CloudField = WeatherManager.cloud_field
	if cf != null and cf.blocks_los(cam.global_position, top):
		return false
	return not _terrain_blocks(cam.global_position, top)


## A bomber's nose glazing: the bomb aimer looks forward and down (a cone ~50 degrees round a line 45 degrees
## below the nose), so a target coming up under the nose counts even when the camera is not pointed at it.
func _bomb_aimer_sees(pl: Aircraft, top: Vector3) -> bool:
	if pl.stats == null or not AircraftCatalog.is_bomber(pl.stats.id):
		return false
	var fwd: Vector3 = pl.get_forward()
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.1:
		return false
	var look: Vector3 = (flat.normalized() + Vector3.DOWN).normalized()
	var d: Vector3 = top - pl.global_position
	d.y /= WorldCoords.VERTICAL_SCALE          # true angles, not the stretched vertical
	return look.dot(d.normalized()) > 0.64


## A hill between the eye and the building: sample the ground along the sight line (the last stretch is the
## building's own surroundings, which are allowed to rise a little above its base).
func _terrain_blocks(a: Vector3, b: Vector3) -> bool:
	for i in range(1, 16):
		var k: float = float(i) / 16.0
		if k > 0.94:
			break
		var p: Vector3 = a.lerp(b, k)
		if GroundKit.ground_y(p.x, p.z) > p.y + 4.0:
			return true
	return false


func _spotted(t: GroundStructure, pl: Aircraft) -> void:
	var bomber: bool = pl.stats != null and AircraftCatalog.is_bomber(pl.stats.id)
	# one of the recorded call-outs in assets/voice/mode/target/, at random (never the same one twice running)
	var n: int = randi_range(1, CLIPS)
	if n == _last_clip:
		n = n % CLIPS + 1
	_last_clip = n
	Radio.say("Bomb Aimer" if bomber else "Wingman", "There it is!", Radio.Kind.FRIENDLY, 0.0, "mode/target/target_spotted_%d" % n, true)
	var mk: Decal = _make_mark(t)
	_seen[t.get_instance_id()] = {"node": t, "mark": mk}
	BlackBox.note("target in sight: %s" % (t.display_name if t.display_name != "" else t.name))
	print("[spotter] target in sight: %s at %s" % [t.name, t.global_position])
	# debug: --spot-shot=<png> saves a frame 2 s after the call and quits (hidden test renders)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spot-shot="):
			var path: String = arg.substr(12)
			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				get_viewport().get_texture().get_image().save_png(path)
				print("[spotter] shot ", path)
				get_tree().quit())


## The faint red X: projected straight down over the building's footprint.
func _make_mark(t: GroundStructure) -> Decal:
	var s: float = clampf(t.hit_radius * 2.6, 24.0, 200.0)
	var dc := Decal.new()
	dc.name = "TargetMark"
	dc.texture_albedo = _cross_texture()
	dc.texture_emission = _cross_texture(true)   # black outside the strokes, or the whole square would glow
	dc.emission_energy = 0.5          # just enough to read at dusk; well below the bloom threshold
	dc.modulate = Color(1.0, 0.16, 0.10, 0.5)
	dc.albedo_mix = 1.0
	dc.size = Vector3(s, 160.0, s)    # tall enough to reach the roof and the ground (world units, vertical x2)
	dc.upper_fade = 0.05
	dc.lower_fade = 0.05
	dc.cull_mask = 0xFFFFF
	t.add_child(dc)
	dc.position = Vector3(0.0, 60.0, 0.0)
	dc.global_rotation = Vector3(0.0, t.global_rotation.y, 0.0)
	return dc


static func _cross_texture(emit: bool = false) -> ImageTexture:
	if not emit and _tex != null:
		return _tex
	if emit and _tex_emit != null:
		return _tex_emit
	var n: int = 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half: float = float(n) * 0.5
	for y in n:
		for x in n:
			var u: float = (float(x) + 0.5 - half) / half
			var v: float = (float(y) + 0.5 - half) / half
			var r: float = maxf(absf(u), absf(v))
			# two diagonal strokes, soft-edged, fading toward the ends
			var dd: float = minf(absf(u - v), absf(u + v)) * 0.7071
			var stroke: float = 1.0 - smoothstep(0.035, 0.065, dd)
			var ends: float = 1.0 - smoothstep(0.72, 0.9, r)
			var a: float = stroke * ends
			img.set_pixel(x, y, Color(a, a, a, 1.0) if emit else Color(1.0, 1.0, 1.0, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	if emit:
		_tex_emit = tex
	else:
		_tex = tex
	return tex
