extends Node
## Global game state and settings (autoload "GameState"). Also registers the InputMap.

signal outlines_changed(enabled: bool)
signal settings_changed

var outlines_enabled: bool = true:
	set(v):
		outlines_enabled = v
		RenderingServer.global_shader_parameter_set("outline_enabled", 1.0 if v else 0.0)
		outlines_changed.emit(v)

var start_airborne: bool = false
var start_airfield: String = "manston"  # "manston" or "hawkinge"
var spawn_point: Dictionary = {}          # free-flight airborne spawn (SpawnPoints entry); empty = use start_airfield
var auto_level: bool = false
var invert_pitch: bool = false
var show_hud: bool = true
var reduce_shake: bool = false   # calmer camera: gust, engine and hit shake cut to a quarter (Options > Camera shake)
var colorblind: bool = false     # red/green friend-foe colours swapped for blue/yellow (Options > Colour-blind colours)
var radio_subtitles: bool = false  # radio call log on screen (Options > Radio subtitles)
var radio_static: bool = true   # background radio hiss / crackle between calls
const TIME_SPEEDS := [0.0, 1.0, 6.0, 12.0, 30.0, 120.0]
const TIME_SPEED_NAMES := ["Frozen", "Real time", "6x", "12x", "30x", "120x"]
var time_speed: int = 2        # day/night cycle speed (index into TIME_SPEEDS; Options > Time passes)
var completed_missions: Array = []   # ids of historical missions the player has completed (shown as [DONE] in the list)
# Audio mixer (Options > Audio): 0..1 per category, persisted in settings.cfg [audio]; AudioManager reads them from here.
var vol_master: float = 1.0
var vol_fx: float = 1.0
var vol_engine: float = 1.0
var vol_radio: float = 1.0
var vol_music: float = 0.7
# Music managers (Options > Music). Each playlist entry is a resource path: a track that ships under
# res://assets/music/ or an imported copy under user://music/. Both lists and the per-manager selection
# live here and are persisted in settings.cfg [music]; the imported files themselves are user data.
var menu_music_playlist: Array = []
var ingame_music_playlist: Array = []
var menu_music_configured: bool = false     # false = follow the tracks shipped on disk (fresh install)
var ingame_music_configured: bool = false
var menu_music_shuffle: bool = true
var ingame_music_shuffle: bool = true
var menu_music_current: String = ""         # the track a manager should start on ("" = pick freely)
var ingame_music_current: String = ""
var show_hints: bool = true    # control hints panel on the right of the HUD (Options > Control hints)
var engine_heat_on: bool = true   # Options > Realism: engine overheating (player and AI)
var g_effects_on: bool = true     # Options > Realism: G grey-out, blackout and G-LOC (player and AI)
var player_heal: bool = true   # the player's aircraft very slowly repairs itself in flight
var show_pitch_ladder: bool = false   # pitch ladder drawn in the HUD
var player_side: String = "Allies"
var era_date: String = ""          # ISO date of the current mission / campaign day ("" = no date): decides which airfields are liberated
var quality: int = 1  # 0 low, 1 medium, 2 high
var shadows_enabled: bool = true
var msaa_level: int = 2      # 0 = off, 2 = 2x, 4 = 4x
var post_fx: int = 2         # post effects: 0 off, 1 medium (filmic tonemap, bloom, grade), 2 high (adds ambient occlusion, sun scatter)
var view_distance: int = 1   # 0 near, 1 normal, 2 far
var cloud_detail: int = 1    # volumetric clouds: 0 low, 1 medium, 2 high (raymarch step size / sample count)
var fullscreen: bool = true
var ui_scale: float = 1.0
var paused: bool = false

# ---- simulation time warp ("]" / "[" in flight): the map is real-scale, so a multiplier on the whole
# simulation fast-forwards the long empty transits. It is NOT the day/night clock (time_speed / TIME_SPEEDS is
# separate and stays independent) and it is deliberately not persisted: every session starts at 1x and main.gd
# resets it on pause, on the results screen and when leaving to the menu.
const SIM_WARPS := [1, 2, 4]      # the simulation does not hold together above 4x, so that is the top of the ladder
const SIM_WARP_NAMES := ["1x", "2x", "4x"]
var sim_warp: int = 1        # current multiplier from SIM_WARPS; main.gd applies it as Engine.time_scale


