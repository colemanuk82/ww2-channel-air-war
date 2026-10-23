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
	vb.custom_minimum_size = Vector2(420, 0)
	var t: Label = UIKit.heading(vb, "MISSION COMPLETE" if success else "MISSION FAILED", 38)
	if not success:
		t.add_theme_color_override("font_color", Color(1.0, 0.42, 0.32))
	var secs: int = int(float(stats.get("time", 0.0)))
	var lines: Array = [["Score", str(int(stats.get("score", 0)))], ["Kills", str(int(stats.get("kills", 0)))], ["Time", "%d:%02d" % [secs / 60, secs % 60]]]
	for k in stats.keys():
		if k in ["score", "kills", "time", "success"]:
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
		var avail: float = get_viewport().get_visible_rect().size.y - 330.0
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
