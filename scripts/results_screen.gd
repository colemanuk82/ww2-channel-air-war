class_name ResultsScreen
extends CanvasLayer
## End-of-mission overlay: score / kills / time (+ any other simple stats) with restart/menu/quit.

signal restart_requested
signal menu_requested
signal quit_requested


static func show_results(parent: Node, success: bool, stats: Dictionary) -> ResultsScreen:
	var r := ResultsScreen.new()
	parent.add_child(r)
	r._build(success, stats)
	return r


func _build(success: bool, stats: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	get_tree().paused = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim: Control = UIKit.dimmer(0.6)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb: VBoxContainer = UIKit.panel(center)
	var debrief: Dictionary = stats.get("debrief", {}) if stats.get("debrief", null) is Dictionary else {}
	vb.custom_minimum_size = Vector2(560 if not debrief.is_empty() else 420, 0)
	var t: Label = UIKit.heading(vb, "MISSION COMPLETE" if success else "MISSION FAILED", 38)
	if not success:
		t.add_theme_color_override("font_color", Color(1.0, 0.42, 0.32))
	if not debrief.is_empty():
		_build_debrief(vb, debrief)
	var secs: int = int(float(stats.get("time", 0.0)))
	var lines: Array = [["Score", str(int(stats.get("score", 0)))], ["Kills", str(int(stats.get("kills", 0)))], ["Time", "%d:%02d" % [secs / 60, secs % 60]]]
	for k in stats.keys():
		if k in ["score", "kills", "time", "success", "grade"] or (not debrief.is_empty() and k in ["reason", "mission"]):
			continue
		var v: Variant = stats[k]
		if v is int or v is float or v is String:
			lines.append([String(k).capitalize().replace("_", " "), str(v)])
	# stats and the bomb-damage maps scroll on their own, so the buttons below stay on screen however many targets
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	for ln in lines:
		var hb := HBoxContainer.new()
		body.add_child(hb)
		var a := UIKit.label(ln[0], 20, UIKit.ACCENT)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(a)
		hb.add_child(UIKit.label(ln[1], 20))
	var bda: Variant = stats.get("bda", null)
	if bda is Dictionary and not (bda as Dictionary).get("targets", []).is_empty():
		body.add_child(BDAMap.panel((bda as Dictionary)["targets"]))
	var fit := func() -> void:
		var avail: float = get_viewport().get_visible_rect().size.y - (330.0 if debrief.is_empty() else 590.0)
		scroll.custom_minimum_size.y = clampf(body.get_combined_minimum_size().y, 120.0, maxf(avail, 120.0))
	fit.call_deferred()
	var b1 := UIKit.button("Restart", func() -> void: restart_requested.emit(), 22, true)
	vb.add_child(b1)
	vb.add_child(UIKit.button("Back to menu", func() -> void: menu_requested.emit()))
	vb.add_child(UIKit.button("Quit game", func() -> void: quit_requested.emit()))
	b1.grab_focus()
	for gm in get_tree().get_nodes_in_group("game_music"):
		gm.call("fade_out_and_stop")
	# victory music for a successful mission (assets/music/victory/<allies|axis>.mp3)
	if success:
		var path: String = "res://assets/music/victory/%s.mp3" % ("axis" if GameState.player_side == "Axis" else "allies")
		if ResourceLoader.exists(path) and not AudioManager.muted:
			var mp := AudioStreamPlayer.new()
			mp.stream = load(path)
			mp.volume_db = linear_to_db(clampf(AudioManager.music_volume * AudioManager.master_volume, 0.01, 1.0))
			mp.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(mp)
			mp.play()
			AudioManager.set_game_sound_muted(true)     # engine / guns quiet under the music (unmuted after the next load)


const DONE_COL := Color(0.55, 0.88, 0.5)
const MISSED_COL := Color(0.78, 0.74, 0.66, 0.7)
const STAR_SLOTS: int = 3


## The debrief of a historical mission (MissionBrief.debrief): its name, the grade as stars, a written account and
## the objectives with what was achieved.
func _build_debrief(vb: VBoxContainer, d: Dictionary) -> void:
	var name_l: Label = UIKit.label(str(d.get("title", "")), 20, UIKit.ACCENT)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_l)
	var grade: int = int(d.get("grade", 0))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	var stars := Control.new()
	stars.custom_minimum_size = Vector2(34.0 * float(STAR_SLOTS), 30.0)
	stars.draw.connect(func() -> void:
		for i in STAR_SLOTS:
			var pts: PackedVector2Array = star_points(Vector2(17.0 + 34.0 * float(i), 15.0), 13.0)
			if i < grade:
				stars.draw_colored_polygon(pts, UIKit.ACCENT)
			pts.append(pts[0])
			stars.draw_polyline(pts, Color(UIKit.ACCENT, 0.9 if i < grade else 0.4), 1.5, true))
	row.add_child(stars)
	row.add_child(UIKit.label(str(d.get("grade_name", "")).to_upper(), 22, UIKit.TEXT, true))
	var sum: Label = UIKit.label(str(d.get("summary", "")), 17)
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum.custom_minimum_size = Vector2(520, 0)
	sum.add_theme_font_override("font", UIKit.body_font())
	vb.add_child(sum)
	for o in d.get("objectives", []):
		var done: bool = bool(o.get("done", false))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		vb.add_child(hb)
		var tag: Label = UIKit.label("DONE" if done else ("FAILED" if bool(o.get("primary", false)) else "MISSED"), 15, DONE_COL if done else MISSED_COL, true)
		tag.custom_minimum_size = Vector2(64, 0)
		hb.add_child(tag)
		var text: String = str(o.get("text", ""))
		if not bool(o.get("primary", false)):
			text = "Bonus: " + text
			var note: String = str(o.get("note", ""))
			if note != "" and not done:
				text += "  (%s)" % note
		var ol: Label = UIKit.label(text, 16, UIKit.TEXT if done else MISSED_COL)
		ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(ol)


## Outline of a five-pointed star (10 points, first point at the top).
static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a: float = -PI * 0.5 + float(k) * PI / 5.0
		var rr: float = r if k % 2 == 0 else r * 0.42
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts
