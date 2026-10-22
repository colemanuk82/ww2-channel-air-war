class_name DlssInstaller
extends Node
## Optional NVIDIA DLSS / Streamline components. They are NOT shipped with the game: with the player's consent this
## downloads NVIDIA's own Streamline SDK release from GitHub, verifies it, and unpacks only the runtime DLLs (plus
## NVIDIA's licence texts) next to the game. Without them the game falls back to FSR 2 / standard rendering.

signal progress(fraction: float, text: String)
signal finished(ok: bool, message: String)

const SDK_URL := "https://github.com/NVIDIA-RTX/Streamline/releases/download/v2.10.0/streamline-sdk-v2.10.0.zip"
const SDK_BYTES := 213131430
const SDK_SHA256 := "b0cc810c86b0335d4fd76a02d35fff53e528d2fb66c29860565130f76c9383b0"
const SDK_MB := 213
const TMP_ZIP := "user://nvidia_streamline_sdk.zip"
const PREF_PATH := "user://dlss_offer.cfg"
## Runtime files the engine loads at start-up (sl.interposer.dll is loaded with LoadLibrary).
const RUNTIME_FILES := ["sl.interposer.dll", "sl.common.dll", "sl.dlss.dll", "sl.dlss_g.dll", "sl.nis.dll", "sl.pcl.dll",
	"sl.reflex.dll", "NvLowLatencyVk.dll", "nvngx_dlss.dll", "nvngx_dlssg.dll"]
const LICENCE_FILES := ["license.txt", "3rd-party-licenses.md", "nvngx_dlss.license.txt", "nis.license.txt", "reflex.license.txt"]

static var active: DlssInstaller = null     # the running download, so a re-built Options page can re-attach to it

var running: bool = false
var _http: HTTPRequest
var _thread: Thread
var _result: Dictionary = {}


static func install_dir() -> String:
	return OS.get_executable_path().get_base_dir()


static func is_windows() -> bool:
	return OS.get_name() == "Windows"


static func is_installed() -> bool:
	if not is_windows():
		return false
	for f in RUNTIME_FILES:
		if not FileAccess.file_exists(install_dir().path_join(f)):
			return false
	return true


## True when the graphics card is an NVIDIA one (DLSS needs an RTX card; Streamline reports the exact capability).
static func gpu_is_nvidia() -> bool:
	return RenderingServer.get_video_adapter_name().to_lower().contains("nvidia")


static func can_download() -> bool:
	return is_windows() and gpu_is_nvidia() and not is_installed()


static func offer_declined() -> bool:
	var cf := ConfigFile.new()
	if cf.load(PREF_PATH) == OK:
		return bool(cf.get_value("offer", "declined", false))
	return false


static func set_offer_declined(v: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(PREF_PATH)
	cf.set_value("offer", "declined", v)
	cf.save(PREF_PATH)


static func restart_game(tree: SceneTree) -> void:
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	tree.quit()


func start() -> void:
	if running:
		return
	running = true
	active = self
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_ZIP))
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.download_file = TMP_ZIP
	_http.max_redirects = 10
	_http.request_completed.connect(_on_downloaded)
	add_child(_http)
	var err: int = _http.request(SDK_URL)
	if err != OK:
		_fail("Could not start the download (error %d). Check your internet connection." % err)
		return
	progress.emit(0.0, "Connecting to github.com ...")
	set_process(true)


func _process(_delta: float) -> void:
	if _http != null and running and _thread == null:
		var got: int = _http.get_downloaded_bytes()
		var total: int = _http.get_body_size()
		if total <= 0:
			total = SDK_BYTES
		progress.emit(clampf(float(got) / float(total), 0.0, 1.0) * 0.9, "Downloading NVIDIA components: %d / %d MB" % [got / 1048576, total / 1048576])
	elif _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		set_process(false)
		if bool(_result.get("ok", false)):
			_done(String(_result.get("msg", "")))
		else:
			_fail(String(_result.get("msg", "Install failed.")))


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Download failed (network %d, HTTP %d). Try again later." % [result, code])
		return
	progress.emit(0.92, "Checking the download ...")
	_thread = Thread.new()
	_thread.start(_extract_job)


func _extract_job() -> void:
	var path: String = ProjectSettings.globalize_path(TMP_ZIP)
	if FileAccess.get_sha256(path).to_lower() != SDK_SHA256:
		_result = {"ok": false, "msg": "The downloaded file did not match NVIDIA's release (checksum mismatch). Nothing was installed."}
		return
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		_result = {"ok": false, "msg": "Could not open the downloaded archive."}
		return
	var dest: String = install_dir()
	var lic_dir: String = dest.path_join("licenses")
	DirAccess.make_dir_recursive_absolute(lic_dir)
	var wrote: Array = []
	for entry in zr.get_files():
		var e: String = entry
		var base: String = e.get_file()
		var in_prod: bool = e.begins_with("bin/x64/") and not e.contains("development")
		var target: String = ""
		if in_prod and RUNTIME_FILES.has(base):
			target = dest.path_join(base)
		elif (in_prod and LICENCE_FILES.has(base)) or (e.count("/") == 0 and LICENCE_FILES.has(base)):
			target = lic_dir.path_join(base)
		if target == "":
			continue
		var bytes: PackedByteArray = zr.read_file(e)
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			zr.close()
			_result = {"ok": false, "msg": "Could not write %s. Run the game from a folder you can write to (not Program Files)." % base}
			return
		f.store_buffer(bytes)
		f.close()
		wrote.append(base)
	zr.close()
	for need in RUNTIME_FILES:
		if not wrote.has(need):
			_result = {"ok": false, "msg": "The NVIDIA package did not contain %s." % need}
			return
	DirAccess.remove_absolute(path)
	_result = {"ok": true, "msg": "Installed. Restart the game to turn DLSS on."}


func _done(msg: String) -> void:
	running = false
	active = null
	progress.emit(1.0, msg)
	finished.emit(true, msg)


func _fail(msg: String) -> void:
	running = false
	active = null
	set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_ZIP))
	progress.emit(0.0, msg)
	finished.emit(false, msg)
