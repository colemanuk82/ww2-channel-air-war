class_name MilitaryPeople
extends RefCounted
## Phase 3 of the living world: soldiers and crews everywhere on both sides (see docs/STATUS.md).
##  * gun crews: 3-7 men at every AA gun (flak, Bofors, 3.7 in / 88, machine-gun pit) and 3-4 at every searchlight,
##    standing about outside the pit and RUNNING to their posts (and kneeling / reaching at the gun) when an enemy
##    aircraft comes near; sentries at pillboxes, bunkers and coastal batteries (scan_site, at site build);
##  * per countryside tile (tile_plan, on the tile's worker thread): Home Guard / Feldgendarmerie checkpoints at
##    crossroads outside the towns (a pole barrier, sandbags and a sentry box), pairs of soldiers marching a beat
##    along the beaches and cliff tops, and roadside halts where a few lorries are parked on the verge with their
##    men stood about them (the moving convoys never stop, so the halts are scenery of their own).
## Everything is drawn with AirfieldPeople's one-MultiMesh figures: the planning stays on workers / small, the main
## thread only builds a MultiMesh (and a few barrier / lorry meshes) per cluster.
## Side and era come from GroundKit.side_at (the 1944-45 front line moves it): British and Home Guard on the English
## side and in liberated ground, Germans (Feldgendarmerie at the checkpoints) in Axis-held ground.

const Kind = AirfieldPeople.Kind

const CELL: float = 400.0                 # guns this close share one MultiMesh
const VIEW: float = 1300.0                # the crews fade out at this distance
const REACT_RANGE: float = 1500.0         # enemy aircraft this close (and low enough) bring the crews to their posts
const REACT_HEIGHT: float = 3000.0
const HOLD_S: float = 8.0                 # the crews stay at their posts this long after the last enemy seen
const RUN_SPEED: float = 3.0              # mesh metres a second (the same as the airfield runners)
const WALK_SPEED: float = 1.4
const RUN_HALT: float = 1.2               # the shader's pause at each end of a RUN / WALK beat (see airfield_people.gdshader)
const WALK_HALT: float = 2.4

const DRESS_PLAIN: int = 0                # 0-3: the side's service dress (soldier flag on)

## The roles in a gun crew, in the order men are added: [angle round the pit (degrees; local +z is the entrance
## the sandbag ring leaves open), radius factor, post kind, kind while standing about].
const ROLES := [
	[45.0, 1.0, Kind.REACH, Kind.TALK],        # the layer / first number
	[225.0, 1.0, Kind.KNEEL, Kind.QUEUE],      # loader at the ready-use ammunition
	[90.0, 1.6, Kind.TALK, Kind.QUEUE],        # the sergeant, at the entrance, shouting the orders
	[315.0, 1.0, Kind.KNEEL, Kind.SMOKER],
	[165.0, 1.0, Kind.WORK, Kind.TALK],        # ammunition number
	[135.0, 1.0, Kind.REACH, Kind.TALK],       # second layer / spotter
	[270.0, 1.0, Kind.KNEEL, Kind.QUEUE],
]


# ------------------------------------------------------------------ numbers and geometry (pure, tested)

## How many men a gun gets: 3-7, from its type and the quality setting (density(): 0.7 / 1.6 / 2.2).
static func crew_size(gtype: String, dens: float) -> int:
	var base: float = 5.0 if gtype == "88mm" else (4.0 if gtype == "bofors" else 2.5)
	return clampi(int(round(base * (0.5 + dens * 0.5))), 3, 7)


## The post radius on the pit floor and the radius of the open sandbag ring, by gun type (the AA gun meshes are
## drawn at 1.4 x: ring 5 / 6.5 m, the sergeant stands in the entrance gap).
static func pit_radii(gtype: String) -> Vector2:
	return Vector2(5.0, 9.1) if gtype == "88mm" else Vector2(3.6, 7.0)


## One man's place at a gun: [post (local x, z), ease (local x, z), post kind, ease kind]. The post is on the pit floor
## between the gun and the ring; the ease spot is outside the entrance, in a loose knot on the +z side.
static func gun_slots(gtype: String, count: int) -> Array:
	var rr: Vector2 = pit_radii(gtype)
	var out: Array = []
	var zr: float = rr.y + 0.8 + 2.4                      # just past the ring's outer edge
	for i in count:
		var r: Array = ROLES[i % ROLES.size()]
		var a: float = deg_to_rad(float(r[0]))
		var rad: float = rr.x * float(r[1])
		var post := Vector2(cos(a) * rad, sin(a) * rad)
		var ex: float = (float(i) - float(count - 1) * 0.5) * 1.5
		var ease_p := Vector2(ex, zr + float(i % 2) * 1.7)
		out.append([post, ease_p, int(r[2]), int(r[3])])
	return out


## Phase (0..1, the INSTANCE_CUSTOM.z the shader multiplies by 61 s) that makes a RUN / WALK beat of `len_mesh` mesh
## metres begin at its start `now` (the shader's TIME): afterwards the man runs the beat once, so the crew can be
## switched to the stationed pose when he arrives.
static func beat_phase(len_mesh: float, spd: float, halt: float, now: float) -> float:
	var ln: float = maxf(len_mesh, 0.5)
	var sp: float = maxf(spd, 0.1)
	var period: float = 2.0 * (ln + halt * sp) / sp
	return fposmod(-now, period) / 61.0


## Where a checkpoint's men stand: [position (Vector2), facing (Vector2), kind] for up to four men, from the
## junction `j`, the unit road direction `d` and the road width `w`. The barrier lies across the road 10 m along d;
## the men are on the approach side of it, on the road and its verges (never beyond the sandbags).
static func checkpoint_spots(j: Vector2, d: Vector2, w: float, count: int) -> Array:
	var lat := Vector2(d.y, -d.x)
	var half: float = w * 0.5
	var face: Vector2 = -d
	var out: Array = []
	var spots: Array = [
		[7.2, -(half - 0.4), Kind.SALUTE],
		[6.4, 0.9, Kind.TALK],
		[8.4, half + 1.0, Kind.SMOKER],
		[7.6, half - 0.5, Kind.SALUTE],
	]
	for i in mini(count, spots.size()):
		var s: Array = spots[i]
		out.append([j + d * float(s[0]) + lat * float(s[1]), face, int(s[2])])
	return out