## Index of the current warp multiplier in SIM_WARPS (0 when sim_warp is not on the ladder).
func sim_warp_index() -> int:
	return maxi(SIM_WARPS.find(sim_warp), 0)


## Step the warp one notch up (dir = 1) or down (dir = -1), clamped to SIM_WARPS (so it can never exceed 4x).
func step_sim_warp(dir: int) -> int:
	sim_warp = int(SIM_WARPS[clampi(sim_warp_index() + dir, 0, SIM_WARPS.size() - 1)])
	return sim_warp


## Snap the warp onto the SIM_WARPS ladder, never above the top one. Returns the multiplier.
func snap_sim_warp(mult: int) -> int:
	var i: int = 0
	for k in SIM_WARPS.size():
		if int(SIM_WARPS[k]) <= mult:
			i = k
	sim_warp = int(SIM_WARPS[i])
	return sim_warp


## Back to real time: the warp must never survive a pause, the results screen, a restart or the menu.
func reset_sim_warp() -> void:
	sim_warp = 1


# ---- temporal upscaling (NVIDIA DLSS on the RTX Godot fork, AMD FSR 2 as the fallback) and frame generation
enum Upscaler { OFF, FSR2, DLSS }
const UPSCALE_SCALES := [0.667, 0.58, 0.5, 0.333]     # Quality, Balanced, Performance, Ultra Performance
const UPSCALE_NAMES := ["Quality", "Balanced", "Performance", "Ultra Performance"]
var upscaler: int = -1             # -1 = not chosen yet: DLSS when the GPU/engine supports it, otherwise FSR 2
var upscale_quality: int = 0
var frame_gen: bool = false
var vsync_on: bool = true
var fps_cap: int = 0                                  # 0 = unlimited; otherwise frames per second
const FPS_CAPS := [0, 30, 60, 120, 144, 165, 240]    # Options > Render "Frame rate limit" presets

# Gamepad remapping (Options > Controls): _pad_defaults holds the built-in joypad events, pad_bindings any
# player override (encoded), persisted under [input] in settings.cfg.
const UNBOUND := "unbound"        # pad_bindings value for an action deliberately left with no pad button
var _pad_defaults: Dictionary = {}
var pad_bindings: Dictionary = {}


func _ready() -> void:
	_setup_input()
	_load_settings()
	_debug_upscaler_args()
	RenderingServer.global_shader_parameter_set("outline_enabled", 1.0 if outlines_enabled else 0.0)
	ThemeDB.fallback_font = UIKit.font()


# ---------------------------------------------------------------- graphics settings
const SETTINGS_PATH := "user://settings.cfg"
const VIEW_SCALES := [0.7, 1.0, 1.35]
const UI_SCALES := [0.85, 1.0, 1.25, 1.5]


## True only on the NVIDIA RTX engine fork (Streamline built in). The standard Godot build has no DLSS, no frame
## generation and no use for the DLSS download, so those options are hidden there.
func engine_has_streamline() -> bool:
	return Engine.has_singleton("Streamline")


## True when this build is the DLSS-enabled engine AND Streamline reports DLSS on this GPU.
func dlss_supported() -> bool:
	if not Engine.has_singleton("Streamline"):
		return false
	return bool(Engine.get_singleton("Streamline").call("get_capability", 0))      # STREAMLINE_CAPABILITY_DLSS


func framegen_supported() -> bool:
	if not Engine.has_singleton("Streamline"):
		return false
	return bool(Engine.get_singleton("Streamline").call("get_capability", 1))      # STREAMLINE_CAPABILITY_DLSS_G


## The upscaler actually used: the chosen one, with DLSS falling back to FSR 2 when it is unavailable.
func effective_upscaler() -> int:
	var u: int = upscaler
	if u < 0:
		u = Upscaler.DLSS if dlss_supported() else Upscaler.FSR2
	if u == Upscaler.DLSS and not dlss_supported():
		u = Upscaler.FSR2
	return u


