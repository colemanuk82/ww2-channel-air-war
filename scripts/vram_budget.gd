class_name VramBudget
extends RefCounted
## How much video memory the machine has, so the keep-alive caches (terrain meshes, scenery tiles) can be sized to it:
## a big card keeps far more of the world resident (less rebuilding when you fly back over an area, fewer hitches),
## a small one keeps just a few. Godot has no total-VRAM query, so on Windows it is read once from the display
## driver's registry entry (largest adapter) and remembered in user://vram_mb.txt. WW2_VRAM_MB overrides it.

const FALLBACK_MB := 4096
const MIN_MB := 2048
static var _mb: int = 0


## Total video memory in MB (never below MIN_MB, FALLBACK_MB when it cannot be found).
static func total_mb() -> int:
	if _mb > 0:
		return _mb
	var v: int = 0
	var env: String = OS.get_environment("WW2_VRAM_MB")
	if env.is_valid_int():
		v = int(env)
	if v <= 0:
		v = _read_cached()
	if v <= 0:
		v = _query_registry()
		if v > 0:
			var f := FileAccess.open("user://vram_mb.txt", FileAccess.WRITE)
			if f != null:
				f.store_string(str(v))
	if v <= 0:
		v = FALLBACK_MB
	_mb = maxi(v, MIN_MB)
	return _mb


## Cache size factor: 1.0 on a 4 GB card, 2.0 on 8 GB, 4.0 on 16 GB (clamped 0.5 .. 6).
static func factor() -> float:
	if OS.get_environment("WW2_NO_CACHE") != "":
		return 0.0       # A/B switch: no keep-alive caches
	return clampf(float(total_mb()) / 4096.0, 0.5, 6.0)


## Video memory the renderer is using now, in MB.
static func used_mb() -> float:
	return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0


## True while there is room to keep more resident: under 70% of the card is in use.
static func has_headroom() -> bool:
	return used_mb() < float(total_mb()) * 0.70


static func _read_cached() -> int:
	var f := FileAccess.open("user://vram_mb.txt", FileAccess.READ)
	if f == null:
		return 0
	var s: String = f.get_as_text().strip_edges()
	return int(s) if s.is_valid_int() else 0


static func _query_registry() -> int:
	if OS.get_name() != "Windows":
		return 0
	var out: Array = []
	var code: int = OS.execute("reg", ["query", "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}",
			"/s", "/v", "HardwareInformation.qwMemorySize"], out, true)
	if code != 0 or out.is_empty():
		return 0
	var best: int = 0
	for line in String(out[0]).split("\n"):
		var p: PackedStringArray = line.strip_edges().split(" ", false)
		if p.size() >= 3 and p[0] == "HardwareInformation.qwMemorySize":
			var hex: String = p[p.size() - 1]
			if hex.begins_with("0x"):
				best = maxi(best, int(hex.hex_to_int() / 1048576))
	return best