## The roadside halt's men round `h` (the middle of the halt), road direction d, road width w, lorries stood on the
## verge at lateral +side: [position, facing, kind]. Pairs talk face to face, one has a smoke, one is the sentry.
static func halt_spots(h: Vector2, d: Vector2, w: float, side: float, lorries: int, count: int) -> Array:
	var lat := Vector2(d.y, -d.x) * side
	var lat_l: float = w * 0.5 + 2.4                      # the lorries' centre line
	var out: Array = []
	var run: float = float(lorries - 1) * 11.0
	var spots: Array = [
		[-run * 0.5 - 7.0, lat_l - 0.5, 1.0, Kind.TALK],            # in front of the first cab
		[-run * 0.5 - 7.0, lat_l + 0.8, -1.0, Kind.TALK],
		[run * 0.5 + 7.2, lat_l + 0.3, 1.0, Kind.SMOKER],           # behind the last tail
		[0.0, lat_l + 3.0, 1.0, Kind.TALK],                         # on the far side
		[1.2, lat_l + 3.3, -1.0, Kind.TALK],
		[-run * 0.5 - 4.0, lat_l - 2.4, 1.0, Kind.SALUTE],          # the sentry at the road edge
		[run * 0.5 + 5.0, lat_l + 2.6, -1.0, Kind.QUEUE],
	]
	for i in mini(count, spots.size()):
		var s: Array = spots[i]
		var p: Vector2 = h + d * float(s[0]) + lat * float(s[1])
		var f: Vector2 = (d * float(s[2]) * 0.4 + Vector2(-lat.x, -lat.y) * 0.0).normalized()
		out.append([p, f, int(s[3])])
	# the pairs face each other: the 2nd man of a pair looks at the first
	if out.size() >= 2:
		var o0: Array = out[0]
		var o1: Array = out[1]
		o0[1] = (o1[0] as Vector2) - (o0[0] as Vector2)
		o1[1] = (o0[0] as Vector2) - (o1[0] as Vector2)
	if out.size() >= 5:
		var o3: Array = out[3]
		var o4: Array = out[4]
		o3[1] = (o4[0] as Vector2) - (o3[0] as Vector2)
		o4[1] = (o3[0] as Vector2) - (o4[0] as Vector2)
	for e in out:
		var ea: Array = e
		ea[1] = (ea[1] as Vector2).normalized() if (ea[1] as Vector2).length() > 0.01 else d
	return out


# ------------------------------------------------------------------ a built site: gun and searchlight crews, sentries

## Called from the world populator once a site's node is built (before it enters the scene): finds its AA guns,
## searchlights, pillboxes, bunkers and batteries (direct children) and gives each its men. One MultiMesh per
## 400 m cluster of them, with a CrewDriver that sends the gun crews to their posts under an enemy aircraft.
static func scan_site(n: Node3D, key: String) -> void:
	if n.has_meta("mil_done"):
		return
	n.set_meta("mil_done", true)
	_ensure_demo()
	var t0: int = Time.get_ticks_usec()
	var dens: float = AirfieldPeople.density()
	var clusters: Dictionary = {}           # "team|cx|cz" -> {"team", "items": [[kind, node]]}
	for ch in n.get_children():
		var knd: String = ""
		var team: String = ""
		if ch is AAGun:
			knd = "gun"
			team = (ch as AAGun).team
		elif ch is Searchlight:
			knd = "light"
			team = (ch as Searchlight).team
		elif ch is GroundStructure:
			var sk: String = (ch as GroundStructure).skind
			if sk == "pillbox" or sk == "bunker" or sk == "battery":
				knd = sk
				team = (ch as GroundStructure).team
		if knd == "":
			continue
		var p: Vector3 = (ch as Node3D).position + n.position
		var ck: String = "%s|%d|%d" % [team, floori(p.x / CELL), floori(p.z / CELL)]
		if not clusters.has(ck):
			clusters[ck] = {"team": team, "items": []}
		var item: Dictionary = {"kind": knd, "pos": p, "basis": (ch as Node3D).transform.basis.orthonormalized(), "gtype": "", "guns": 0}
		if ch is AAGun:
			item["gtype"] = (ch as AAGun).gtype
		elif ch is GroundStructure:
			item["guns"] = (ch as GroundStructure).guns
		(clusters[ck]["items"] as Array).append(item)
	if clusters.is_empty():
		return
	for ck in clusters.keys():
		var cl: Dictionary = clusters[ck]
		_queue.append([weakref(n), str(cl["team"]), cl["items"], hash(key) + hash(ck), dens, key])
	_ensure_pump()
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	if OS.is_debug_build() and (ms > 1.0 or OS.get_cmdline_user_args().has("--mil-log")):
		print("[mil] site %s: %d clusters queued, scan %.1f ms" % [key, clusters.size(), ms])


static var _queue: Array = []
static var _pump: Node = null


static func _ensure_pump() -> void:
	if _pump != null and is_instance_valid(_pump):
		return
	var tree: SceneTree = GroundKit.tree()
	if tree == null:
		return
	_pump = ClusterPump.new()
	tree.root.add_child.call_deferred(_pump)


## Builds the queued gun clusters one per frame (a few tenths of a millisecond each: a MultiMesh and the ground heights of
## a handful of men), once the site's node is in the scene, so an airfield with a dozen pits never costs the frame 2 ms.
class ClusterPump extends Node:
	func _process(_d: float) -> void:
		var t0: int = Time.get_ticks_usec()
		var tries: int = 0
		while not MilitaryPeople._queue.is_empty() and tries < 40:
			tries += 1
			var job: Array = MilitaryPeople._queue[0]
			var nd: Node3D = (job[0] as WeakRef).get_ref() as Node3D
			if nd == null or not is_instance_valid(nd):
				MilitaryPeople._queue.pop_front()          # the site streamed out again
				continue
			if not nd.is_inside_tree():
				MilitaryPeople._queue.push_back(MilitaryPeople._queue.pop_front())   # staged in over a few frames: not yet
				if tries >= MilitaryPeople._queue.size():
					break
				continue
			MilitaryPeople._queue.pop_front()
			var nm: int = MilitaryPeople._make_cluster(nd, str(job[1]), job[2], int(job[3]), float(job[4]))
			if OS.get_cmdline_user_args().has("--mil-log"):
				print("[mil] site %s: cluster of %d men built in %.2f ms" % [str(job[5]), nm, float(Time.get_ticks_usec() - t0) / 1000.0])
			if float(Time.get_ticks_usec() - t0) > 700.0:
				break