## True for GPUs that will struggle with the full-quality renderer: Intel / generic integrated graphics.
static func is_weak_gpu(adapter: String) -> bool:
	var n: String = adapter.to_lower().replace("(tm)", "").replace("(r)", "")
	if n.contains("nvidia") or n.contains("geforce") or n.contains("rtx") or n.contains("gtx") or n.contains("quadro"):
		return false
	if n.contains("radeon rx") or n.contains("radeon pro") or n.contains("arc a") or n.contains("arc b"):
		return false
	return n.contains("intel") or n.contains("uhd") or n.contains("iris") or n.contains("hd graphics") \
		or n.contains("vega 8") or n.contains("vega 7") or n.contains("vega 6") or n.contains("radeon graphics") \
		or n.contains("llvmpipe") or n.contains("software") or n.contains("basic render")


## First launch only (no settings file yet): pick the Low preset and FSR 2 upscaling on weak / integrated GPUs.
func _first_run_autotune() -> void:
	var name: String = RenderingServer.get_video_adapter_name()
	print("[gfx] first run, adapter: ", name)
	if is_weak_gpu(name):
		quality = 0
		outlines_enabled = false
		shadows_enabled = false
		msaa_level = 0
		view_distance = 0
		post_fx = 0
		cloud_detail = 0
		upscaler = Upscaler.FSR2
		upscale_quality = 1
		print("[gfx] weak GPU detected: Low preset + FSR 2")


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		_first_run_autotune()
		return
	outlines_enabled = cf.get_value("gfx", "outlines", outlines_enabled)
	shadows_enabled = cf.get_value("gfx", "shadows", shadows_enabled)
	msaa_level = int(cf.get_value("gfx", "msaa", msaa_level))
	post_fx = int(cf.get_value("gfx", "post_fx", post_fx))
	quality = int(cf.get_value("gfx", "quality", quality))
	view_distance = int(cf.get_value("gfx", "view_distance", view_distance))
	cloud_detail = clampi(int(cf.get_value("gfx", "cloud_detail", cloud_detail)), 0, 2)
	fullscreen = cf.get_value("gfx", "fullscreen", fullscreen)
	ui_scale = float(cf.get_value("gfx", "ui_scale", ui_scale))
	upscaler = int(cf.get_value("gfx", "upscaler", upscaler))
	upscale_quality = int(cf.get_value("gfx", "upscale_quality", upscale_quality))
	frame_gen = bool(cf.get_value("gfx", "frame_gen", frame_gen))
	vsync_on = bool(cf.get_value("gfx", "vsync", vsync_on))
	fps_cap = clampi(int(cf.get_value("gfx", "fps_cap", fps_cap)), 0, 1000)
	show_hints = bool(cf.get_value("ui", "show_hints", show_hints))
	player_heal = bool(cf.get_value("gameplay", "player_heal", player_heal))
	engine_heat_on = bool(cf.get_value("realism", "engine_heat", engine_heat_on))
	g_effects_on = bool(cf.get_value("realism", "g_effects", g_effects_on))
	show_pitch_ladder = bool(cf.get_value("gameplay", "pitch_ladder", show_pitch_ladder))
	completed_missions = cf.get_value("progress", "completed_missions", completed_missions)
	time_speed = clampi(int(cf.get_value("ui", "time_speed", time_speed)), 0, TIME_SPEEDS.size() - 1)
	radio_static = bool(cf.get_value("ui", "radio_static", radio_static))
	radio_subtitles = bool(cf.get_value("ui", "radio_subtitles", radio_subtitles))
	reduce_shake = bool(cf.get_value("ui", "reduce_shake", reduce_shake))
	colorblind = bool(cf.get_value("ui", "colorblind", colorblind))
	vol_master = clampf(float(cf.get_value("audio", "master", vol_master)), 0.0, 1.0)
	vol_fx = clampf(float(cf.get_value("audio", "fx", vol_fx)), 0.0, 1.0)
	vol_engine = clampf(float(cf.get_value("audio", "engine", vol_engine)), 0.0, 1.0)
	vol_radio = clampf(float(cf.get_value("audio", "radio", vol_radio)), 0.0, 1.0)
	vol_music = clampf(float(cf.get_value("audio", "music", vol_music)), 0.0, 1.0)
	menu_music_playlist = _str_array(cf.get_value("music", "menu_playlist", menu_music_playlist))
	ingame_music_playlist = _str_array(cf.get_value("music", "ingame_playlist", ingame_music_playlist))
	menu_music_configured = bool(cf.get_value("music", "menu_configured", menu_music_configured))
	ingame_music_configured = bool(cf.get_value("music", "ingame_configured", ingame_music_configured))
	menu_music_shuffle = bool(cf.get_value("music", "menu_shuffle", menu_music_shuffle))
	ingame_music_shuffle = bool(cf.get_value("music", "ingame_shuffle", ingame_music_shuffle))
	menu_music_current = str(cf.get_value("music", "menu_current", menu_music_current))
	ingame_music_current = str(cf.get_value("music", "ingame_current", ingame_music_current))
	if cf.has_section("input"):
		for k in cf.get_section_keys("input"):
			pad_bindings[k] = cf.get_value("input", k)
		_apply_pad_bindings()


