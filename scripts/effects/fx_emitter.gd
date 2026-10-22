class_name FXEmitter
extends RefCounted
## Persistent smoke / fire emitter driven by the FX autoload. Call stop() to end it.

enum Kind { COLUMN, FIRE, TRAIL_SMOKE, TRAIL_FIRE, STACK, BLAZE, PLUME, PILLAR }

var kind: int = Kind.COLUMN
var pos: Vector3
var last_pos: Vector3
var follow: Node3D
var offset: Vector3
var size: float = 4.0
var dark: float = 0.5          # 0 light grey .. 1 black (trails)
var drift: Vector3 = Vector3(2.0, 0.0, 0.8)   # STACK: how far the wind leans the plume
var aux: FXParticles           # PILLAR: pool for the flames at its foot
var remain: float = 20.0       # < 0 = until stop()
var total: float = 20.0
var active: bool = true
var _acc: float = 0.0
var _tick: int = 0


func stop() -> void:
	active = false


## Returns false when finished.
func update(delta: float, puffs: FXParticles) -> bool:
	if follow != null:
		if not is_instance_valid(follow) or not follow.is_inside_tree():
			return false
		last_pos = pos
		pos = follow.global_transform * offset
	if not active:
		return false
	var fade: float = 1.0
	if remain >= 0.0:
		remain -= delta
		if remain <= 0.0:
			return false
		fade = clampf(remain / maxf(minf(total * 0.25, 6.0), 0.1), 0.0, 1.0)
	var interval: float = 0.1
	match kind:
		Kind.COLUMN:
			interval = 0.12
		Kind.FIRE:
			interval = 0.06
		Kind.TRAIL_SMOKE:
			interval = 0.045
		Kind.TRAIL_FIRE:
			interval = 0.035
		Kind.STACK:
			interval = 0.6 if dark < 0.0 else 0.42
		Kind.BLAZE:
			interval = 0.1
		Kind.PLUME:
			interval = 0.2
		Kind.PILLAR:
			interval = 0.2
	_acc += delta
	var loops: int = 0
	while _acc >= interval and loops < 4:
		_acc -= interval
		loops += 1
		_tick += 1
		var p: Vector3 = pos
		if follow != null:
			p = pos.lerp(last_pos, clampf(_acc / maxf(delta, 0.0001), 0.0, 1.0))
		_emit(p, puffs, fade)
	return true


func _jit(s: float) -> Vector3:
	return Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))