static func _make_cluster(n: Node3D, team: String, items: Array, seed_v: int, dens: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var men: Array = []
	var tab: Array = []
	var shot_p: Vector3 = Vector3.INF
	var shot_kind: String = ""
	for it in items:
		var knd: String = it["kind"]
		var gp: Vector3 = it["pos"]
		var bs: Basis = it["basis"]
		match knd:
			"gun":
				var gt: String = it["gtype"]
				var slots: Array = gun_slots(gt, crew_size(gt, dens))
				for si in slots.size():
					var sl: Array = slots[si]
					var post_l: Vector2 = sl[0]
					var ease_l: Vector2 = sl[1]
					var post: Vector3 = gp + bs * Vector3(post_l.x, 0.0, post_l.y)
					post.y = gp.y + 0.17
					var ez: Vector3 = gp + bs * Vector3(ease_l.x, 0.0, ease_l.y)
					ez.y = GroundKit.ground_y(ez.x, ez.z)
					var ease_p: Vector3 = ez
					# an ease spot in the water or up a bank is no good: he waits at his post instead
					if GroundKit.raw_y(ez.x, ez.z) < 0.9 or absf(ez.y - gp.y) > 2.5:
						ease_p = post
					var pdir: Vector3 = (gp - post)
					pdir.y = 0.0
					if pdir.length() < 0.1:
						pdir = bs * Vector3(0.0, 0.0, -1.0)
					var edir: Vector3 = (gp + bs * Vector3(0.0, 0.0, 14.0) - ease_p)
					edir.y = 0.0
					# the knot of men stands round its middle (the men beside him), the middle man looks at the gun
					edir = (Vector3(gp.x, 0.0, gp.z) + bs * Vector3(float(si % 3 - 1) * 2.0, 0.0, 6.0) - Vector3(ease_p.x, 0.0, ease_p.z))
					if edir.length() < 0.1:
						edir = pdir
					_add_man(men, tab, ease_p, edir.normalized(), int(sl[3]), post, pdir.normalized(), int(sl[2]), si % 4, true)
				if shot_kind == "":
					shot_p = gp + bs * Vector3(0.0, 0.0, pit_radii(gt).y + 5.0)
					shot_kind = "gun"
			"light":
				var cnt: int = 3 if dens < 1.0 else 4
				for k in cnt:
					var a: float = TAU * (float(k) + 0.3 * rng.randf()) / float(cnt) + 0.6
					var sp: Vector3 = gp + Vector3(cos(a) * 3.9, 0.0, sin(a) * 3.9)
					sp.y = GroundKit.ground_y(sp.x, sp.z)
					var face: Vector3 = (gp - sp)
					face.y = 0.0
					# standing about; at the alarm they get to work on the lamp (same place, a different job)
					_add_man(men, tab, sp, face.normalized(), Kind.TALK if k % 2 == 0 else Kind.QUEUE, sp, face.normalized(), Kind.WORK if k % 2 == 0 else Kind.REACH, k, true)
				if shot_kind == "":
					shot_p = gp + Vector3(0.0, 0.0, 6.0)
					shot_kind = "light"
			"pillbox", "bunker":
				var loc: Vector3 = Vector3(1.2, 0.0, 8.3) if knd == "pillbox" else Vector3(10.6, 0.0, 0.5)
				var sp2: Vector3 = gp + bs * loc
				sp2.y = GroundKit.ground_y(sp2.x, sp2.z)
				var fc: Vector3 = (bs * Vector3(0.0, 0.0, -1.0))
				_add_man(men, tab, sp2, fc, Kind.SALUTE, sp2, fc, Kind.SALUTE, 1, true)
				if knd == "bunker" and dens > 1.2:
					var sp3: Vector3 = gp + bs * Vector3(-10.6, 0.0, 0.5)
					sp3.y = GroundKit.ground_y(sp3.x, sp3.z)
					_add_man(men, tab, sp3, fc, Kind.SALUTE, sp3, fc, Kind.SALUTE, 2, true)
				if shot_kind == "":
					shot_p = sp2
					shot_kind = "sentry"
			"battery":
				var guns: int = maxi(int(it["guns"]), 2)
				var fc2: Vector3 = (bs * Vector3(0.0, 0.0, -1.0))
				var slots2: Array = [0, guns - 1] if dens >= 1.0 else [0]
				for gi in slots2:
					var gx: float = (float(gi) - float(guns - 1) * 0.5) * 30.0
					var gz: float = sin(float(gi) * 1.7) * 6.0
					var sp4: Vector3 = gp + bs * Vector3(gx - 3.0, 0.0, gz + 11.5)
					sp4.y = GroundKit.ground_y(sp4.x, sp4.z)
					_add_man(men, tab, sp4, fc2, Kind.SALUTE, sp4, fc2, Kind.SALUTE, gi, true)
				var sp5: Vector3 = gp + bs * Vector3(0.0, 0.0, 19.6)
				sp5.y = GroundKit.ground_y(sp5.x, sp5.z)
				_add_man(men, tab, sp5, fc2, Kind.SALUTE, sp5, fc2, Kind.SALUTE, 3, true)
				if dens >= 1.0:
					var sp6: Vector3 = gp + bs * Vector3(4.0, 0.0, 17.5)
					sp6.y = GroundKit.ground_y(sp6.x, sp6.z)
					_add_man(men, tab, sp6, (sp5 - sp6).normalized(), Kind.TALK, sp6, (sp5 - sp6).normalized(), Kind.TALK, 2, true)
				if shot_kind == "":
					shot_p = sp5
					shot_kind = "sentry"
	if men.is_empty():
		return 0
	var c := Vector3.ZERO
	for m in men:
		c += (m as Array)[0] as Vector3
	c /= float(men.size())
	var origin := Vector3(c.x, GroundKit.ground_y(c.x, c.z), c.z)
	var mi: MultiMeshInstance3D = AirfieldPeople.spawn(n, men, origin, team, seed_v, "", true)
	if mi == null:
		return 0
	var old: Node = mi.get_node_or_null("Driver")
	if old != null:
		mi.remove_child(old)
		old.free()                          # the standard "everyone lies flat" driver: these men run to their posts instead
	mi.name = "GunCrew"
	mi.visibility_range_end = VIEW * minf(Scatter.vis_scale, 1.0)
	mi.visibility_range_end_margin = 100.0
	var rad: float = 30.0
	for e in tab:
		rad = maxf(rad, Vector2((e["ease"] as Vector3).x - c.x, (e["ease"] as Vector3).z - c.z).length() + 12.0)
		rad = maxf(rad, Vector2((e["post"] as Vector3).x - c.x, (e["post"] as Vector3).z - c.z).length() + 12.0)
	mi.multimesh.custom_aabb = AABB(Vector3(-rad, -30.0, -rad), Vector3(rad * 2.0, 90.0, rad * 2.0))
	var drv := CrewDriver.new()
	drv.name = "CrewDriver"
	drv.mi = mi
	drv.team = team
	drv.tab = tab
	drv.centre = c
	drv.radius = rad
	mi.add_child(drv)
	_ensure_probe()
	if shot_kind != "":
		_debug_shot(shot_kind, shot_p)
	return men.size()


## One man of a cluster: the MultiMesh entry (standing at his ease spot) and the driver's table row.
static func _add_man(men: Array, tab: Array, ease_p: Vector3, edir: Vector3, ek: int, post: Vector3, pdir: Vector3, pk: int, dress: int, soldier: bool) -> void:
	edir.y = 0.0
	pdir.y = 0.0
	if edir.length() < 0.01:
		edir = Vector3(0.0, 0.0, 1.0)
	if pdir.length() < 0.01:
		pdir = edir
	men.append([Vector3(ease_p.x, 0.0, ease_p.z), edir.normalized(), ek, 0.0, -1.0, 0.0, soldier, null, 0.0, ease_p.y, ease_p.y, dress])
	tab.append({"ease": ease_p, "edir": edir.normalized(), "ek": ek, "post": post, "pdir": pdir.normalized(), "pk": pk, "dress": dress, "soldier": soldier,
		"i": tab.size(), "st": 0, "t": 0.0, "delay": 0.0, "moves": ease_p.distance_to(post) > 0.5 or ek != pk})


## Sends a cluster's gun crews to their posts when an enemy aircraft is near, and back to their ease when it is
## gone. The run is the shader's RUN beat started at the right clock phase (beat_phase), so he runs the stretch once;
## on arrival the figure is swapped for the stationed pose (KNEEL / REACH / WORK). Idle clusters only run a timer.
class CrewDriver extends Node:
	var mi: MultiMeshInstance3D
	var team: String = ""
	var tab: Array = []
	var centre: Vector3
	var radius: float = 40.0
	var _clock: float = 0.0
	var _chk: float = 0.0
	var _threat_t: float = 0.0       # seconds the men stay at their posts after the last enemy seen
	var _want: bool = false
	var _wake_t: float = 0.0         # clock when the want changed
	var _pending: bool = false       # some man still has a transition to do
	var _forced: float = -1.0        # --mil-alarm=<s>: the alarm is called this many seconds after the driver starts

	func _ready() -> void:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--mil-alarm"):
				var v: String = a.substr(11).trim_prefix("=")
				_forced = float(v) if v.is_valid_float() else 3.0
		_chk = randf() * 0.5
		for e in tab:
			e["delay"] = randf_range(0.0, 1.1)

	func _process(delta: float) -> void:
		_clock += delta
		_chk -= delta
		if _chk <= 0.0:
			_chk = 0.5
			var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
			var near: bool = cam != null and Vector2(cam.global_position.x - centre.x, cam.global_position.z - centre.z).length() < MilitaryPeople.VIEW + radius + 900.0
			if not near:
				_chk = 1.5
				_snap_back()
			elif (_forced >= 0.0 and _clock >= _forced) or _enemy_near():
				_threat_t = MilitaryPeople.HOLD_S
		_threat_t = maxf(_threat_t - delta, 0.0)
		var want: bool = _threat_t > 0.0
		if want != _want:
			_want = want
			_wake_t = _clock
			_pending = true
		if not _pending:
			return
		var busy: bool = false
		for e in tab:
			if not bool(e["moves"]):
				continue
			var st: int = int(e["st"])
			var due: float = _wake_t + float(e["delay"]) * (1.0 if _want else 2.2)
			if st == 0 and _want:
				if _clock >= due:
					_start(e, true)
				busy = true
			elif st == 1 or st == 3:
				if _clock >= float(e["t"]):
					_place(e, st == 1)
					e["st"] = 2 if st == 1 else 0
				else:
					busy = true
			elif st == 2 and not _want:
				if _clock >= due:
					_start(e, false)
				busy = true
		_pending = busy

	func _enemy_near() -> bool:
		for nd in get_tree().get_nodes_in_group("aircraft"):
			var ac: Aircraft = nd as Aircraft
			if ac == null or ac.team == team or ac.state != Aircraft.State.ALIVE or ac.on_ground:
				continue
			var d: Vector3 = ac.global_position - centre
			if d.y < MilitaryPeople.REACT_HEIGHT and Vector2(d.x, d.z).length() < MilitaryPeople.REACT_RANGE + radius:
				return true
		return false

	## Camera far away: whoever is still at a post goes straight back to his ease spot (nobody can see it).
	func _snap_back() -> void:
		if _threat_t > 0.0 and _forced < 0.0:
			return
		for e in tab:
			if int(e["st"]) != 0 and bool(e["moves"]):
				_place(e, false)
				e["st"] = 0
		_pending = false

	## Start a run to the post (to = true) or a walk back to the ease spot.
	func _start(e: Dictionary, to: bool) -> void:
		var a: Vector3 = e["ease"] if to else e["post"]
		var b: Vector3 = e["post"] if to else e["ease"]
		var dv := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var dist: float = dv.length()
		var dir: Vector3 = dv.normalized() if dist > 0.3 else (e["pdir"] as Vector3)
		var spd: float = MilitaryPeople.RUN_SPEED if to else MilitaryPeople.WALK_SPEED
		var halt: float = MilitaryPeople.RUN_HALT if to else MilitaryPeople.WALK_HALT
		var kind: int = AirfieldPeople.Kind.RUN if to else AirfieldPeople.Kind.WALK
		var idx: int = int(e["i"])
		if dist < 0.3:
			_place(e, to)
			e["st"] = 2 if to else 0
			return
		var ln: float = dist / AirfieldPeople.MAN
		var ph: float = MilitaryPeople.beat_phase(ln, spd, halt, MilitaryPeople.shader_time())
		_put(idx, a, dir, kind, ln, spd, ph, e)
		e["st"] = 1 if to else 3
		e["t"] = _clock + ln / spd + 0.05

	## The man at his post (at_post) or at his ease spot.
	func _place(e: Dictionary, at_post: bool) -> void:
		var idx: int = int(e["i"])
		var p: Vector3 = e["post"] if at_post else e["ease"]
		var dr: Vector3 = e["pdir"] if at_post else e["edir"]
		_put(idx, p, dr, int(e["pk"]) if at_post else int(e["ek"]), 0.0, 0.0, randf(), e)

	func _put(idx: int, p: Vector3, dir: Vector3, kind: int, ln: float, spd: float, ph: float, e: Dictionary) -> void:
		var mm: MultiMesh = mi.multimesh
		var o: Vector3 = mi.position
		var lp := Vector3(p.x - o.x, p.y + 0.01 - o.y, p.z - o.z)
		var bas: Basis = Basis.looking_at(dir, Vector3.UP).scaled(Vector3.ONE * AirfieldPeople.MAN)
		mm.set_instance_transform(idx, Transform3D(bas, lp))
		var sp: float = spd if spd > 0.0 else 1.4
		mm.set_instance_custom_data(idx, Color(ln, sp, ph, float(AirfieldPeople.code_of(kind, bool(e["soldier"]), int(e["dress"])))))


# ------------------------------------------------------------------ the shader clock (for beat_phase)

static var _toff: float = 0.0
static var _probe: Node = null
static var _probed: bool = false


## The shader's TIME now, estimated as the engine's tick clock plus an offset measured once from a 4 x 4 pixel render
## (the shader time is not readable from script). Off by up to a few hundredths of a second: a run starts within
## a stride of where it should.
static func shader_time() -> float:
	return fposmod(float(Time.get_ticks_usec()) / 1.0e6 + _toff, 3600.0)


static func _ensure_probe() -> void:
	if _probed or (_probe != null and is_instance_valid(_probe)):
		return
	_probed = true
	if DisplayServer.get_name() == "headless":
		return
	var tree: SceneTree = GroundKit.tree()
	if tree == null:
		return
	_probe = TimeProbe.new()
	tree.root.add_child.call_deferred(_probe)


## Renders one pixel pair carrying TIME (coarse in red, fine in green) into a tiny viewport and reads it back a couple
## of frames later; the difference to the tick clock is the offset shader_time() adds. Runs once per game.
class TimeProbe extends Node:
	var _vp: SubViewport
	var _frame: int = 0
	var _ticks: float = 0.0

	func _ready() -> void:
		_vp = SubViewport.new()
		_vp.size = Vector2i(4, 4)
		_vp.transparent_bg = false
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cr := ColorRect.new()
		cr.size = Vector2(4.0, 4.0)
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment() { float t = TIME / 16.0; COLOR = vec4(floor(t) / 255.0, fract(t), 0.0, 1.0); }\n"
		var sm := ShaderMaterial.new()
		sm.shader = sh
		cr.material = sm
		_vp.add_child(cr)
		add_child(_vp)

	func _process(_d: float) -> void:
		_frame += 1
		if _frame == 3:
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			_ticks = float(Time.get_ticks_usec()) / 1.0e6
		elif _frame == 6:
			var img: Image = _vp.get_texture().get_image()
			if img != null and not img.is_empty():
				var c: Color = img.get_pixel(1, 1)
				var t_shader: float = round(c.r * 255.0) * 16.0 + c.g * 16.0
				MilitaryPeople._toff = fposmod(t_shader - _ticks, 3600.0)
				if OS.get_cmdline_user_args().has("--mil-log"):
					print("[mil] shader clock: TIME %.2f at ticks %.2f -> offset %.2f" % [t_shader, _ticks, MilitaryPeople._toff])
			set_process(false)
			queue_free()


# ------------------------------------------------------------------ a countryside tile: checkpoints, patrols, halts

## The soldiers of one tile, planned on the tile's worker thread with the village houses (`houses` is the tile's own
## "house_xf", may be empty): returns {"men": entries for AirfieldPeople.spawn, "barriers": [[pos, yaw, road width]],
## "lorries": [[pos, yaw]], "team"} or an empty Dictionary. Uses the road polylines (RoadMesh.routes_in_rect is safe
## on a worker) and the height field; never inside a house footprint (HouseMap), always on land.
static func tile_plan(org: Vector2, cell: float, houses: Array, seed_v: int, team: String, dens: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var all: Array = []
	for lst in houses:
		all.append_array(lst as Array)
	var hm := AirfieldPeople.HouseMap.new()
	var hpos: PackedVector2Array = PackedVector2Array()
	for t in all:
		hm.add_xf(t)
		hpos.append(Vector2((t as Transform3D).origin.x, (t as Transform3D).origin.z))
	var bounds := Rect2(org + Vector2(40.0, 40.0), Vector2(cell - 80.0, cell - 80.0))
	var centre := Vector2(org.x + cell * 0.5, org.y + cell * 0.5)
	var men: Array = []
	var barriers: Array = []
	var lorries: Array = []
	var axis: bool = team == "Axis"
	var routes: Array = RoadMesh.routes_in_rect(centre, cell * 0.6) if RoadMesh.has_roads() else []
	var near_houses := func(p: Vector2, r: float) -> int:
		var cnt: int = 0
		for hp in hpos:
			if hp.distance_squared_to(p) < r * r:
				cnt += 1
		return cnt
	# ---- checkpoints: junctions (a vertex two different roads share) away from the villages
	var want_cp: int = (1 if rng.randf() < 0.55 else 0) + (1 if (dens > 1.4 and rng.randf() < 0.4) else 0)
	if want_cp > 0 and not routes.is_empty():
		var junc: Dictionary = {}
		for r in routes:
			var rk: String = str(r["k"])
			if rk == "motorway":
				continue
			var pts: PackedVector2Array = r["pts"]
			for i in pts.size():
				var p: Vector2 = pts[i]
				if not bounds.has_point(p):
					continue
				var nb: Vector2 = pts[i + 1] if i + 1 < pts.size() else pts[maxi(i - 1, 0)]
				var key := Vector2i(roundi(p.x / 3.0), roundi(p.y / 3.0))
				var arr: Array = junc.get(key, [])
				arr.append([int(r["idx"]), p, (nb - p).normalized() if nb.distance_to(p) > 0.5 else Vector2(1.0, 0.0), rk])
				junc[key] = arr
		var cands: Array = []
		for key in junc.keys():
			var arr2: Array = junc[key]
			var ids: Dictionary = {}
			for a in arr2:
				ids[int(a[0])] = true
			if ids.size() >= 2 or arr2.size() >= 3:
				cands.append(arr2[0])
		if cands.size() < want_cp:
			# the Kent / Normandy road data is simplified (few vertices): a crossroads is then where two polylines cross
			_crossings(routes, bounds, cands)
		if OS.get_cmdline_user_args().has("--mil-log"):
			print("[mil] tile %.0f, %.0f: %d routes, %d vertices in bounds, %d junctions, want %d checkpoints" % [centre.x, centre.y, routes.size(), junc.size(), cands.size(), want_cp])
		AirfieldPeople._shuffle(cands, rng)
		var tried: int = 0
		var chosen: Array = []
		for cd in cands:
			if chosen.size() >= want_cp or tried >= 14:
				break
			tried += 1
			var jp: Vector2 = cd[1]
			var dd: Vector2 = cd[2]
			if int(near_houses.call(jp, 110.0)) > 6:
				continue                                  # that is a village, not a crossroads in the country
			var too_close: bool = false
			for ch in chosen:
				if (ch as Vector2).distance_to(jp) < 250.0:
					too_close = true
			if too_close or GroundKit.raw_y(jp.x, jp.y) <= 1.0:
				continue
			var w: float = float(RoadMesh.WIDTHS.get(str(cd[3]), 6.5))
			var ncp: int = clampi(int(round(1.6 + dens * 0.9)), 2, 4)
			var spots: Array = checkpoint_spots(jp, dd, w, ncp)
			var placed: int = 0
			for sp in spots:
				var q: Vector2 = sp[0]
				if not AirfieldPeople._town_free(hm, q, bounds):
					continue
				var dress: int = AirfieldPeople.CIV_SUIT if axis else (AirfieldPeople.CIV_HOME_GUARD if rng.randf() < 0.75 else DRESS_PLAIN)
				men.append(_entry(q, sp[1], int(sp[2]), dress, true))
				placed += 1
			if placed == 0:
				continue
			chosen.append(jp)
			var bpos: Vector2 = jp + dd * 10.0
			barriers.append([Vector3(bpos.x, GroundKit.ground_y(bpos.x, bpos.y), bpos.y), atan2(dd.x, dd.y), w])
			if OS.get_cmdline_user_args().has("--mil-log"):
				print("[mil] checkpoint %s at %.0f, %.0f (%d men, road %s)" % [team, jp.x, jp.y, placed, str(cd[3])])
	# ---- a roadside halt: lorries on the verge of a straight, quiet stretch, men stood about them
	var halt_p: float = 0.18 if dens < 1.0 else (0.3 if dens < 2.0 else 0.38)
	if not routes.is_empty() and rng.randf() < halt_p:
		var ridx: Array = range(routes.size())
		AirfieldPeople._shuffle(ridx, rng)
		var done_halt: bool = false
		for ri in ridx:
			if done_halt:
				break
			var rt: Dictionary = routes[int(ri)]
			var rk2: String = str(rt["k"])
			if rk2 == "motorway" or rk2 == "trunk":
				continue
			var pts2: PackedVector2Array = rt["pts"]
			var start: int = rng.randi() % maxi(pts2.size() - 1, 1)
			for off in pts2.size() - 1:
				var si: int = (start + off) % (pts2.size() - 1)
				var a0: Vector2 = pts2[si]
				var a1: Vector2 = pts2[si + 1]
				if a0.distance_to(a1) < 70.0:
					continue
				var mid: Vector2 = Geometry2D.get_closest_point_to_segment(centre, a0, a1)     # a long simplified segment: its part nearest the tile's middle
				if mid.distance_to(a0) < 35.0 or mid.distance_to(a1) < 35.0:
					mid = (a0 + a1) * 0.5
				if not bounds.has_point(mid) or int(near_houses.call(mid, 120.0)) > 3:
					continue
				var dh: Vector2 = (a1 - a0).normalized()
				var wh: float = float(RoadMesh.WIDTHS.get(rk2, 6.5))
				var nl: int = 3 if dens >= 1.5 else 2
				var side: float = 1.0 if rng.randf() < 0.5 else -1.0
				var latv := Vector2(dh.y, -dh.x) * side
				var ok: bool = GroundKit.raw_y(mid.x, mid.y) > 1.0
				var lpos: Array = []
				for k in nl:
					var along: float = (float(k) - float(nl - 1) * 0.5) * 11.0
					var lp: Vector2 = mid + dh * along + latv * (wh * 0.5 + 2.4)
					for s in [-4.4, -2.0, 0.0, 2.0, 4.4]:
						for lt in [-1.3, 0.0, 1.3]:
							var q2: Vector2 = lp + dh * float(s) + Vector2(dh.y, -dh.x) * float(lt)
							if not AirfieldPeople._town_free(hm, q2, bounds):
								ok = false
					if absf(GroundKit.raw_y(lp.x + dh.x * 5.0, lp.y + dh.y * 5.0) - GroundKit.raw_y(lp.x - dh.x * 5.0, lp.y - dh.y * 5.0)) > 1.2:
						ok = false
					lpos.append(lp)
				if not ok:
					continue
				for lp2 in lpos:
					var lv: Vector2 = lp2
					lorries.append([Vector3(lv.x, GroundKit.ground_y(lv.x, lv.y) + 0.02, lv.y), atan2(-dh.x, -dh.y)])
				var nm: int = clampi(int(round(2.0 + dens * 1.6)), 4, 7)
				var hs: Array = halt_spots(mid, dh, wh, side, nl, nm)
				for h in hs:
					var q3: Vector2 = h[0]
					if AirfieldPeople._town_free(hm, q3, bounds):
						men.append(_entry(q3, h[1], int(h[2]), DRESS_PLAIN + rng.randi() % 4, true))
				done_halt = true
				if OS.get_cmdline_user_args().has("--mil-log"):
					print("[mil] halt %s at %.0f, %.0f (%d lorries, %d men)" % [team, mid.x, mid.y, nl, hs.size()])
				break
	# ---- coastal foot patrols: pairs marching a beat along the beach or the cliff top
	var npat: int = _patrols(men, hm, bounds, centre, cell, rng, dens)
	if men.is_empty() and lorries.is_empty():
		return {}
	if npat > 0 and OS.get_cmdline_user_args().has("--mil-log"):
		print("[mil] %d coastal patrols %s in tile at %.0f, %.0f" % [npat, team, centre.x, centre.y])
	return {"men": men, "barriers": barriers, "lorries": lorries, "team": team, "seed": seed_v + 5}


## Crossroads from polylines that cross each other (not at a shared vertex): appends [line idx, point, unit direction of the
## first road there, kind] to `cands`. Only segments that touch the bounds, at most 300 of them, so the pair test stays small.
static func _crossings(routes: Array, bounds: Rect2, cands: Array) -> void:
	var segs: Array = []
	for r in routes:
		var rk: String = str(r["k"])
		if rk == "motorway":
			continue
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not Rect2(a, Vector2.ZERO).expand(b).intersects(bounds):
				continue
			segs.append([int(r["idx"]), a, b, rk])
			if segs.size() >= 300:
				break
		if segs.size() >= 300:
			break
	for i in segs.size():
		var s1: Array = segs[i]
		for j in range(i + 1, segs.size()):
			var s2: Array = segs[j]
			if int(s1[0]) == int(s2[0]):
				continue
			var ip: Variant = Geometry2D.segment_intersects_segment(s1[1], s1[2], s2[1], s2[2])
			if ip == null:
				continue
			var q: Vector2 = ip
			if not bounds.has_point(q):
				continue
			var dd: Vector2 = ((s1[2] as Vector2) - (s1[1] as Vector2)).normalized()
			cands.append([int(s1[0]), q, dd, str(s1[3])])


## A standing man's entry (see AirfieldPeople.spawn): ground height from the height field (worker-safe).
static func _entry(p: Vector2, face: Vector2, kind: int, dress: int, soldier: bool) -> Array:
	var gy: float = GroundKit.ground_y(p.x, p.y)
	var f: Vector2 = face.normalized() if face.length() > 0.01 else Vector2(0.0, 1.0)
	return [Vector3(p.x, 0.0, p.y), Vector3(f.x, 0.0, f.y), kind, 0.0, -1.0, 0.0, soldier, null, 0.0, gy, gy, dress]


## A rifle-carrying MARCH pair's beat entry: both ends' ground heights are stored (indices 9 and 10).
static func _march(p: Vector2, dir: Vector2, ln: float, ph: float, dress: int) -> Array:
	var p1: Vector2 = p + dir * ln
	return [Vector3(p.x, 0.0, p.y), Vector3(dir.x, 0.0, dir.y), Kind.MARCH, ln, ph, 1.45, true, null, 0.0, GroundKit.ground_y(p.x, p.y), GroundKit.ground_y(p1.x, p1.y), dress]


## Find a stretch of shore (beach, or a cliff top up to 140 m: Scatter.find_shore only knows the low beaches) with its
## inland walking line and plan pairs marching along it. Returns how many pairs.
static func _patrols(men: Array, hm: AirfieldPeople.HouseMap, bounds: Rect2, centre: Vector2, cell: float, rng: RandomNumberGenerator, dens: float) -> int:
	# coastal at all? a coarse grid of the tile: some water and some land
	var wet: int = 0
	var dry: int = 0
	for gz in 5:
		for gx in 5:
			var px: float = centre.x + (float(gx) - 2.0) * cell * 0.2
			var pz: float = centre.y + (float(gz) - 2.0) * cell * 0.2
			if GroundKit.raw_y(px, pz) < 0.6:
				wet += 1
			else:
				dry += 1
	if wet == 0 or dry == 0:
		return 0
	var want: int = 1 + (1 if (dens > 1.4 and rng.randf() < 0.6) else 0)
	var got: int = 0
	var shots: Array = []
	for tries in 70:
		if got >= want:
			break
		var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.end.y))
		var h: float = GroundKit.raw_y(p.x, p.y)
		if h < 1.0 or h > 140.0:
			continue
		var wd: Vector3 = GroundKit.water_dir(Vector3(p.x, 0.0, p.y), 100.0)
		if wd == Vector3.ZERO:
			continue
		var w2 := Vector2(wd.x, wd.z)
		# wide open water beyond (sea, estuary): not a pond or a ditch
		if not (GroundKit.is_water(p.x + w2.x * 160.0, p.y + w2.y * 160.0) and GroundKit.is_water(p.x + w2.x * 320.0, p.y + w2.y * 320.0)):
			continue
		var dw: float = 0.0
		while dw < 120.0 and not GroundKit.is_water(p.x + w2.x * dw, p.y + w2.y * dw):
			dw += 3.0
		var stand_off: float = 9.0 if h < 12.0 else 26.0
		var base: Vector2 = p + w2 * (dw - stand_off)
		var tang := Vector2(-w2.y, w2.x)
		if rng.randf() < 0.5:
			tang = -tang
		var ln: float = rng.randf_range(70.0, 150.0)
		var okl: bool = false
		while ln >= 40.0:
			var good: bool = true
			var y0: float = GroundKit.raw_y(base.x, base.y)
			for k in int(ln / 6.0) + 1:
				var q: Vector2 = base + tang * (float(k) * 6.0)
				var qy: float = GroundKit.raw_y(q.x, q.y)
				if qy < 0.9 or absf(qy - y0) > 5.0 or not AirfieldPeople._town_free(hm, q, bounds):
					good = false
					break
				# the second man walks beside him on the sea side
				var q2: Vector2 = q + w2 * 1.5
				if not AirfieldPeople._town_free(hm, q2, bounds):
					good = false
					break
			if good:
				okl = true
				break
			ln -= 20.0
		if not okl:
			continue
		var ph: float = rng.randf()
		var dress0: int = DRESS_PLAIN + rng.randi() % 4
		men.append(_march(base, tang, ln, ph, dress0))
		men.append(_march(base + w2 * 1.5, tang, ln, ph, (dress0 + 1) % 4))
		shots.append(base)
		got += 1
	if got > 0:
		MilitaryPeople._debug_pending("patrol", shots[0] as Vector2)
	return got