func mark_mission_done(id: String) -> void:
	if id != "" and not completed_missions.has(id):
		completed_missions.append(id)
		save_settings()


func is_mission_done(id: String) -> bool:
	return completed_missions.has(id)


func mission_label(id: String, mission_name: String) -> String:
	if DatedOps.is_dated(id) and not DatedOps.is_open(id):
		return "[LOCKED: opens %s]  %s" % [DatedOps.opens_text(id), mission_name]
	var t: String = mission_name      # completed missions are tinted green in the menu list (see StartMenu), not tagged
	if DatedOps.is_dated(id):
		t += "   (dated: %s)" % DatedOps.opens_text(id)
	return t


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "outlines", outlines_enabled)
	cf.set_value("gfx", "shadows", shadows_enabled)
	cf.set_value("gfx", "msaa", msaa_level)
	cf.set_value("gfx", "post_fx", post_fx)
	cf.set_value("gfx", "quality", quality)
	cf.set_value("gfx", "view_distance", view_distance)
	cf.set_value("gfx", "cloud_detail", cloud_detail)
	cf.set_value("gfx", "fullscreen", fullscreen)
	cf.set_value("gfx", "ui_scale", ui_scale)
	cf.set_value("gfx", "upscaler", upscaler)
	cf.set_value("gfx", "upscale_quality", upscale_quality)
	cf.set_value("gfx", "frame_gen", frame_gen)
	cf.set_value("gfx", "vsync", vsync_on)
	cf.set_value("gfx", "fps_cap", fps_cap)
	cf.set_value("ui", "show_hints", show_hints)
	cf.set_value("gameplay", "player_heal", player_heal)
	cf.set_value("realism", "engine_heat", engine_heat_on)
	cf.set_value("realism", "g_effects", g_effects_on)
	cf.set_value("gameplay", "pitch_ladder", show_pitch_ladder)
	cf.set_value("progress", "completed_missions", completed_missions)
	cf.set_value("ui", "time_speed", time_speed)
	cf.set_value("ui", "radio_static", radio_static)
	cf.set_value("ui", "radio_subtitles", radio_subtitles)
	cf.set_value("ui", "reduce_shake", reduce_shake)
	cf.set_value("ui", "colorblind", colorblind)
	cf.set_value("audio", "master", vol_master)
	cf.set_value("audio", "fx", vol_fx)
	cf.set_value("audio", "engine", vol_engine)
	cf.set_value("audio", "radio", vol_radio)
	cf.set_value("audio", "music", vol_music)
	cf.set_value("music", "menu_playlist", menu_music_playlist)
	cf.set_value("music", "ingame_playlist", ingame_music_playlist)
	cf.set_value("music", "menu_configured", menu_music_configured)
	cf.set_value("music", "ingame_configured", ingame_music_configured)
	cf.set_value("music", "menu_shuffle", menu_music_shuffle)
	cf.set_value("music", "ingame_shuffle", ingame_music_shuffle)
	cf.set_value("music", "menu_current", menu_music_current)
	cf.set_value("music", "ingame_current", ingame_music_current)
	for a in pad_bindings.keys():
		cf.set_value("input", a, pad_bindings[a])
	cf.save(SETTINGS_PATH)


