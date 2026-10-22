class_name FirstRun
extends RefCounted
## First-launch welcome: offered once, then never again (user://firstrun.cfg).

const PATH := "user://firstrun.cfg"


## True when the welcome card has not been shown yet and this is a normal interactive launch.
static func pending() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--welcome"):      # debug: force the card (screenshots, testing)
		return true
	for a in args:
		if a == "--skip-legal" or a == "--menu-test" or a.begins_with("--ui-shot") or a.begins_with("--missions-shot") or a.begins_with("--shot="):
			return false
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		return not bool(cf.get_value("welcome", "offered", false))
	return true


static func mark_offered() -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("welcome", "offered", true)
	cf.save(PATH)