## Put a planned tile into the scene (main thread, after the tile node exists): one MultiMesh for the men, a barrier
## mesh per checkpoint, a lorry mesh per halted lorry.
static func spawn_tile(tile: Node3D, plan: Dictionary, centre: Vector3) -> void:
	if plan.is_empty():
		return
	var team: String = str(plan.get("team", "Allies"))
	var men: Array = plan.get("men", [])
	if not men.is_empty():
		var mi: MultiMeshInstance3D = AirfieldPeople.spawn(tile, men, Vector3(centre.x, 0.0, centre.z), team, int(plan.get("seed", 1)), "", true)
		if mi != null:
			mi.name = "MilitaryPeople"
			mi.visibility_range_end = AirfieldPeople.TOWN_VIEW * minf(Scatter.vis_scale, 1.0)
			mi.visibility_range_end_margin = 120.0
	for b in plan.get("barriers", []):
		var bi := MeshInstance3D.new()
		bi.mesh = barrier_mesh(float(b[2]))
		bi.transform = Transform3D(Basis(Vector3.UP, float(b[1])), b[0] as Vector3)
		bi.visibility_range_end = 1500.0 * minf(Scatter.vis_scale, 1.0)
		bi.name = "CheckpointBarrier"
		tile.add_child(bi)
	for lo in plan.get("lorries", []):
		var li := MeshInstance3D.new()
		li.mesh = AirfieldAssets.truck(team)
		li.transform = Transform3D(Basis(Vector3.UP, float(lo[1])), lo[0] as Vector3)
		li.visibility_range_end = 2200.0 * minf(Scatter.vis_scale, 1.0)
		li.name = "HaltedLorry"
		tile.add_child(li)
	_debug_tile(plan)