# ---------------------------------------------------------------- music playlists (Options > Music)
## Effective playlist for a manager ("menu" or "ingame"): the stored list once the player has edited it,
## otherwise every shipped track found on disk, so a fresh install and newly shipped tracks are picked up.
func music_playlist(which: String) -> Array:
	if which == "ingame":
		return ingame_music_playlist.duplicate() if ingame_music_configured else default_music_playlist("ingame")
	return menu_music_playlist.duplicate() if menu_music_configured else default_music_playlist("menu")


## The tracks that ship with the game for a manager (never modified; the fallback playlist).
func default_music_playlist(which: String) -> Array:
	return MenuMusic.discover_in("res://assets/music/ingame/" if which == "ingame" else "res://assets/music/")


func music_shuffle(which: String) -> bool:
	return ingame_music_shuffle if which == "ingame" else menu_music_shuffle


func set_music_shuffle(which: String, on: bool) -> void:
	if which == "ingame":
		ingame_music_shuffle = on
	else:
		menu_music_shuffle = on
	save_settings()


func music_current(which: String) -> String:
	return ingame_music_current if which == "ingame" else menu_music_current


func set_music_current(which: String, path: String) -> void:
	if which == "ingame":
		ingame_music_current = path
	else:
		menu_music_current = path
	save_settings()


## Replace a manager's playlist and mark it as edited by the player (so it is no longer auto-discovered).
func set_music_playlist(which: String, list: Array) -> void:
	if which == "ingame":
		ingame_music_playlist = list.duplicate()
		ingame_music_configured = true
	else:
		menu_music_playlist = list.duplicate()
		menu_music_configured = true
	save_settings()


## Add a track to a manager's playlist (no-op when it is already there).
func add_music_track(which: String, path: String) -> void:
	var list: Array = music_playlist(which)
	if not list.has(path):
		list.append(path)
		set_music_playlist(which, list)


## Remove a track from a manager's playlist; clears the selection when it was the current track.
func remove_music_track(which: String, path: String) -> void:
	var list: Array = music_playlist(which)
	list.erase(path)
	set_music_playlist(which, list)
	if music_current(which) == path:
		set_music_current(which, "")


