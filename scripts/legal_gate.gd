class_name LegalGate
extends Control
## Start-up gate, shown over the main menu: (1) the photosensitivity warning on every launch, (2) the licence agreement
## and privacy policy on first launch (or when their version changes), (3) a one-time offer to download the optional
## NVIDIA DLSS components on NVIDIA graphics cards. Emits done() when the player may continue.

signal done

const SAVE_PATH := "user://legal.cfg"
const EULA_VERSION := 1
const WARNING_SECONDS := 4.0

var _root: VBoxContainer
var _installer: DlssInstaller
var _bar: ProgressBar
var _status: Label


static func eula_accepted() -> bool:
	var cf := ConfigFile.new()
	return cf.load(SAVE_PATH) == OK and int(cf.get_value("legal", "eula_version", 0)) >= EULA_VERSION


static func _remember_accept() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("legal", "eula_version", EULA_VERSION)
	cf.save(SAVE_PATH)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.03, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_root = VBoxContainer.new()
	_root.custom_minimum_size = Vector2(760, 0)
	_root.add_theme_constant_override("separation", 14)
	center.add_child(_root)
	_step_warning()


func _clear() -> void:
	for c in _root.get_children():
		c.queue_free()


func _wrapped(text: String, size: int = 18, col: Color = UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ---- 1. photosensitivity warning ------------------------------------------------------------------------
func _step_warning() -> void:
	_clear()
	var title := UIKit.label("WARNING - PHOTOSENSITIVITY / EPILEPSY", 30, UIKit.RED, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(title)
	_root.add_child(UIKit.rule(0.8))
	_root.add_child(_wrapped(LegalMenu.text_for("epilepsy").replace("PHOTOSENSITIVITY WARNING\n\n", ""), 19))
	var b: Button = UIKit.button("I understand - continue", _after_warning, 22, true)
	b.disabled = true
	_root.add_child(b)
	var t := get_tree().create_timer(WARNING_SECONDS)
	t.timeout.connect(func() -> void:
		if is_instance_valid(b):
			b.disabled = false)


func _after_warning() -> void:
	if eula_accepted():
		_step_dlss_or_finish()
	else:
		_step_eula()


# ---- 2. licence agreement + privacy -----------------------------------------------------------------------
func _step_eula() -> void:
	_clear()
	_root.add_child(UIKit.label("LICENCE AGREEMENT & PRIVACY", 28, UIKit.TEXT, true))
	_root.add_child(_wrapped("Please read the agreement and privacy policy. You can read them again later under Credits.", 16, UIKit.TEXT_DIM))
	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.custom_minimum_size = Vector2(0, 340)
	body.add_theme_font_override("normal_font", UIKit.body_font())
	body.add_theme_font_size_override("normal_font_size", 15)
	body.add_theme_color_override("default_color", UIKit.TEXT)
	body.text = LegalMenu.text_for("eula") + "\n\n=====================================\n\n" + LegalMenu.text_for("privacy")
	_root.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_root.add_child(row)
	var acc := UIKit.button("I accept", func() -> void:
		_remember_accept()
		_step_dlss_or_finish(), 22, true)
	acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(acc)
	var dec := UIKit.button("Decline and quit", func() -> void: get_tree().quit(), 22)
	dec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dec)


# ---- 3. optional DLSS download ----------------------------------------------------------------------------
func _step_dlss_or_finish() -> void:
	if not DlssInstaller.can_download() or DlssInstaller.offer_declined() or OS.has_feature("editor"):
		done.emit()
		return
	_clear()
	_root.add_child(UIKit.label("NVIDIA DLSS", 30, UIKit.TEXT, true))
	_root.add_child(UIKit.rule(0.8))
	_root.add_child(_wrapped("Your graphics card (%s) may support NVIDIA DLSS, which makes the game run faster and look sharper.\n\nDLSS is not included with the game. With your permission it can be downloaded now (about %d MB) straight from NVIDIA's public repository on GitHub, checked against its checksum, and installed next to the game. Use of the components is subject to NVIDIA's licence, which is saved with them.\n\nIf you skip this, or your card does not support DLSS, the game uses its standard renderer with AMD FSR 2 upscaling. You can download it later from Options > Render." % [RenderingServer.get_video_adapter_name(), DlssInstaller.SDK_MB], 17))
	_status = _wrapped("", 16, UIKit.ACCENT)
	_root.add_child(_status)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.show_percentage = false
	_bar.visible = false
	_root.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_root.add_child(row)
	var yes := UIKit.button("Download DLSS", func() -> void: _begin_download(row), 20, true)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(yes)
	var later := UIKit.button("Not now", func() -> void: done.emit(), 20)
	later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(later)
	var never := UIKit.button("Don't ask again", func() -> void:
		DlssInstaller.set_offer_declined(true)
		done.emit(), 20)
	never.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(never)


func _begin_download(row: HBoxContainer) -> void:
	for c in row.get_children():
		(c as Button).disabled = true
	_bar.visible = true
	_installer = DlssInstaller.new()
	add_child(_installer)
	_installer.progress.connect(func(f: float, text: String) -> void:
		_bar.value = f
		_status.text = text)
	_installer.finished.connect(func(ok: bool, msg: String) -> void:
		_status.text = msg
		for c in row.get_children():
			c.queue_free()
		if ok:
			var rb := UIKit.button("Restart now", func() -> void: DlssInstaller.restart_game(get_tree()), 20, true)
			rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(rb)
		var cont := UIKit.button("Continue" if not ok else "Restart later", func() -> void: done.emit(), 20)
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cont))
	_installer.start()
