class_name ModeRegistry
extends RefCounted
## Static registry of game modes: id -> {name, script, desc?}.
## To add a mode, APPEND an entry to MODES (keep it a plain dictionary):
##   "bombing": {"name": "Bombing Run", "script": "res://scripts/modes/bombing_mode.gd", "desc": "..."},
## The script must extend ModeBase. Optional members main.gd understands (duck-typed):
##   var start_airborne: bool        # spawn player in the air
##   var manages_respawn: bool       # mode handles player death/respawn itself
##   func configure(cfg: Dictionary) # called before start(): side, aircraft, difficulty, weather, time

const MODES := {
	"dogfight": {"name": "Dogfight", "script": "res://scripts/modes/dogfight_mode.gd", "desc": "Waves of enemy fighters over the Channel. Score kills, chain combos, survive."},
	"free": {"name": "Free Flight", "script": "res://scripts/modes/free_flight_mode.gd", "desc": "No objectives. Roam the Channel and Kent, take off and land."},
	"bombing": {"name": "Bombing Run", "script": "res://scripts/modes/bombing_mode.gd", "desc": "Fly to a real enemy target, bomb it through flak and fighters, then return to base."},
	"ground": {"name": "Ground Attack", "script": "res://scripts/modes/ground_attack_mode.gd", "desc": "Strafe trains, convoys and tanks behind the lines. Hit the kill quota."},
	"training": {"name": "Training", "script": "res://scripts/modes/training_mode.gd", "desc": "Flying school: basics, take-off, landing, gunnery, rockets and bombs, formation flying, stalls and dogfighting. Pick a lesson from the Mission list."},
	"defend": {"name": "Defend Targets", "script": "res://scripts/ground/defend_mode.gd", "desc": "Intercept enemy bomber raids before they hit your installations."},
	"escort": {"name": "Bomber Escort", "script": "res://scripts/modes/escort_mode.gd", "desc": "Escort a bomber formation to a real target and back. Keep the bombers alive through the interceptors."},
	"dambuster": {"name": "Dam Busters [WIP]", "script": "res://scripts/modes/dam_run_mode.gd", "desc": "Training, then Operation Chastise: low flying, skipping bombs, release timing and the attack on the Möhne, Eder and Sorpe dams. One mission a day."},
	"pow_escape": {"name": "POW Escape [WIP]", "script": "res://scripts/modes/pow_escape_mode.gd", "desc": "What-if clandestine operations: scout a prisoner-of-war camp by day, then fly a civil Dragon Rapide in at night under cloud, land on a field strip beside the camp, pick up the escapers and get home quietly. Each camp is a scouting sortie then a pickup."},
	"airborne": {"name": "D-Day Airborne [WIP]", "script": "res://scripts/modes/airborne_mode.gd", "desc": "6 June 1944 in a C-47 Skytrain: drop sticks of paratroopers onto the dropping zones, low and slow, and tow assault gliders to the landing zones, with the tow rope in view and a cast-off in reach of the zone."},
	"historical": {"name": "Historical Missions [WIP]", "script": "res://scripts/modes/historical_missions.gd", "desc": "Battle of Britain, Dieppe, D-Day, Dunkirk and the bomber raids. Pick a mission from the Mission list."},
}


static func get_mode_ids() -> Array:
	return MODES.keys()


## Ids whose script file actually exists (entries may be registered before their script lands).
static func get_available_ids() -> Array:
	var out: Array = []
	for id in MODES.keys():
		if ResourceLoader.exists(MODES[id]["script"]):
			out.append(id)
	return out


static func has_mode(id: String) -> bool:
	return MODES.has(id) and ResourceLoader.exists(MODES[id]["script"])


static func display_name(id: String) -> String:
	return String(MODES[id]["name"]) if MODES.has(id) else id


static func description(id: String) -> String:
	return String(MODES[id].get("desc", "")) if MODES.has(id) else ""


## Instantiate a mode by id (null if unknown/missing).
static func create(id: String) -> ModeBase:
	if not has_mode(id):
		return null
	var scr: Script = load(MODES[id]["script"]) as Script
	return scr.new() as ModeBase
