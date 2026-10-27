class_name SortieResume
extends RefCounted
## A rolling checkpoint of the current sortie (config + player state), written every few seconds while flying.
## If the game is closed or crashes, the start menu offers to resume the last sortie. Mission objectives are
## re-created from the config; the player's aircraft is restored to its last checkpointed position and state.

const PATH := "user://sortie_resume.json"
const MAX_AGE_S := 7 * 24 * 60 * 60


static func save(cfg: Dictionary, state: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"saved": int(Time.get_unix_time_from_system()), "config": cfg, "state": state}))
	f.close()


## The last checkpoint, or {} when there is none / it is malformed.
static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var d: Dictionary = parsed
		if d.get("config") is Dictionary and d.get("state") is Dictionary:
			return d
	return {}


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func fresh(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	return int(d.get("saved", 0)) > int(Time.get_unix_time_from_system()) - MAX_AGE_S