func _emit(p: Vector3, puffs: FXParticles, fade: float) -> void:
	var s: float = size * fade
	match kind:
		Kind.COLUMN:
			puffs.spawn(p + _jit(s * 0.15), Vector3(4.0, s * 1.4, 1.5) + _jit(s * 0.2), 9.0, s * 0.5, s * 2.4,
				Color(0.13, 0.12, 0.12, 0.88 * fade), Color(0.32, 0.31, 0.3, 0.0), 1.0, 0.0, 0.2)
		Kind.FIRE:
			puffs.spawn(p + _jit(s * 0.25), Vector3(0.0, s * 1.6, 0.0) + _jit(s * 0.3), 0.75, s * 0.8, s * 0.25,
				Color(1.0, 0.82, 0.25, 1.0), Color(0.95, 0.25, 0.05, 0.0), 0.2, 0.0, 0.5)
			if _tick % 3 == 0:
				puffs.spawn(p + Vector3(0, s * 0.8, 0), Vector3(2.0, s * 1.2, 0.8) + _jit(s * 0.2), 3.0, s * 0.5, s * 1.5,
					Color(0.1, 0.1, 0.1, 0.85 * fade), Color(0.3, 0.3, 0.3, 0.0), 1.0, 0.0, 0.4)
		Kind.TRAIL_SMOKE:
			var g: float = lerpf(0.55, 0.1, dark)
			puffs.spawn(p + _jit(s * 0.1), _jit(1.2) + Vector3(0, 1.5, 0), 4.6, s * 0.45, s * 1.9,
				Color(g, g, g, 0.85), Color(g + 0.2, g + 0.2, g + 0.2, 0.0), 1.0, 0.0, 0.22)
		Kind.STACK:
			# thin pale industrial smoke: small soft puffs that rise, widen and fade into the haze
			if dark < 0.0:
				# house chimney: small bright white wisp
				puffs.spawn(p + _jit(s * 0.2), drift * 1.4 + Vector3(0.0, 3.6 * s, 0.0) + _jit(0.25), 9.0, s * 1.3, s * 4.2,
					Color(0.98, 0.98, 0.97, 0.7 * fade), Color(1.0, 1.0, 1.0, 0.0), 1.0, 0.0, 0.12)
			else:
				puffs.spawn(p + _jit(s * 0.2), drift + Vector3(0.0, 4.2 * s, 0.0) + _jit(0.3), 9.0, s * 0.9, s * 3.4,
					Color(0.68, 0.67, 0.65, 0.30 * fade), Color(0.80, 0.80, 0.79, 0.0), 1.0, 0.0, 0.15)
		Kind.BLAZE:
			# flames licking out of a burning building
			puffs.spawn(p + _jit(s * 1.2) * Vector3(1, 0.4, 1), Vector3(drift.x * 0.2, s * 2.4, drift.z * 0.2) + _jit(s * 0.35), 0.9, s * 1.5, s * 0.35,
				Color(1.0, 0.78, 0.22, 1.0), Color(0.95, 0.22, 0.04, 0.0), 0.2, 0.0, 0.5)
			if _tick % 2 == 0:
				puffs.spawn(p + Vector3(0, s * 1.5, 0) + _jit(s * 0.8), Vector3(drift.x * 0.4, s * 2.0, drift.z * 0.4) + _jit(s * 0.3), 5.5, s * 1.1, s * 2.9,
					Color(0.05, 0.05, 0.05, 0.9), Color(0.2, 0.2, 0.2, 0.0), 1.0, 0.0, 0.3)
		Kind.PLUME:
			# tall, wide black column that leans with the wind and thins into the haze
			puffs.spawn(p + _jit(s * 0.4), drift + Vector3(0.0, 6.0 + 0.9 * s, 0.0) + _jit(0.8), 22.0, s * 1.4, s * 8.5,
				Color(0.06, 0.055, 0.055, 0.9 * fade), Color(0.22, 0.21, 0.21, 0.0), 1.0, 0.0, 0.1)
		Kind.PILLAR:
			# a tall, narrow, near-black column that climbs a kilometre or more, leans with the wind and thins out at the top
			puffs.spawn(p + _jit(s * 0.12) * Vector3(1, 0.2, 1), drift * 0.35 + Vector3(0.0, 22.0 + s * 0.6, 0.0) + _jit(0.5), 44.0, s * 0.55, s * 2.9,
				Color(0.035, 0.033, 0.036, 0.97 * fade), Color(0.17, 0.17, 0.18, 0.0), 1.0, 0.0, 0.04)
			if aux != null and _tick % 2 == 0:
				aux.spawn(p + _jit(s * 0.2) * Vector3(1, 0.3, 1), Vector3(0.0, s * 1.6, 0.0) + _jit(s * 0.25), 0.8, s * 0.55, s * 0.18,
					Color(1.0, 0.78, 0.22, 1.0), Color(0.95, 0.22, 0.04, 0.0), 0.2, 0.0, 0.5)
		Kind.TRAIL_FIRE:
			puffs.spawn(p + _jit(s * 0.1), _jit(1.5), 0.35, s * 0.7, s * 0.15,
				Color(1.0, 0.8, 0.2, 1.0), Color(0.95, 0.25, 0.05, 0.0), 0.2, 0.0, 0.0)
			puffs.spawn(p + _jit(s * 0.1), _jit(1.5) + Vector3(0, 2.0, 0), 4.6, s * 0.55, s * 2.4,
				Color(0.08, 0.08, 0.08, 0.9), Color(0.3, 0.3, 0.3, 0.0), 1.0, 0.0, 0.22)