static func _str_array(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for e in v:
			out.append(str(e))
	return out


## Change one graphics setting, apply it live and remember it.
func set_graphic(key: String, value: Variant) -> void:
	match key:
		"outlines":
			outlines_enabled = bool(value)
		"shadows":
			shadows_enabled = bool(value)
		"player_heal":
			player_heal = bool(value)
		"pitch_ladder":
			show_pitch_ladder = bool(value)
		"msaa":
			msaa_level = int(value)
		"post_fx":
			post_fx = clampi(int(value), 0, 2)
		"quality":
			quality = int(value)
		"view_distance":
			view_distance = int(value)
		"cloud_detail":
			cloud_detail = clampi(int(value), 0, 2)
		"fullscreen":
			fullscreen = bool(value)
		"ui_scale":
			ui_scale = float(value)
		"upscaler":
			upscaler = int(value)
		"upscale_quality":
			upscale_quality = int(value)
		"frame_gen":
			frame_gen = bool(value)
		"vsync":
			vsync_on = bool(value)
		"fps_cap":
			fps_cap = clampi(int(value), 0, 1000)
		"show_hints":
			show_hints = bool(value)
		"time_speed":
			time_speed = clampi(int(value), 0, TIME_SPEEDS.size() - 1)
		"radio_static":
			radio_static = bool(value)
		"radio_subtitles":
			radio_subtitles = bool(value)
		"engine_heat":
			engine_heat_on = bool(value)
		"g_effects":
			g_effects_on = bool(value)
		"reduce_shake":
			reduce_shake = bool(value)
		"colorblind":
			colorblind = bool(value)
	apply_graphics()
	save_settings()
	settings_changed.emit()


## Friend / foe colours for people who confuse red and green: red becomes blue, green becomes yellow.
func accessible_color(c: Color) -> Color:
	if not colorblind:
		return c
	if c.r > 0.7 and c.g < 0.5 and c.b < 0.5:
		return Color(0.2, 0.62, 1.0, c.a)
	if c.g > c.r and c.g > c.b:
		return Color(1.0, 0.9, 0.25, c.a)
	return c


## Apply a quality preset (also used to apply the loaded settings at startup).
func apply_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	match quality:
		0:
			outlines_enabled = false
			shadows_enabled = false
			msaa_level = 0
			view_distance = 0
			post_fx = 0
			cloud_detail = 0
		1:
			outlines_enabled = true
			shadows_enabled = true
			msaa_level = 2
			view_distance = 1
			post_fx = 1
			cloud_detail = 1
		2:
			outlines_enabled = true
			shadows_enabled = true
			msaa_level = 4
			view_distance = 2
			post_fx = 2
			cloud_detail = 2
	apply_graphics()
	save_settings()
	settings_changed.emit()


## Push the current settings to the running game (call after the world/light/camera exist).
func apply_graphics() -> void:
	RenderingServer.global_shader_parameter_set("outline_enabled", 1.0 if outlines_enabled else 0.0)
	Scatter.vis_scale = float(VIEW_SCALES[clampi(view_distance, 0, 2)])
	var tod0: Node = get_tree().root.get_node_or_null("TimeOfDay")
	if tod0 != null:
		tod0.set("time_scale", float(TIME_SPEEDS[clampi(time_speed, 0, TIME_SPEEDS.size() - 1)]) / 3600.0)   # game hours per real second
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap
	var win: Window = get_window()
	if win:
		win.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		win.content_scale_factor = ui_scale
		var vp: Viewport = win
		_apply_upscaler(vp)
		match msaa_level:
			0:
				vp.msaa_3d = Viewport.MSAA_DISABLED
			2:
				vp.msaa_3d = Viewport.MSAA_2X
			4:
				vp.msaa_3d = Viewport.MSAA_4X
			8:
				vp.msaa_3d = Viewport.MSAA_8X
		if effective_upscaler() != Upscaler.OFF:
			vp.msaa_3d = Viewport.MSAA_DISABLED      # DLSS / FSR 2 do their own temporal anti-aliasing
	var tod: Node = get_tree().root.get_node_or_null("TimeOfDay")
	if tod and tod.get("sun") != null:
		var sun: DirectionalLight3D = tod.get("sun")
		if sun:
			sun.shadow_enabled = shadows_enabled
		if tod.has_method("apply_post"):
			tod.call("apply_post", post_fx)
	var wm: Node = get_tree().root.get_node_or_null("WeatherManager")
	if wm and wm.get("cloud_field") != null and wm.get("cloud_field").has_method("set_detail"):
		wm.get("cloud_field").call("set_detail", cloud_detail)
	var terr: Node = get_tree().get_first_node_in_group("terrain")
	if terr and terr.has_method("set_view_scale"):
		terr.call("set_view_scale", float(VIEW_SCALES[clampi(view_distance, 0, 2)]))


var radio_voice: bool = false     # computer text-to-speech for calls with no recorded clip (off: recorded voices or text only)


func toggle_outlines() -> void:
	outlines_enabled = not outlines_enabled


func _key(action: String, keycode: Key) -> void:
	_add_event(action, _make_key(keycode))


func _make_key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	return e


func _add_event(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	InputMap.action_add_event(action, ev)


func _axis(action: String, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	_add_event(action, e)
	_record_default(action, e)


func _btn(action: String, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	_add_event(action, e)
	_record_default(action, e)


func _mouse(action: String, button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	_add_event(action, e)


func _record_default(action: String, e: InputEvent) -> void:
	if not _pad_defaults.has(action):
		_pad_defaults[action] = []
	(_pad_defaults[action] as Array).append(e)


func _setup_input() -> void:
	# Flight keyboard
	_key("pitch_down", KEY_W)
	_key("pitch_up", KEY_S)
	_key("roll_left", KEY_A)
	_key("roll_right", KEY_D)
	_key("yaw_left", KEY_Q)
	_key("yaw_right", KEY_E)
	_key("throttle_up", KEY_SHIFT)
	_key("throttle_down", KEY_CTRL)
	_key("fire", KEY_SPACE)
	_key("weapon_toggle", KEY_X)
	_key("weapon_toggle", KEY_B)
	_key("gear", KEY_G)
	_key("camera", KEY_C)
	_key("padlock", KEY_K)       # target view: aim the camera at the nearest aircraft
	_key("boost", KEY_TAB)
	_key("brake", KEY_V)
	_key("flaps", KEY_F)
	_key("bail_out", KEY_J)    # hold: bail out of the aircraft (see scripts/bail_out.gd)
	_key("bombsight", KEY_N)
	_key("gunner_view", KEY_L)   # bombers: step through the defensive gun positions (autopilot while gunning)
	_key("tac_map", KEY_M)
	_key("sight_alt_up", KEY_UP)
	_key("sight_alt_down", KEY_DOWN)
	_key("sight_spd_up", KEY_RIGHT)
	_key("sight_spd_down", KEY_LEFT)
	# Radio orders to friendly aircraft (keyboard)
	_key("radio_form", KEY_1)
	_key("radio_attack", KEY_2)
	_key("radio_cover", KEY_3)
	_key("radio_rtb", KEY_4)
	_key("radio_join", KEY_5)      # accept an offer to join a passing flight (free flight)
	# Gamepad
	_axis("pitch_down", JOY_AXIS_LEFT_Y, -1.0)
	_axis("pitch_up", JOY_AXIS_LEFT_Y, 1.0)
	_axis("roll_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("roll_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("throttle_up", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis("throttle_down", JOY_AXIS_TRIGGER_LEFT, 1.0)   # left trigger: throttle down
	_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)           # left trigger: wheel brake too (both at once)
	# Right stick = free-look camera (yaw is on keyboard Q/E)
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_btn("fire", JOY_BUTTON_A)
	_btn("weapon_toggle", JOY_BUTTON_B)
	_btn("gear", JOY_BUTTON_Y)
	_btn("camera", JOY_BUTTON_X)
	_btn("boost", JOY_BUTTON_RIGHT_SHOULDER)
	_btn("padlock", JOY_BUTTON_LEFT_SHOULDER)   # hold to point the view at the nearest aircraft
	_btn("sight_cycle", JOY_BUTTON_BACK)         # bomber: flight -> bombsight -> chart -> flight
	_btn("sight_alt_up", JOY_BUTTON_DPAD_UP)     # bombsight dials: up/down altitude, left/right speed
	_btn("sight_alt_down", JOY_BUTTON_DPAD_DOWN)
	_btn("sight_spd_down", JOY_BUTTON_DPAD_LEFT)
	_btn("sight_spd_up", JOY_BUTTON_DPAD_RIGHT)
	_btn("flaps", JOY_BUTTON_LEFT_STICK)         # flaps: UP -> 15 -> 35 (L3)
	_btn("brake", JOY_BUTTON_RIGHT_STICK)       # wheel brake (R3). Left stick click no longer does anything.
	_btn("center_view", JOY_BUTTON_RIGHT_STICK) # R3 also snaps the free-look camera back ahead
	_mouse("center_view", MOUSE_BUTTON_RIGHT)   # ...and so does the right mouse button
	_btn("ui_cancel", JOY_BUTTON_START)         # pause / back
	_btn("ui_accept", JOY_BUTTON_A)             # menus (Godot already maps this; explicit for safety)
	# Simulation time warp (fast-forward the flight, not the day/night clock): ] steps it up, [ steps it down.
	# No gamepad binding by default, but both are listed in Options > Controls and can be bound there.
	_key("warp_up", KEY_BRACKETRIGHT)      # ]
	_key("warp_down", KEY_BRACKETLEFT)     # [
	# Debug / utility
	_key("time_cycle", KEY_T)
	_key("weather_cycle", KEY_Y)
	_key("outline_toggle", KEY_O)
	_key("assist_toggle", KEY_R)
	_key("hud_toggle", KEY_H)
	_key("respawn", KEY_BACKSPACE)
	_key("start_mode_toggle", KEY_F2)
	_key("airfield_cycle", KEY_F3)


# ---------------------------------------------------------------- gamepad remapping

## Rebinding (Options > Controls): one joypad button/axis per action, remembered in settings.cfg [input].
func rebind_pad(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if _is_joypad(e):
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, ev)
	pad_bindings[action] = _encode_pad(ev)
	save_settings()


## Restore every joypad action to its built-in binding.
func reset_pad_bindings() -> void:
	pad_bindings.clear()
	for a in _pad_defaults.keys():
		for e in InputMap.action_get_events(a):
			if _is_joypad(e):
				InputMap.action_erase_event(a, e)
		for e in (_pad_defaults[a] as Array):
			InputMap.action_add_event(a, e)
	save_settings()


## First joypad event bound to an action (for the controls UI label), or null.
func pad_event_for(action: String) -> InputEvent:
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			if _is_joypad(e):
				return e
	return null


func _apply_pad_bindings() -> void:
	for a in pad_bindings.keys():
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			if _is_joypad(e):
				InputMap.action_erase_event(a, e)
		if str(pad_bindings[a]) == UNBOUND:
			continue                       # deliberately unbound: leave it with no joypad event
		InputMap.action_add_event(a, _decode_pad(pad_bindings[a]))


## Remove the joypad binding for an action (it stays keyboard-only / unbound on the pad).
func clear_pad(action: String) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if _is_joypad(e):
			InputMap.action_erase_event(action, e)
	pad_bindings[action] = UNBOUND
	save_settings()


static func _is_joypad(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion


static func _encode_pad(e: InputEvent) -> Array:
	if e is InputEventJoypadButton:
		return ["b", (e as InputEventJoypadButton).button_index]
	return ["a", (e as InputEventJoypadMotion).axis, (e as InputEventJoypadMotion).axis_value]


static func _decode_pad(enc: Array) -> InputEvent:
	if String(enc[0]) == "b":
		var b := InputEventJoypadButton.new()
		b.button_index = int(enc[1])
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = int(enc[1])
	m.axis_value = float(enc[2])
	return m


## Set the 3D scaling mode, render scale and frame generation on the root viewport.
## Mode ids: 0 bilinear (off), 2 FSR 2, 6 DLSS (only exists on the RTX engine, so it is set by number).
func _apply_upscaler(vp: Viewport) -> void:
	var u: int = effective_upscaler()
	print("[gfx] upscaler=%s  dlss_supported=%s  framegen_supported=%s  frame_gen_wanted=%s  scale=%.3f" % [["off", "fsr2", "dlss"][u], dlss_supported(), framegen_supported(), frame_gen, float(UPSCALE_SCALES[clampi(upscale_quality, 0, 3)])])
	match u:
		Upscaler.DLSS:
			vp.scaling_3d_mode = 6 as Viewport.Scaling3DMode
			vp.scaling_3d_scale = float(UPSCALE_SCALES[clampi(upscale_quality, 0, 3)])
		Upscaler.FSR2:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = float(UPSCALE_SCALES[clampi(upscale_quality, 0, 3)])
		_:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
	# frame generation only exists on the RTX engine, needs DLSS, and is only valid on RTX 40-series or newer
	if "frame_generation" in vp:
		vp.set("frame_generation", frame_gen and u == Upscaler.DLSS and framegen_supported())


## Debug / test overrides (not saved): --upscaler=off|fsr2|dlss  --upscale-quality=0..3  --framegen
func _debug_upscaler_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--upscaler="):
			upscaler = {"off": Upscaler.OFF, "fsr2": Upscaler.FSR2, "dlss": Upscaler.DLSS}.get(a.substr(11).to_lower(), upscaler)
		elif a.begins_with("--upscale-quality="):
			upscale_quality = clampi(int(a.substr(18)), 0, 3)
		elif a == "--framegen":
			frame_gen = true
		elif a == "--no-framegen":
			frame_gen = false
		elif a.begins_with("--shadows="):
			shadows_enabled = a.substr(10) == "1"
		elif a.begins_with("--view="):
			view_distance = clampi(int(a.substr(7)), 0, 2)
		elif a.begins_with("--post="):
			post_fx = clampi(int(a.substr(7)), 0, 2)
	# screenshot runs (--shot= / --tour=) must not use DLSS/framegen: the upscale
	# internals have no valid frame in --no-window captures and abort the save
	var capture_run: bool = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") or a.begins_with("--tour="):
			capture_run = true
			break
	if capture_run and not OS.get_cmdline_user_args().has("--capture-upscaler"):
		upscaler = Upscaler.OFF
		frame_gen = false