static var _barrier_cache: Dictionary = {}


## A checkpoint's furniture, local x across the road (width `w`), z along it, the pole across the road at z = 0:
## two posts, a red-and-white pole, a pile of sandbags either side (the near one stepped), a sentry box.
static func barrier_mesh(w: float) -> ArrayMesh:
	var key: int = int(round(w * 2.0))
	if _barrier_cache.has(key):
		return _barrier_cache[key]
	var half: float = w * 0.5
	var red := Color(0.62, 0.10, 0.09)
	var white := Color(0.88, 0.87, 0.82)
	var sand := Color(0.50, 0.44, 0.31)
	var wood := Color(0.30, 0.22, 0.14)
	var parts: Array = []
	for sx in [-1.0, 1.0]:
		parts.append(GroundKit.box_part(Vector3(0.28, 1.35, 0.28), Vector3(sx * (half + 0.4), 0.675, 0.0), wood, Vector3.ZERO, false))
	var nseg: int = 6
	var span: float = w + 0.8
	for i in nseg:
		var x: float = -span * 0.5 + span * (float(i) + 0.5) / float(nseg)
		parts.append(GroundKit.box_part(Vector3(span / float(nseg), 0.14, 0.14), Vector3(x, 1.12, 0.0), red if i % 2 == 0 else white, Vector3.ZERO, false))
	# sandbag piles: courses of boxes, a wall either side of the post
	for sx in [-1.0, 1.0]:
		for course in 3:
			parts.append(GroundKit.box_part(Vector3(2.8 - 0.4 * float(course), 0.38, 1.0), Vector3(sx * (half + 2.4), 0.19 + 0.38 * float(course), 0.3), sand.darkened(0.06 * float(course % 2)), Vector3.ZERO, false))
	# the sentry box: a plank hut with a pitched look from a flat roof, door towards the road
	parts.append(GroundKit.box_part(Vector3(1.3, 2.2, 1.3), Vector3(half + 4.2, 1.1, 0.4), wood.lightened(0.05), Vector3.ZERO, false))
	parts.append(GroundKit.box_part(Vector3(1.6, 0.14, 1.6), Vector3(half + 4.2, 2.28, 0.4), wood.darkened(0.2), Vector3.ZERO, false))
	var m: ArrayMesh = GroundKit.combine(parts)
	_barrier_cache[key] = m
	return m


