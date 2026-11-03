extends Node
## Black box (autoload "BlackBox"): a crash recorder. The engine's own log is buffered, so the last seconds before a
## hard crash are usually lost. This writes its own file, user://logs/blackbox_<time>.txt, and flushes every line
## to disk at once, so whatever it recorded survives the crash.
##
## Every 5 seconds: frame rate and worst frame time, memory, object / node / resource counts, orphan nodes, physics
## and render load, the number of aircraft, effects and projectiles, the player's state and position, the weather
## and the war date. Between those lines: breadcrumbs (sortie start, deaths, weather changes, warnings) and every
## script error or warning the engine reports, with its script backtrace where the build gives one.
##
## A steady climb in memory or object counts over the minutes before a crash points at a leak; a sudden jump points
## at whatever happened in that interval. When the game quits normally the file ends with "CLEAN EXIT". On the next
## start, a file without it is kept as blackbox_CRASH_<time>.txt (the last 6 are kept) and the game says so.

const KEEP := 6
const EVERY := 5.0

var _f: FileAccess = null
var _path: String = ""
var _t: float = 0.0
var _start_ms: int = 0
var _worst_ms: float = 0.0
var _frames: int = 0
var _err_count: int = 0
var _err_seen: Dictionary = {}            # message -> times seen (repeats are counted, not written again)
var crashed_last_time: String = ""        # path of the previous session's file when it did not end cleanly
var _mx := Mutex.new()                    # loggers call in from any thread


