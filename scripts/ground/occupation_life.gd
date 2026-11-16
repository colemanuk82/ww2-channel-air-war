extends RefCounted

## Phase 5 - the French side of the living towns. Two small jobs, both run on the town layout's worker thread
## (or the main thread for a town built straight away) and both cheap:
##
## 1. The German presence in an Axis-held French town: a Kommandantur pair of sentries either side of the town
##    hall's door, a two-man patrol on the square, and a sentry pair at the station. Nothing is added to a town held by
##    the Allies, and nothing to a town smaller than size 2. The flag over the town hall is NOT done (it needs a flag
##    prop, which the town-model kit does not have yet; see docs/STATUS.md).
## 2. The French civilians: British-only outfits (the constable, the ARP warden and the Home Guard) are turned into
##    French civilians wherever a town is continental, so no British police or wardens walk the streets of France.
##    There is no gendarme outfit in the dress set, so the French constable is a dark suit for now.
##
## The Luftwaffe airfields already get their crews from AirfieldPeople.populate (team "Axis"); this file adds nothing
## there. Garrison men are soldiers (the soldier bit), so they wear field grey and a Stahlhelm on the Axis side.


## The English shore runs along this line (the same keys as GroundKit.side_at_latlon). Used for the continental test.
static func _channel_mid(lon: float) -> float:
	var keys: Array = [[-4.6, 50.0], [-1.0, 50.25], [0.0, 50.38], [0.8, 50.85], [1.2, 51.05], [1.5, 51.3]]
	if lon <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if lon >= float(a[0]) and lon <= float(b[0]):
			var f: float = (lon - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), f)
	return float(keys[keys.size() - 1][1])


## True for a town on the continent (France, Belgium, the Netherlands): east of 1.5 E (except East Anglia, which reaches
## 1.75 E north of 51.45 N), or south of the Channel shore by more than 0.15 degrees (so Dieppe and Le Havre count and
## the Kent coast does not). Used to decide that the British-only outfits must not walk the streets there.
static func continental(lat: float, lon: float) -> bool:
	if lon >= 1.5:
		return not (lat > 51.45 and lon < 2.0)
	return lat < _channel_mid(lon) - 0.15


## Turn the British-only civilians of a continental town into French ones, in place. Returns how many were changed.
## Constable -> dark suit; ARP warden -> tweed jacket; Home Guard -> tweed jacket and no rifle (no soldier bit).
## Works on the men entries of AirfieldPeople.town_plan (dress at index 11, soldier flag at index 6).
static func civilise(men: Array, lat: float, lon: float) -> int:
	if not continental(lat, lon):
		return 0
	var n: int = 0
	for e in men:
		var m: Array = e
		if m.size() <= 11:
			continue
		var dress: int = int(m[11])
		if dress == AirfieldPeople.CIV_POLICE:
			m[11] = AirfieldPeople.CIV_GENDARME       # c1: dark blue tunic and kepi
		elif dress == AirfieldPeople.CIV_ARP:
			m[11] = AirfieldPeople.CIV_JACKET
		elif dress == AirfieldPeople.CIV_HOME_GUARD:
			m[11] = AirfieldPeople.CIV_JACKET
			m[6] = false
		else:
			continue
		n += 1
	return n


## The German garrison of an Axis-held town (called from AirfieldPeople.town_plan before the street fill, with the
## same HouseMap so nobody is placed in a building). Returns the number of men added. Sentries use the spot finder
## _town_stand, which refuses a spot inside a house, so a sentry that would stand in a wall is simply left out.
static func garrison(men: Array, hm, center: Vector3, d: Dictionary, size: int, team: String, dens: float,
		rng: RandomNumberGenerator, bounds: Rect2) -> int:
	if team != "Axis" or size < 2:
		return 0
	var before: int = men.size()
	for cv in d.get("civic", []):
		var cd: Dictionary = cv
		if not cd.has("pos"):
			continue
		var kind: String = str(cd.get("kind", ""))
		if kind != "townhall" and kind != "station":
			continue
		var cp: Vector3 = cd["pos"]
		var cpv := Vector2(cp.x, cp.z)
		var yaw: float = float(cd.get("yaw", 0.0))
		var fwd := Vector2(cos(yaw), sin(yaw))          # the door faces this way (the town hall's yaw, as scatter lays it)
		var side := Vector2(-fwd.y, fwd.x)
		if kind == "townhall":
			# the Kommandantur: a sentry either side of the door, facing out, and a two-man patrol across the square
			AirfieldPeople._town_stand(men, hm, cpv + fwd * 30.0 + side * 4.0, fwd, AirfieldPeople.Kind.SALUTE, AirfieldPeople.CIV_SUIT, true, bounds)
			AirfieldPeople._town_stand(men, hm, cpv + fwd * 30.0 - side * 4.0, fwd, AirfieldPeople.Kind.SALUTE, AirfieldPeople.CIV_SUIT, true, bounds)
			if dens >= 1.0 and rng.randf() < 0.8:
				AirfieldPeople._town_beat(men, hm, cpv + fwd * 36.0 - side * 12.0, side, 24.0, AirfieldPeople.Kind.WALK, 0.0, AirfieldPeople.CIV_SUIT, true, bounds)
		else:
			# the station: a sentry either side of the entrance
			AirfieldPeople._town_stand(men, hm, cpv + side * 14.0, -side, AirfieldPeople.Kind.SALUTE, AirfieldPeople.CIV_SUIT, true, bounds)
			AirfieldPeople._town_stand(men, hm, cpv - side * 14.0, side, AirfieldPeople.Kind.SALUTE, AirfieldPeople.CIV_SUIT, true, bounds)
	return men.size() - before
