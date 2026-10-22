class_name BurningRuin
extends Node3D
## A shelled, burning building: jagged charred walls, a collapsed roof, flames and a tall black smoke plume.
## Purely scenery for action sites. Place with BurningRuin.create(seed, scale), add to the tree, set position.
## Flames/smoke live as long as this node does (FX.blaze follows it).

var _scale: float = 1.0
var _seed: int = 0
var _light: OmniLight3D
var _t: float = 0.0
var _emit: Array = []
var _glow: GroundGlow


static func create(p_seed: int, p_scale: float = 1.0) -> BurningRuin:
	var r := BurningRuin.new()
	r._seed = p_seed
	r._scale = p_scale
	return r


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	rotation.y = rng.randf() * TAU
	var w: float = rng.randf_range(7.0, 11.0) * _scale
	var d: float = rng.randf_range(5.0, 8.0) * _scale
	var wall := Color(0.30, 0.27, 0.24)
	var char_c := Color(0.07, 0.065, 0.06)
	# rubble apron
	GroundKit.box(self, Vector3(w + 3.0, 0.7, d + 3.0), Vector3(0, 0.3, 0), Color(0.22, 0.2, 0.18), Vector3(0, rng.randf_range(-8, 8), 0), false)
	# jagged surviving walls (different heights, broken tops)
	for i in 4:
		var horizontal: bool = i < 2
		var sgn: float = 1.0 if i % 2 == 0 else -1.0
		var len: float = (w if horizontal else d) * rng.randf_range(0.55, 1.0)
		var h: float = rng.randf_range(2.2, 5.2) * _scale
		var pos := Vector3(0, h * 0.5, 0)
		var size := Vector3(len, h, 0.5)
		if horizontal:
			pos.z = sgn * d * 0.5
			pos.x = rng.randf_range(-0.8, 0.8)
		else:
			pos.x = sgn * w * 0.5
			pos.z = rng.randf_range(-0.6, 0.6)
			size = Vector3(0.5, h, len)
		GroundKit.box(self, size, pos, wall)
		# sooty scorch band over the top half
		GroundKit.box(self, size * Vector3(1.02, 0.5, 1.02) + Vector3(0.04, 0, 0.04), pos + Vector3(0, h * 0.25, 0), char_c, Vector3.ZERO, false)
	# collapsed roof: tilted charred beams and a slumped slab
	for i in 5:
		var bl: float = rng.randf_range(3.5, 7.0) * _scale
		GroundKit.box(self, Vector3(0.28, 0.28, bl), Vector3(rng.randf_range(-w * 0.35, w * 0.35), rng.randf_range(0.8, 2.2), rng.randf_range(-d * 0.3, d * 0.3)),
			char_c, Vector3(rng.randf_range(-35, 35), rng.randf_range(0, 180), rng.randf_range(-25, 25)), false)
	GroundKit.box(self, Vector3(w * 0.7, 0.3, d * 0.6), Vector3(rng.randf_range(-1, 1), 1.0, rng.randf_range(-1, 1)), Color(0.12, 0.1, 0.09), Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14)), false)
	_emit = FX.blaze(self, _scale, rng.randf_range(0.8, 1.25))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.18)
	_light.light_energy = 1.4
	_light.omni_range = 26.0 * _scale
	_light.omni_attenuation = 2.0
	_light.position = Vector3(0, 3.0 * _scale, 0)
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 1800.0
	_light.distance_fade_length = 500.0
	add_child(_light)
	_glow = GroundGlow.create(self, 22.0 * _scale)


func _process(delta: float) -> void:
	_t += delta
	if _light != null:
		_light.light_energy = 1.2 + 0.5 * sin(_t * 9.0 + float(_seed % 7)) + 0.3 * sin(_t * 23.0)
	if _glow != null and fmod(_t, 0.5) < delta:
		_glow.intensity = 0.06 + 0.5 * FX.night_factor()


func _exit_tree() -> void:
	for e in _emit:
		(e as FXEmitter).stop()