class BBLogger extends Logger:
	var box: Node
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var bt: String = ""
		for sb in script_backtraces:
			if sb != null and not sb.is_empty():
				bt += sb.format(2, 3)
		# written at once (not deferred): the engine's crash handler reports through here, and after a crash there is
		# no next frame
		box._on_engine_error("%s %s" % ["WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR", rationale if rationale != "" else code], "%s:%d %s" % [file, line, function], bt)
	func _log_message(message: String, error: bool) -> void:
		# stderr text: the crash handler's "Program crashed" banner and its native backtrace (named with the .pdb)
		if error:
			box._raw(message.strip_edges())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_ms = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute("user://logs")
	_check_last_session()
	var stamp: String = Time.get_datetime_string_from_system().replace(":", ".")
	_path = "user://logs/blackbox_%s.txt" % stamp
	_f = FileAccess.open(_path, FileAccess.WRITE)
	_line("BLACK BOX  game v%s  engine %s  %s" % [ProjectSettings.get_setting("application/config/version", "?"), Engine.get_version_info().get("string", ""), Time.get_datetime_string_from_system()])
	_line("system: %s %s | cpu %s x%d | gpu %s (%s) | ram %s" % [OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), _mb(OS.get_memory_info().get("physical", 0))])
	_line("screen %s  window %s  vsync %d  max_fps %d" % [DisplayServer.screen_get_size(), DisplayServer.window_get_size(), DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	OS.add_logger(_make_logger())
	_prune()


func _make_logger() -> Logger:
	var lg := BBLogger.new()
	lg.box = self
	return lg


## The last session's file never got its CLEAN EXIT line: keep it as a crash report.
func _check_last_session() -> void:
	var d := DirAccess.open("user://logs")
	if d == null:
		return
	var newest: String = ""
	for fn in d.get_files():
		if fn.begins_with("blackbox_") and not fn.begins_with("blackbox_CRASH_") and fn > newest:
			newest = fn
	if newest == "":
		return
	var txt: String = FileAccess.get_file_as_string("user://logs/" + newest)
	if txt.contains("CLEAN EXIT"):
		return
	var to: String = newest.replace("blackbox_", "blackbox_CRASH_")
	d.rename(newest, to)
	crashed_last_time = ProjectSettings.globalize_path("user://logs/" + to)
	push_warning("BlackBox: the last session ended without a clean exit; its record is " + crashed_last_time)


func _prune() -> void:
	var d := DirAccess.open("user://logs")
	if d == null:
		return
	for prefix in ["blackbox_CRASH_", "blackbox_2"]:
		var list: Array = []
		for fn in d.get_files():
			if fn.begins_with(prefix):
				list.append(fn)
		list.sort()
		while list.size() > KEEP:
			d.remove(String(list.pop_front()))


func _line(s: String) -> void:
	_mx.lock()
	if _f != null:
		var secs: float = float(Time.get_ticks_msec() - _start_ms) / 1000.0
		_f.store_line("%7.1f  %s" % [secs, s])
		_f.flush()                  # straight to disk: a crash can't lose it
	_mx.unlock()


func _raw(s: String) -> void:
	if s != "":
		_line("! " + s)


## A breadcrumb from anywhere: BlackBox.note("sortie start free spitfire")
func note(s: String) -> void:
	_line("> " + s)


func _on_engine_error(msg: String, where: String, bt: String) -> void:
	_mx.lock()
	_err_count += 1
	var n: int = int(_err_seen.get(msg, 0)) + 1
	_err_seen[msg] = n
	_mx.unlock()
	# the first three of a kind in full, then every 500th as a count (a per-frame error must not flood the file)
	if n <= 3 or n % 500 == 0:
		_line("%s  [%s] (x%d)" % [msg, where, n])
		if bt != "" and n <= 3:
			for l in bt.strip_edges().split("\n"):
				_line("      " + l)


func _process(delta: float) -> void:
	_frames += 1
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	_t += delta
	if _t < EVERY:
		return
	_t = 0.0
	_snapshot()
	_worst_ms = 0.0
	_frames = 0


func _snapshot() -> void:
	var P := Performance
	# process memory is only counted in debug builds: in a release build the PC's free RAM is the leak gauge
	var mem: float = P.get_monitor(P.MEMORY_STATIC)
	var free_ram: float = float(OS.get_memory_info().get("available", 0))
	var vmem: float = P.get_monitor(P.RENDER_VIDEO_MEM_USED)
	var s: String = "fps %d worst %.0fms | mem %s free %s vram %s | obj %d nodes %d orphan %d res %d | draws %d prims %dk | phys %d | " % [
		int(P.get_monitor(P.TIME_FPS)), _worst_ms, _mb(mem), _mb(free_ram), _mb(vmem),
		int(P.get_monitor(P.OBJECT_COUNT)), int(P.get_monitor(P.OBJECT_NODE_COUNT)), int(P.get_monitor(P.OBJECT_ORPHAN_NODE_COUNT)), int(P.get_monitor(P.OBJECT_RESOURCE_COUNT)),
		int(P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(P.get_monitor(P.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		int(P.get_monitor(P.PHYSICS_3D_ACTIVE_OBJECTS))]
	var tree := get_tree()
	if tree != null:
		var air: int = tree.get_nodes_in_group("aircraft").size()
		s += "aircraft %d particles %d audio %d | " % [air, _count_class(tree.root, "GPUParticles3D"), _count_playing_audio(tree.root)]
		var pl: Node = _player()
		if pl != null:
			var p: Vector3 = (pl as Node3D).global_position
			s += "player %s %s alt %dm spd %dkm/h at (%d, %d, %d) | " % [String(pl.get("stats").get("id")) if pl.get("stats") != null else "?", ["alive", "dying", "dead"][clampi(int(pl.get("state")), 0, 2)], int(p.y / WorldCoords.VERTICAL_SCALE), int(float(pl.get("speed")) * 3.6), int(p.x), int(p.y), int(p.z)]
	s += "wx %s rain %.2f | date %s | errors %d" % [WeatherManager.current, WeatherManager.rain, EraClock.current(), _err_count]
	_line(s)


func _player() -> Node:
	for n in get_tree().get_nodes_in_group("aircraft"):
		if n.get("player_controlled"):
			return n
	return null


## Cheap enough every 5 s: the tree is walked once.
func _count_class(root: Node, cls: String) -> int:
	return root.find_children("*", cls, true, false).size()


func _count_playing_audio(root: Node) -> int:
	var n: int = 0
	for a in root.find_children("*", "AudioStreamPlayer3D", true, false):
		if (a as AudioStreamPlayer3D).playing:
			n += 1
	return n


static func _mb(b: float) -> String:
	return "%dMB" % int(b / 1048576.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if _f != null:
			_snapshot()
			_line("CLEAN EXIT")
			_mx.lock()
			_f.close()
			_f = null
			_mx.unlock()