# ------------------------------------------------------------------ debug cameras

static var _shot_made: bool = false
static var _pending_shot: Dictionary = {}


static func _debug_pending(kind: String, p: Vector2) -> void:
	if not _pending_shot.has(kind):
		_pending_shot[kind] = Vector3(p.x, GroundKit.ground_y(p.x, p.y), p.y)


static func _debug_tile(plan: Dictionary) -> void:
	if _shot_made:
		return
	var barriers: Array = plan.get("barriers", [])
	if not barriers.is_empty():
		_debug_shot("checkpoint", (barriers[0][0] as Vector3) - Vector3(0.0, 0.0, 0.0))
	if not (plan.get("lorries", []) as Array).is_empty():
		var lo: Array = plan["lorries"]
		_debug_shot("halt", lo[0][0] as Vector3)
	if _pending_shot.has("patrol"):
		_debug_shot("patrol", _pending_shot["patrol"] as Vector3)
		_pending_shot.erase("patrol")


## --mil-shot=<gun|light|sentry|checkpoint|halt|patrol>[,<distance>[,<skip>[,<x>,<z>]]]: remembers every group of that kind
## as it is built; a ShotPicker then (once the player is placed, --mil-pick=<frame>, default 500) puts a held camera on
## the one nearest the player (or nearest the world point x, z; skipping the first <skip>), `distance` metres away.
## Hidden-desktop screenshots only.
static func _debug_shot(kind: String, tp: Vector3) -> void:
	if _shot_made:
		return
	var arg: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mil-shot"):
			arg = a
	if arg == "":
		return
	var parts: PackedStringArray = arg.substr(10).trim_prefix("=").split(",")
	if parts.size() == 0 or String(parts[0]) != kind:
		return
	_cands.append(tp)
	if _picker == null or not is_instance_valid(_picker):
		_picker = ShotPicker.new()
		_picker.kind = kind
		_picker.parts = parts
		GroundKit.tree().root.add_child.call_deferred(_picker)


