class_name UpdateCheck
extends Node
## Manual "Check for updates": one request to GitHub's public releases API, made ONLY when the player presses the
## button (nothing is sent in the background). Compares the latest release tag with this build's version.

signal result(text: String, newer: bool)

const API_URL := "https://api.github.com/repos/colemanuk82/ww2-channel-air-war/releases/latest"
const PAGE_URL := "https://github.com/colemanuk82/ww2-channel-air-war/releases/latest"


## "1.10" > "1.9": compare dotted versions numerically. A leading "v" is ignored.
static func is_newer(latest: String, current: String) -> bool:
	var a: PackedStringArray = latest.trim_prefix("v").split(".")
	var b: PackedStringArray = current.trim_prefix("v").split(".")
	for i in maxi(a.size(), b.size()):
		var x: int = int(a[i]) if i < a.size() else 0
		var y: int = int(b[i]) if i < b.size() else 0
		if x != y:
			return x > y
	return false


func check() -> void:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	req.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code != 200:
			result.emit("Could not reach GitHub", false)
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not (parsed is Dictionary):
			result.emit("Unexpected reply from GitHub", false)
			return
		var tag: String = str((parsed as Dictionary).get("tag_name", ""))
		var cur: String = str(ProjectSettings.get_setting("application/config/version", "0"))
		if tag != "" and is_newer(tag, cur):
			result.emit("New version %s available - click to open" % tag, true)
		else:
			result.emit("You have the latest version (v%s)" % cur, false))
	var err: int = req.request(API_URL, PackedStringArray(["User-Agent: WW2ChannelAirWar", "Accept: application/vnd.github+json"]))
	if err != OK:
		req.queue_free()
		result.emit("Could not start the check", false)
