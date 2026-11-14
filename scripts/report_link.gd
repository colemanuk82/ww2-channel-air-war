class_name ReportLink
extends RefCounted
## Opt-in crash reports and feedback. Nothing is ever sent by the game: these build a "new issue" link on the
## game's GitHub page with the text filled in, and open it in the player's browser. The player reads (and can edit
## or delete) everything before pressing Submit there, and can simply close the page instead.
##
## The crash text is the tail of the black box file (BlackBox, user://logs/blackbox_CRASH_*.txt) with the player's
## home folder and user name replaced by "~" / "<user>", so no personal path leaves the PC.

const ISSUES_URL := "https://github.com/colemanuk82/ww2-channel-air-war/issues/new"
const MAX_LOG_CHARS := 5000     # GitHub (and browsers) cut very long links; the tail of the log is what matters


static func system_line() -> String:
	return "Game v%s | Godot %s | %s %s | %s | %s" % [
		str(ProjectSettings.get_setting("application/config/version", "?")),
		str(Engine.get_version_info().get("string", "")),
		OS.get_name(), OS.get_version(), OS.get_processor_name(), RenderingServer.get_video_adapter_name()]


## Replace the player's home folder and user name in a text with neutral placeholders.
static func scrub(text: String) -> String:
	var t: String = text
	var home: String = OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	if home != "":
		t = t.replace(home, "~").replace(home.replace("\\", "/"), "~")
	var user: String = OS.get_environment("USERNAME")
	if user == "":
		user = OS.get_environment("USER")
	if user.length() >= 3:
		t = t.replace(user, "<user>")
	return t


## The last part of a log file, scrubbed; "" when it cannot be read.
static func log_tail(path: String, max_chars: int = MAX_LOG_CHARS) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	if s.length() > max_chars:
		s = "...\n" + s.substr(s.length() - max_chars)
	return scrub(s)


static func issue_url(title: String, body: String, label: String = "") -> String:
	var url: String = "%s?title=%s&body=%s" % [ISSUES_URL, title.uri_encode(), body.uri_encode()]
	if label != "":
		url += "&labels=" + label.uri_encode()
	return url


static func crash_body(crash_path: String) -> String:
	var tail: String = log_tail(crash_path)
	return "**What were you doing when it closed?**\n\n\n\n**System**\n%s\n\n**Black box (last lines, personal paths removed)**\n```\n%s\n```\n" % [system_line(), tail if tail != "" else "(no log found)"]


static func feedback_body() -> String:
	return "**Your feedback, idea or bug**\n\n\n\n**System**\n%s\n" % system_line()


## Open a pre-filled crash report in the browser (the player still has to press Submit on GitHub).
static func open_crash_report(crash_path: String) -> void:
	OS.shell_open(issue_url("Crash report v%s" % str(ProjectSettings.get_setting("application/config/version", "?")), crash_body(crash_path), "crash"))


static func open_feedback() -> void:
	OS.shell_open(issue_url("Feedback: ", feedback_body(), "feedback"))