static var _cands: Array = []
static var _picker: Node = null


class ShotPicker extends Node:
	var kind: String = ""
	var parts: PackedStringArray = PackedStringArray()
	var _at_frame: int = 500

	func _ready() -> void:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--mil-pick="):
				_at_frame = int(a.substr(11))

	func _process(_d: float) -> void:
		if Engine.get_frames_drawn() < _at_frame:
			return
		set_process(false)
		var back: float = float(parts[1]) if parts.size() > 1 and String(parts[1]).is_valid_float() else 14.0
		var skip: int = int(parts[2]) if parts.size() > 2 and String(parts[2]).is_valid_int() else 0
		var ref := Vector3.INF
		if parts.size() > 4 and String(parts[3]).is_valid_float() and String(parts[4]).is_valid_float():
			ref = Vector3(float(parts[3]), 0.0, float(parts[4]))
		else:
			for nd in get_tree().get_nodes_in_group("aircraft"):
				var pa: Aircraft = nd as Aircraft
				if pa != null and pa.player_controlled:
					ref = pa.global_position
					break
		var list: Array = MilitaryPeople._cands.duplicate()
		if ref != Vector3.INF:
			list.sort_custom(func(x: Vector3, y: Vector3) -> bool:
				return Vector2(x.x - ref.x, x.z - ref.z).length() < Vector2(y.x - ref.x, y.z - ref.z).length())
		if list.is_empty():
			print("[mil-shot] no %s built" % kind)
			queue_free()
			return
		var tp: Vector3 = list[mini(skip, list.size() - 1)]
		# the terrain only streams round the player: fly him over the group and give it a few hundred frames to arrive
		for nd in get_tree().get_nodes_in_group("aircraft"):
			var pa2: Aircraft = nd as Aircraft
			if pa2 != null and pa2.player_controlled:
				pa2.reset_pose(Vector3(tp.x, GroundKit.ground_y(tp.x, tp.z) + 250.0, tp.z), 0.0, true)
				break
		await get_tree().create_timer(14.0).timeout
		var look: Vector3 = tp + Vector3(0.0, 1.0, 0.0)
		var cp: Vector3 = look + Vector3(back * 0.55, back * 0.28, back * 0.8)
		var cam := AirfieldPeople.TownShot.new()
		cam.fov = 40.0
		cam.transform = Transform3D(Basis.looking_at(look - cp, Vector3.UP), cp)
		cam.hold_s = 900.0
		get_tree().root.add_child(cam)
		MilitaryPeople._shot_made = true
		var dist: float = Vector2(tp.x - ref.x, tp.z - ref.z).length() if ref != Vector3.INF else -1.0
		print("[mil-shot] %s at %.0f, %.0f from %.0f m (%d candidates, %.0f m from the player)" % [kind, tp.x, tp.z, back, list.size(), dist])
		queue_free()


