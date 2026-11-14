class_name PatrolMode
extends FreeFlightMode
## Patrol Missions: pick one kind of Ops Room job from the Mission list (intercept a raid, photo recce, air-sea
## rescue, hunt a convoy at sea, ...) and the Ops Room calls with it soon after take-off, then again with the same
## kind each time one is done. Built on Free Flight's OpsRoom (scripts/modes/ops_room.gd), which places the job
## on a real target, runs it and writes the result to the pilot's logbook.
## configure(cfg): FreeFlightMode's keys plus "mission" = the tasking kind (one of KINDS).

const KINDS := [
	{"id": "intercept", "name": "Intercept a bomber raid", "brief": "An enemy raid with its escort is heading for one of our towns or airfields. Get to it and break it up before it bombs."},
	{"id": "recce", "name": "Photo reconnaissance", "brief": "Photograph an enemy site: fly over it low and with the wings level, then bring the pictures home."},
	{"id": "rescue", "name": "Air-sea rescue", "brief": "A pilot is down in his dinghy in the Channel. Find him and circle low over him until the rescue launch has a fix."},
	{"id": "shipping", "name": "Convoy hunt (shipping)", "brief": "A merchant convoy with escorts is at sea on a real convoy route. Sink or damage the ships."},
	{"id": "eboats", "name": "E-boat flotilla", "brief": "Fast attack boats are heading out of an enemy port. Catch them before they reach the convoy lanes."},
	{"id": "convoy", "name": "Road convoy", "brief": "A supply convoy is moving on the roads near an enemy town. Find it and shoot it up."},
	{"id": "cover", "name": "Convoy cover", "brief": "Enemy dive bombers are going for one of our coastal convoys. Get there first and drive them off."},
	{"id": "sweep", "name": "Fighter sweep", "brief": "Enemy fighters are patrolling over their own territory. Clear the sky."},
	{"id": "strike", "name": "Strike", "brief": "Bomb or rocket a real target: a factory, rail yard, port, radar or V-1 site."},
]

var patrol_kind: String = "intercept"


static func kind_ids() -> Array:
	var out: Array = []
	for k in KINDS:
		out.append(String(k["id"]))
	return out


static func brief_for(id: String) -> String:
	for k in KINDS:
		if String(k["id"]) == id:
			return String(k["brief"])
	return ""


func configure(cfg: Dictionary) -> void:
	var c: Dictionary = cfg.duplicate()
	c["taskings"] = true
	c["ambient"] = false
	super.configure(c)
	var want: String = String(cfg.get("mission", ""))
	for a in OS.get_cmdline_user_args():     # debug: --mission=<kind> (the menu passes it in cfg instead)
		if a.begins_with("--mission="):
			want = a.substr(10)
	patrol_kind = want if want in kind_ids() else String(KINDS[0]["id"])


func start() -> void:
	super.start()
	if ops != null:
		ops.set("_forced", patrol_kind)
		ops.set("_next_t", 25.0)          # the first call comes once the flight is up and away
		objective_updated.emit("%s - the Ops Room will call shortly" % _kind_name())


func _kind_name() -> String:
	for k in KINDS:
		if String(k["id"]) == patrol_kind:
			return String(k["name"])
	return patrol_kind