# ------------------------------------------------------------------ --mil-demo (hidden-desktop screenshots)

static var _demo_made: bool = false


static func _ensure_demo() -> void:
	if _demo_made:
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mil-demo"):
			_demo_made = true
			var dn := DemoNode.new()
			dn.spec = a.substr(10).trim_prefix("=").split(",")
			GroundKit.tree().root.add_child.call_deferred(dn)


## --mil-demo=<gun|checkpoint|halt|patrol>[,<distance>[,<Allies|Axis>]]: builds that group on open ground 70 m ahead of the
## player (a grey strip for the road), through the same functions the tile plan uses, and holds a camera on it. The
## real tile plans depend on the road data, which is sparse in Kent: this is the reproducible view of the same thing.
class DemoNode extends Node:
	var spec: PackedStringArray = PackedStringArray()

	func _process(_d: float) -> void:
		if Engine.get_frames_drawn() < 1000:
			return
		var pa: Aircraft = null
		for nd in get_tree().get_nodes_in_group("aircraft"):
			if (nd as Aircraft) != null and (nd as Aircraft).player_controlled:
				pa = nd as Aircraft
				break
		if pa == null:
			return
		set_process(false)
		var kind: String = str(spec[0]) if spec.size() > 0 else "checkpoint"
		var back: float = float(spec[1]) if spec.size() > 1 and String(spec[1]).is_valid_float() else 16.0
		var team: String = str(spec[2]) if spec.size() > 2 else "Allies"
		var f: Vector3 = pa.get_forward()
		f.y = 0.0
		f = f.normalized() if f.length() > 0.01 else Vector3(0.0, 0.0, -1.0)
		# open land: turn until the strip (and 45 m either side of it) is above the waterline
		var pf: Vector3 = f
		for k in 16:
			var ang: float = atan2(f.z, f.x) + TAU * float(k) / 16.0
			var tf := Vector3(cos(ang), 0.0, sin(ang))
			var tb: Vector3 = pa.global_position + tf * 70.0
			var td := Vector3(-tf.z, 0.0, tf.x)
			var land: bool = true
			for q in [-45.0, -20.0, 0.0, 20.0, 45.0]:
				for r in [-25.0, 0.0, 25.0]:
					var pq: Vector3 = tb + td * float(q) + tf * float(r)
					if GroundKit.raw_y(pq.x, pq.z) < 2.0:
						land = false
			if land:
				pf = tf
				break
		f = pf
		var base: Vector3 = pa.global_position + f * 70.0
		base.y = GroundKit.ground_y(base.x, base.z)
		var d := Vector2(-f.z, f.x)                      # the road runs across the player's view
		var jp := Vector2(base.x, base.z)
		var host: Node3D = pa.get_parent() as Node3D
		var road := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(6.5, 0.06, 90.0)
		road.mesh = bm
		var mt := StandardMaterial3D.new()
		mt.albedo_color = Color(0.25, 0.25, 0.26)
		road.material_override = mt
		road.transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), base + Vector3(0.0, 0.05, 0.0))
		host.add_child(road)
		var men: Array = []
		var barriers: Array = []
		var lorries: Array = []
		var look: Vector3 = base
		var axis: bool = team == "Axis"
		match kind:
			"checkpoint":
				for sp in MilitaryPeople.checkpoint_spots(jp, d, 6.5, 4):
					men.append(MilitaryPeople._entry(sp[0], sp[1], int(sp[2]), AirfieldPeople.CIV_SUIT if axis else AirfieldPeople.CIV_HOME_GUARD, true))
				var bp: Vector2 = jp + d * 10.0
				barriers.append([Vector3(bp.x, base.y, bp.y), atan2(d.x, d.y), 6.5])
				look = base + Vector3(d.x, 0.0, d.y) * 7.0
			"halt":
				for k in 3:
					var lp: Vector2 = jp + d * ((float(k) - 1.0) * 11.0) + Vector2(d.y, -d.x) * (6.5 * 0.5 + 2.4)
					lorries.append([Vector3(lp.x, GroundKit.ground_y(lp.x, lp.y) + 0.02, lp.y), atan2(-d.x, -d.y)])
				for h in MilitaryPeople.halt_spots(jp, d, 6.5, 1.0, 3, 7):
					men.append(MilitaryPeople._entry(h[0], h[1], int(h[2]), k_dress(men.size()), true))
			"patrol":
				men.append(MilitaryPeople._march(jp - d * 12.0, d, 24.0, 0.3, 0))
				men.append(MilitaryPeople._march(jp - d * 12.0 + Vector2(f.x, f.z) * 1.5, d, 24.0, 0.3, 1))
		if kind == "gun":
			var gt: String = "88mm" if (spec.size() > 3 and str(spec[3]) == "88mm") else "bofors"
			var g: AAGun = AAGun.create(gt, team)
			g.active = false
			g.position = base
			host.add_child(g)
			var made: int = MilitaryPeople._make_cluster(host, team, [{"kind": "gun", "pos": base, "basis": Basis.IDENTITY, "gtype": gt, "guns": 0}], 77, 2.2)
			print("[mil-demo] crew of %d men made for %s" % [made, team])
			look = base + Vector3(0.0, 0.0, 6.0)
		else:
			MilitaryPeople.spawn_tile(host, {"men": men, "barriers": barriers, "lorries": lorries, "team": team, "seed": 5}, base)
		var lk: Vector3 = look + Vector3(0.0, 1.0, 0.0)
		var cp: Vector3 = lk + Vector3(back * 0.55, back * 0.28, back * 0.8)
		var cam := AirfieldPeople.TownShot.new()
		cam.fov = 40.0
		cam.transform = Transform3D(Basis.looking_at(lk - cp, Vector3.UP), cp)
		cam.hold_s = 900.0
		get_tree().root.add_child(cam)
		print("[mil-demo] %s %s at %.0f, %.0f, camera %.0f m" % [team, kind, base.x, base.z, back])

	static func k_dress(i: int) -> int:
		return i % 4
