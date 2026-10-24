class_name ModelSpecs
extends RefCounted
## Spec dictionaries for PlaneBuilder (metres, nose toward -Z). get_spec(id) returns {} if unknown.

const IDS := ["hurricane", "typhoon", "mosquito", "p51", "p47", "bf109", "fw190", "me262", "lancaster", "b26", "ju87", "he111", "ju88", "bf110", "do17", "ju52", "fw200", "blenheim", "tempest", "p38", "defiant", "b25", "a20", "c47", "dh89"]

const RAF_TOP := Color(0.18, 0.28, 0.14)
const RAF_PATCH := Color(0.33, 0.26, 0.16)
const RAF_UNDER := Color(0.66, 0.75, 0.72)
const OD_TOP := Color(0.28, 0.30, 0.18)
const OD_PATCH := Color(0.22, 0.25, 0.15)
const OD_UNDER := Color(0.62, 0.64, 0.62)
const LW_TOP := Color(0.32, 0.36, 0.34)
const LW_PATCH := Color(0.2, 0.27, 0.22)
const LW_UNDER := Color(0.58, 0.7, 0.78)


static func get_spec(id: String) -> Dictionary:
	var spec: Dictionary = _spec_for(id)
	if not spec.is_empty():
		spec["id"] = id        # lets PlaneBuilder fit the underside gear that belongs to this type
	return spec


static func _spec_for(id: String) -> Dictionary:
	match id:
		"hurricane": return hurricane()
		"typhoon": return typhoon()
		"mosquito": return mosquito()
		"p51": return p51()
		"p47": return p47()
		"bf109": return bf109()
		"fw190": return fw190()
		"me262": return me262()
		"lancaster": return lancaster()
		"b26": return b26()
		"ju87": return ju87()
		"he111": return he111()
		"ju88": return ju88()
		"bf110": return bf110()
		"do17": return do17()
		"ju52": return ju52()
		"fw200": return fw200()
		"blenheim": return blenheim()
		"tempest": return tempest()
		"p38": return p38()
		"defiant": return defiant()
		"b25": return b25()
		"a20": return a20()
		"c47": return c47()
		"dh89": return dh89()
	return {}


static func hurricane() -> Dictionary:
	return {
		"scale": 1.1, "nation": "RAF",
		"colors": {"top": RAF_TOP, "under": RAF_UNDER, "patch": RAF_PATCH},
		"fus": {"z0": -3.9, "z1": 5.0, "hw": 0.55, "hh": 0.8, "cy": 0.0, "profile": "hump"},
		"wing": {"root_x": 0.45, "half": 5.65, "y": -0.5, "dihedral": 0.3, "cr": 3.3, "ct": 1.6, "le_z": -1.6, "sweep": 0.3, "thick": 0.15},
		"tail": {"z": 4.0, "span": 1.8, "cr": 1.5, "ct": 0.9, "y": 0.3},
		"fin": {"z": 3.4, "y": 0.3, "h": 2.1, "cr": 2.0, "ct": 1.1},
		"nose_prop": {"z": -3.95, "r": 1.7, "blades": 3, "spinner": 0.3},
		"canopies": [[[-1.4, 0.1, 0.1, 0.9], [-0.9, 0.4, 0.36, 0.98], [-0.2, 0.42, 0.4, 1.02], [0.7, 0.34, 0.3, 0.96], [1.6, 0.1, 0.12, 0.8]]],
		"extras": [],
		"gear": {"x": 1.6, "y": -0.45, "z": -0.6, "len": 0.9, "r": 0.33},
		"tail_wheel": [-0.1, 4.8],
		"guns": [2.3, -0.3, -2.1], "eye": Vector3(0, 1.3, 0.2),
		"mark_z": 3.0, "mark_t": 0.55,
	}


static func typhoon() -> Dictionary:
	return {
		"scale": 1.1, "nation": "RAF", "stripes": true,
		"colors": {"top": RAF_TOP, "under": RAF_UNDER, "patch": RAF_PATCH},
		"fus": {"z0": -3.9, "z1": 5.2, "hw": 0.65, "hh": 0.8, "cy": 0.05, "profile": "inline"},
		"wing": {"root_x": 0.5, "half": 5.83, "y": -0.45, "dihedral": 0.25, "cr": 3.7, "ct": 1.9, "le_z": -1.7, "sweep": 0.3, "thick": 0.16},
		"tail": {"z": 4.2, "span": 2.1, "cr": 1.7, "ct": 1.0, "y": 0.3},
		"fin": {"z": 3.5, "y": 0.3, "h": 2.2, "cr": 2.2, "ct": 1.2},
		"nose_prop": {"z": -4.0, "r": 2.0, "blades": 4, "spinner": 0.34},
		"canopies": [[[-1.5, 0.12, 0.1, 0.9], [-1.0, 0.4, 0.38, 1.0], [-0.1, 0.44, 0.44, 1.05], [0.9, 0.4, 0.4, 1.0], [1.9, 0.1, 0.14, 0.85]]],
		"extras": [],
		"gear": {"x": 1.7, "y": -0.45, "z": -0.6, "len": 0.95, "r": 0.36},
		"tail_wheel": [-0.1, 5.0],
		"guns": [2.6, -0.3, -2.2], "eye": Vector3(0, 1.35, 0.3),
		"mark_z": 3.2, "mark_t": 0.6,
	}


static func mosquito() -> Dictionary:
	return {
		"scale": 1.1, "nation": "RAF", "stripes": true,
		"colors": {"top": Color(0.28, 0.33, 0.28), "under": RAF_UNDER, "patch": Color(0.2, 0.28, 0.2)},
		"fus": {"z0": -4.2, "z1": 6.2, "hw": 0.55, "hh": 0.8, "cy": 0.05, "profile": "inline"},
		"wing": {"root_x": 0.55, "half": 8.2, "y": -0.4, "dihedral": 0.35, "cr": 3.1, "ct": 1.5, "le_z": -1.4, "sweep": 0.2, "thick": 0.14},
		"tail": {"z": 5.2, "span": 3.0, "cr": 1.8, "ct": 1.0, "y": 0.3},
		"fin": {"z": 4.6, "y": 0.3, "h": 2.2, "cr": 2.2, "ct": 1.2},
		"engines": [
			{"x": -2.5, "y": -0.35, "z0": -3.2, "z1": 1.4, "r": 0.62, "prop_r": 1.7, "blades": 3},
			{"x": 2.5, "y": -0.35, "z0": -3.2, "z1": 1.4, "r": 0.62, "prop_r": 1.7, "blades": 3}],
		"canopies": [[[-3.9, 0.15, 0.15, 0.05], [-3.2, 0.42, 0.45, 0.2], [-2.2, 0.5, 0.58, 0.4], [-1.0, 0.46, 0.5, 0.7], [-0.3, 0.12, 0.15, 0.7]]],
		"gear": {"x": 2.5, "y": -0.8, "z": -1.0, "len": 0.9, "r": 0.35},
		"tail_wheel": [-0.1, 6.0],
		"guns": [0.3, -0.5, -4.0], "eye": Vector3(0, 1.1, -2.2),
		"mark_z": 4.4, "mark_t": 0.8,
	}


static func p51() -> Dictionary:
	return {
		"scale": 1.1, "nation": "USAAF", "stripes": true,
		"colors": {"top": Color(0.72, 0.74, 0.76), "under": Color(0.7, 0.72, 0.74), "patch": Color(0.62, 0.64, 0.66)},
		"fus": {"z0": -3.8, "z1": 5.0, "hw": 0.5, "hh": 0.65, "cy": 0.05, "profile": "inline"},
		"wing": {"root_x": 0.45, "half": 5.19, "y": -0.4, "dihedral": 0.3, "cr": 2.6, "ct": 1.2, "le_z": -1.4, "sweep": 0.3, "thick": 0.12},
		"tail": {"z": 4.0, "span": 1.9, "cr": 1.4, "ct": 0.8, "y": 0.25},
		"fin": {"z": 3.5, "y": 0.25, "h": 1.75, "cr": 1.9, "ct": 1.0, "fillet": 1.1},
		"nose_prop": {"z": -3.9, "r": 1.7, "blades": 4, "spinner": 0.3},
		"canopies": [[[-0.9, 0.1, 0.1, 0.78], [-0.5, 0.38, 0.34, 0.84], [0.5, 0.4, 0.4, 0.88], [1.5, 0.3, 0.3, 0.8], [2.3, 0.08, 0.1, 0.6]]],
		"extras": [
			{"t": "slice", "z0": -3.0, "z1": -1.6, "col": "olive"}],
		"gear": {"x": 1.6, "y": -0.4, "z": -0.5, "len": 0.8, "r": 0.3},
		"tail_wheel": [-0.1, 4.7],
		"guns": [2.2, -0.3, -1.8], "eye": Vector3(0, 1.1, 0.5),
		"mark_z": 3.0, "mark_t": 0.55,
	}


static func p47() -> Dictionary:
	return {
		"scale": 1.1, "nation": "USAAF", "stripes": true,
		"colors": {"top": OD_TOP, "under": OD_UNDER, "patch": OD_PATCH},
		"fus": {"z0": -4.3, "z1": 5.8, "hw": 0.72, "hh": 0.98, "cy": 0.05, "profile": "radial"},
		"wing": {"root_x": 0.7, "half": 5.51, "y": -0.5, "dihedral": 0.3, "cr": 3.6, "ct": 1.8, "le_z": -1.8, "sweep": 0.3, "thick": 0.15},
		"tail": {"z": 4.7, "span": 2.4, "cr": 1.8, "ct": 1.0, "y": 0.3},
		"fin": {"z": 4.1, "y": 0.4, "h": 2.2, "cr": 2.4, "ct": 1.3, "fillet": 0.8},
		"nose_prop": {"z": -4.4, "r": 2.1, "blades": 4, "spinner": 0.4},
		"canopies": [[[-0.8, 0.1, 0.1, 0.95], [-0.3, 0.45, 0.42, 1.05], [0.8, 0.46, 0.44, 1.1], [2.0, 0.35, 0.3, 0.95], [2.8, 0.08, 0.1, 0.8]]],
		"extras": [],
		"gear": {"x": 1.9, "y": -0.5, "z": -0.6, "len": 1.1, "r": 0.4},
		"tail_wheel": [-0.1, 5.6],
		"guns": [2.5, -0.3, -2.3], "eye": Vector3(0, 1.4, 0.4),
		"mark_z": 3.6, "mark_t": 0.6, "mark_size": 0.65,
	}


static func bf109() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe",
		"colors": {"top": LW_TOP, "under": LW_UNDER, "patch": LW_PATCH},
		"fus": {"z0": -3.5, "z1": 4.6, "hw": 0.45, "hh": 0.6, "cy": 0.05, "profile": "inline"},
		"wing": {"root_x": 0.4, "half": 4.53, "y": -0.4, "dihedral": 0.25, "cr": 2.1, "ct": 1.1, "le_z": -1.1, "sweep": 0.1, "thick": 0.12, "round_tip": false},
		"tail": {"z": 3.75, "span": 1.35, "cr": 1.0, "ct": 0.7, "y": 0.62},
		"fin": {"z": 3.45, "y": 0.2, "h": 1.32, "cr": 1.45, "ct": 0.85, "sweep": 0.55},
		"nose_prop": {"z": -3.6, "r": 1.5, "blades": 3, "spinner": 0.3},
		"canopies": [[[-1.0, 0.1, 0.1, 0.72], [-0.6, 0.3, 0.28, 0.78], [0.2, 0.32, 0.32, 0.82], [1.0, 0.2, 0.2, 0.72], [1.4, 0.06, 0.08, 0.6]]],
		"extras": [{"t": "slice", "z0": -3.45, "z1": -2.7, "col": "yellow"}],
		"gear": {"x": 1.0, "y": -0.35, "z": -0.4, "len": 0.78, "r": 0.29, "splay": 12.0},
		"tail_wheel": [-0.1, 4.4],
		"guns": [0.5, -0.1, -2.8], "eye": Vector3(0, 1.0, 0.2),
		"mark_z": 2.6, "mark_t": 0.55, "mark_size": 0.5, "wing_mark_size": 0.6,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func fw190() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe",
		"colors": {"top": Color(0.36, 0.38, 0.34), "under": LW_UNDER, "patch": Color(0.22, 0.28, 0.22)},
		"fus": {"z0": -3.4, "z1": 4.7, "hw": 0.62, "hh": 0.7, "cy": 0.05, "profile": "radial"},
		"wing": {"root_x": 0.55, "half": 4.7, "y": -0.45, "dihedral": 0.2, "cr": 2.4, "ct": 1.1, "le_z": -1.1, "sweep": 0.2, "thick": 0.13},
		"tail": {"z": 3.9, "span": 1.6, "cr": 1.2, "ct": 0.7, "y": 0.3},
		"fin": {"z": 3.4, "y": 0.3, "h": 1.8, "cr": 1.7, "ct": 0.9},
		"nose_prop": {"z": -3.5, "r": 1.7, "blades": 3, "spinner": 0.33},
		"canopies": [[[-0.4, 0.1, 0.1, 0.78], [0.0, 0.35, 0.33, 0.88], [0.9, 0.38, 0.38, 0.9], [1.9, 0.2, 0.2, 0.75], [2.4, 0.06, 0.08, 0.6]]],
		"extras": [{"t": "slice", "z0": -3.3, "z1": -2.6, "col": "grey"}],
		"gear": {"x": 1.5, "y": -0.45, "z": -0.5, "len": 0.8, "r": 0.3},
		"tail_wheel": [-0.1, 4.5],
		"guns": [1.2, -0.2, -2.2], "eye": Vector3(0, 1.1, 0.5),
		"mark_z": 3.0, "mark_t": 0.55, "mark_size": 0.5, "wing_mark_size": 0.6,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func me262() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe",
		"colors": {"top": Color(0.27, 0.3, 0.28), "under": Color(0.55, 0.62, 0.68), "patch": Color(0.2, 0.25, 0.2)},
		"fus": {"z0": -4.9, "z1": 5.7, "hw": 0.6, "hh": 0.62, "cy": 0.05, "profile": "bomber"},
		"wing": {"root_x": 0.55, "half": 5.75, "y": -0.35, "dihedral": 0.2, "cr": 3.0, "ct": 1.4, "le_z": -1.3, "sweep": 1.6, "thick": 0.11, "round_tip": false},
		"tail": {"z": 4.7, "span": 1.9, "cr": 1.4, "ct": 0.8, "y": 0.3},
		"fin": {"z": 4.4, "y": 0.2, "h": 1.8, "cr": 1.9, "ct": 1.0},
		"engines": [
			{"x": -2.4, "y": -0.62, "z0": -2.3, "z1": 1.75, "r": 0.48, "jet": true},
			{"x": 2.4, "y": -0.62, "z0": -2.3, "z1": 1.75, "r": 0.48, "jet": true}],
		"canopies": [[[-2.4, 0.1, 0.1, 0.55], [-1.9, 0.38, 0.32, 0.7], [-0.9, 0.42, 0.38, 0.75], [0.1, 0.24, 0.22, 0.66], [0.9, 0.05, 0.08, 0.5]]],
		"gear": {"x": 1.5, "y": -0.35, "z": -0.3, "len": 0.8, "r": 0.28},
		"tail_wheel": [-0.1, 5.5],
		"guns": [0.5, -0.2, -4.6], "eye": Vector3(0, 0.95, -1.35),
		"mark_z": 3.6, "mark_t": 0.4, "mark_size": 0.55, "wing_mark_size": 0.7,
	}


static func lancaster() -> Dictionary:
	return {
		"scale": 1.1, "nation": "RAF", "outline": 0.02,
		"colors": {"top": Color(0.17, 0.25, 0.13), "under": Color(0.06, 0.06, 0.07), "patch": Color(0.3, 0.24, 0.15)},
		"fus": {"z0": -7.0, "z1": 11.0, "hw": 1.05, "hh": 1.3, "cy": 0.1, "profile": "bomber"},
		"wing": {"root_x": 1.0, "half": 15.55, "y": 0.3, "dihedral": 0.4, "cr": 5.0, "ct": 2.2, "le_z": -2.6, "sweep": 0.6, "thick": 0.14},
		"tail": {"z": 9.2, "span": 5.2, "cr": 3.0, "ct": 1.8, "y": 0.8},
		"fin": {"twin": true, "x": 2.6, "z": 9.0, "y": 0.6, "h": 3.4, "cr": 2.8, "ct": 1.6},
		"engines": [
			{"x": -4.8, "y": 0.0, "z0": -3.8, "z1": 1.6, "r": 0.8, "prop_r": 1.9, "blades": 3},
			{"x": 4.8, "y": 0.0, "z0": -3.8, "z1": 1.6, "r": 0.8, "prop_r": 1.9, "blades": 3},
			{"x": -9.2, "y": 0.05, "z0": -3.6, "z1": 1.4, "r": 0.75, "prop_r": 1.9, "blades": 3},
			{"x": 9.2, "y": 0.05, "z0": -3.6, "z1": 1.4, "r": 0.75, "prop_r": 1.9, "blades": 3}],
		"canopies": [[[-5.0, 0.2, 0.2, 0.9], [-4.2, 0.7, 0.5, 1.35], [-2.8, 0.8, 0.5, 1.5], [-1.6, 0.3, 0.25, 1.4]]],
		"extras": [
			{"t": "sphere", "pos": Vector3(0, 0.3, -6.9), "size": Vector3(0.45, 0, 0), "col": "grey"},
			{"t": "sphere", "pos": Vector3(0, 1.45, 3.0), "size": Vector3(0.5, 0, 0), "col": "grey"},
			{"t": "sphere", "pos": Vector3(0, 0.3, 11.1), "size": Vector3(0.45, 0, 0), "col": "grey"}],
		"gear": {"x": 4.8, "y": -0.5, "z": -0.2, "len": 1.5, "r": 0.65},
		"tail_wheel": [-1.0, 9.8],
		"guns": [0.5, 0.0, -6.6], "eye": Vector3(0, 1.4, -4.4),
		"mark_z": 7.2, "mark_t": 0.8, "mark_size": 1.0, "wing_mark_size": 1.3,
	}


static func b26() -> Dictionary:
	return {
		"scale": 1.1, "nation": "USAAF", "outline": 0.02, "stripes": true,
		"colors": {"top": OD_TOP, "under": OD_UNDER, "patch": OD_PATCH},
		"fus": {"z0": -5.5, "z1": 9.0, "hw": 0.95, "hh": 1.1, "cy": 0.05, "profile": "bomber"},
		"wing": {"root_x": 0.9, "half": 10.82, "y": -0.1, "dihedral": 0.3, "cr": 4.2, "ct": 2.0, "le_z": -2.0, "sweep": 0.4, "thick": 0.14},
		"tail": {"z": 7.5, "span": 2.7, "cr": 3.0, "ct": 1.5, "y": 0.5},
		"fin": {"z": 7.2, "y": 0.4, "h": 3.8, "cr": 3.2, "ct": 1.6},
		"engines": [
			{"x": -3.4, "y": -0.05, "z0": -3.9, "z1": 2.3, "r": 1.0, "prop_r": 2.3, "blades": 4},
			{"x": 3.4, "y": -0.05, "z0": -3.9, "z1": 2.3, "r": 1.0, "prop_r": 2.3, "blades": 4}],
		"canopies": [[[-4.8, 0.2, 0.2, 0.8], [-4.2, 0.6, 0.5, 1.0], [-3.0, 0.8, 0.7, 1.15], [-1.8, 0.4, 0.3, 1.1]]],
		"extras": [
			{"t": "sphere", "pos": Vector3(0, 1.3, 3.2), "size": Vector3(0.7, 0, 0), "col": "grey"},
			{"t": "sphere", "pos": Vector3(0, 0.5, 9.1), "size": Vector3(0.6, 0, 0), "col": "grey"}],
		"gear": {"x": 3.4, "y": -0.8, "z": -0.6, "len": 1.2, "r": 0.55},
		"tail_wheel": [-0.9, 8.4],
		"guns": [0.4, 0.0, -5.2], "eye": Vector3(0, 1.3, -3.5),
		"mark_z": 6.2, "mark_t": 0.82, "mark_size": 0.9, "wing_mark_size": 1.2,
	}


static func ju87() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe",
		"colors": {"top": Color(0.22, 0.28, 0.18), "under": Color(0.55, 0.68, 0.76), "patch": Color(0.14, 0.2, 0.14)},
		"fus": {"z0": -3.9, "z1": 6.4, "hw": 0.62, "hh": 0.9, "cy": 0.05, "profile": "inline"},
		"wing": {"root_x": 0.55, "half": 6.9, "y": 0.0, "dihedral": 0.2, "gull": 0.9, "cr": 3.4, "ct": 1.7, "le_z": -1.5, "sweep": 0.2, "thick": 0.15, "round_tip": false},
		"tail": {"z": 5.3, "span": 2.2, "cr": 1.5, "ct": 0.8, "y": 0.3},
		"fin": {"z": 4.9, "y": 0.3, "h": 2.6, "cr": 2.4, "ct": 1.2},
		"nose_prop": {"z": -4.0, "r": 1.7, "blades": 3, "spinner": 0.32},
		"canopies": [[[-1.6, 0.12, 0.1, 0.95], [-1.1, 0.45, 0.5, 1.05], [0.2, 0.5, 0.55, 1.1], [1.8, 0.46, 0.5, 1.05], [2.6, 0.15, 0.2, 0.95]]],
		"extras": [
			{"t": "slice", "z0": -3.7, "z1": -2.8, "col": "yellow"},
			{"t": "box", "pos": Vector3(0, -1.1, 0.4), "size": Vector3(0.4, 0.45, 1.7), "col": "dark"}],
		"gear": {"x": 1.9, "y": -0.7, "z": -0.4, "len": 1.0, "r": 0.45, "leg_w": 0.3},
		"tail_wheel": [-0.3, 6.2],
		"guns": [1.8, -0.3, -1.4], "eye": Vector3(0, 1.4, -0.6),
		"mark_z": 4.3, "mark_t": 0.8, "mark_size": 0.6, "wing_mark_size": 0.8,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func he111() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe", "outline": 0.02,
		"colors": {"top": Color(0.25, 0.30, 0.22), "under": Color(0.55, 0.68, 0.75), "patch": Color(0.18, 0.24, 0.2)},
		"fus": {"z0": -6.6, "z1": 9.8, "hw": 1.0, "hh": 1.15, "cy": 0.1, "profile": "bomber"},
		"wing": {"root_x": 0.9, "half": 11.3, "y": -0.6, "dihedral": 0.3, "cr": 4.1, "ct": 1.9, "le_z": -2.0, "sweep": 0.3, "thick": 0.14},
		"tail": {"z": 8.2, "span": 3.4, "cr": 2.3, "ct": 1.1, "y": 0.5},
		"fin": {"z": 7.6, "y": 0.5, "h": 3.3, "cr": 3.0, "ct": 1.4},
		"engines": [
			{"x": -3.7, "y": -0.55, "z0": -3.8, "z1": 2.2, "r": 0.75, "prop_r": 1.85, "blades": 3},
			{"x": 3.7, "y": -0.55, "z0": -3.8, "z1": 2.2, "r": 0.75, "prop_r": 1.85, "blades": 3}],
		"canopies": [[[-6.6, 0.15, 0.15, 0.2], [-6.0, 0.7, 0.7, 0.25], [-5.0, 0.95, 0.95, 0.45], [-3.5, 0.9, 0.7, 0.8], [-2.2, 0.5, 0.3, 1.0]]],
		"extras": [
			{"t": "box", "pos": Vector3(0, -1.35, -1.0), "size": Vector3(0.8, 0.6, 2.4), "col": "dark"},
			{"t": "sphere", "pos": Vector3(0, 1.45, 0.0), "size": Vector3(0.6, 0, 0), "col": "grey"}],
		"gear": {"x": 3.7, "y": -1.0, "z": -0.8, "len": 1.1, "r": 0.55},
		"tail_wheel": [-0.9, 9.2],
		"guns": [0.4, 0.0, -6.0], "eye": Vector3(0, 1.0, -5.0),
		"mark_z": 6.6, "mark_t": 0.8, "mark_size": 0.9, "wing_mark_size": 1.2,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func ju88() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe", "outline": 0.02,
		"colors": {"top": Color(0.22, 0.27, 0.2), "under": Color(0.53, 0.64, 0.72), "patch": Color(0.15, 0.2, 0.15)},
		"fus": {"z0": -5.2, "z1": 8.4, "hw": 0.9, "hh": 1.05, "cy": 0.1, "profile": "bomber"},
		"wing": {"root_x": 0.8, "half": 9.17, "y": -0.5, "dihedral": 0.3, "cr": 3.8, "ct": 1.8, "le_z": -1.8, "sweep": 0.3, "thick": 0.14},
		"tail": {"z": 6.9, "span": 3.2, "cr": 2.1, "ct": 1.0, "y": 0.4},
		"fin": {"z": 6.5, "y": 0.4, "h": 2.7, "cr": 2.8, "ct": 1.4},
		"engines": [
			{"x": -3.6, "y": -0.5, "z0": -3.5, "z1": 1.8, "r": 0.8, "prop_r": 1.8, "blades": 3},
			{"x": 3.6, "y": -0.5, "z0": -3.5, "z1": 1.8, "r": 0.8, "prop_r": 1.8, "blades": 3}],
		"canopies": [[[-5.2, 0.15, 0.15, 0.25], [-4.7, 0.6, 0.6, 0.3], [-3.5, 0.8, 0.8, 0.5], [-2.3, 0.55, 0.4, 0.85], [-1.6, 0.15, 0.15, 0.9]]],
		"extras": [{"t": "box", "pos": Vector3(0, -1.2, -1.6), "size": Vector3(0.8, 0.55, 2.2), "col": "dark"}],
		"gear": {"x": 3.6, "y": -0.9, "z": -0.6, "len": 1.0, "r": 0.5},
		"tail_wheel": [-0.8, 7.8],
		"guns": [0.4, 0.0, -5.0], "eye": Vector3(0, 1.1, -3.2),
		"mark_z": 5.4, "mark_t": 0.8, "mark_size": 0.8, "wing_mark_size": 1.1,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func bf110() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe", "outline": 0.02,
		"colors": {"top": LW_TOP, "under": LW_UNDER, "patch": LW_PATCH},
		"fus": {"z0": -5.2, "z1": 6.4, "hw": 0.6, "hh": 0.8, "cy": 0.1, "profile": "bomber"},
		"wing": {"root_x": 0.6, "half": 8.15, "y": -0.5, "dihedral": 0.2, "cr": 3.0, "ct": 1.4, "le_z": -0.9, "sweep": 0.1, "thick": 0.13},
		"tail": {"z": 5.4, "span": 3.4, "cr": 1.6, "ct": 0.9, "y": 0.4},
		"fin": {"twin": true, "x": 1.7, "z": 5.3, "y": 0.4, "h": 2.0, "cr": 1.6, "ct": 0.9},
		"engines": [
			{"x": -2.5, "y": -0.45, "z0": -3.2, "z1": 1.6, "r": 0.6, "prop_r": 1.6, "blades": 3},
			{"x": 2.5, "y": -0.45, "z0": -3.2, "z1": 1.6, "r": 0.6, "prop_r": 1.6, "blades": 3}],
		"canopies": [[[-2.8, 0.15, 0.15, 0.55], [-1.8, 0.5, 0.45, 0.75], [-0.4, 0.55, 0.5, 0.85], [1.2, 0.5, 0.4, 0.8], [2.4, 0.15, 0.15, 0.6]]],
		"extras": [{"t": "box", "pos": Vector3(0.0, -0.1, -4.9), "size": Vector3(0.7, 0.35, 1.4), "col": "dark"}],
		"gear": {"x": 2.5, "y": -0.8, "z": -0.6, "len": 0.9, "r": 0.4},
		"tail_wheel": [-0.3, 5.6],
		"guns": [0.5, -0.1, -5.0], "eye": Vector3(0, 1.0, -2.0),
		"mark_z": 4.2, "mark_t": 0.6, "mark_size": 0.6, "wing_mark_size": 0.8,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func do17() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe", "outline": 0.02,
		"colors": {"top": Color(0.24, 0.29, 0.21), "under": LW_UNDER, "patch": LW_PATCH},
		"fus": {"z0": -7.2, "z1": 8.6, "hw": 0.75, "hh": 1.0, "cy": 0.15, "profile": "bomber"},
		"wing": {"root_x": 0.7, "half": 9.0, "y": 0.45, "dihedral": 0.1, "cr": 3.1, "ct": 1.6, "le_z": -1.6, "sweep": 0.1, "thick": 0.12},
		"tail": {"z": 7.2, "span": 4.4, "cr": 2.0, "ct": 1.0, "y": 0.6},
		"fin": {"twin": true, "x": 2.0, "z": 7.0, "y": 0.5, "h": 2.2, "cr": 2.0, "ct": 1.0},
		"engines": [
			{"x": -3.3, "y": 0.35, "z0": -3.6, "z1": 1.2, "r": 0.62, "prop_r": 1.7, "blades": 3},
			{"x": 3.3, "y": 0.35, "z0": -3.6, "z1": 1.2, "r": 0.62, "prop_r": 1.7, "blades": 3}],
		"canopies": [[[-7.2, 0.15, 0.15, 0.4], [-6.4, 0.6, 0.6, 0.7], [-5.2, 0.8, 0.7, 1.0], [-3.8, 0.7, 0.5, 1.15], [-2.4, 0.4, 0.3, 1.1]]],
		"extras": [{"t": "sphere", "pos": Vector3(0, 1.1, 0.4), "size": Vector3(0.45, 0, 0), "col": "grey"}],
		"gear": {"x": 3.3, "y": -0.2, "z": -0.8, "len": 1.0, "r": 0.5},
		"tail_wheel": [-0.4, 8.0],
		"guns": [0.0, 0.0, -6.6], "eye": Vector3(0, 1.0, -5.2),
		"mark_z": 5.6, "mark_t": 0.8, "mark_size": 0.8, "wing_mark_size": 1.1,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func ju52() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe", "outline": 0.02,
		"colors": {"top": Color(0.3, 0.35, 0.3), "under": LW_UNDER, "patch": LW_PATCH},
		"fus": {"z0": -9.0, "z1": 9.9, "hw": 1.3, "hh": 1.4, "cy": 0.2, "profile": "bomber"},
		"wing": {"root_x": 1.2, "half": 14.75, "y": -0.7, "dihedral": 0.15, "cr": 4.6, "ct": 2.8, "le_z": -2.2, "sweep": 0.0, "thick": 0.14, "round_tip": false},
		"tail": {"z": 8.6, "span": 5.8, "cr": 3.0, "ct": 1.8, "y": 0.6},
		"fin": {"z": 8.2, "y": 0.6, "h": 3.4, "cr": 3.2, "ct": 1.6},
		"nose_prop": {"z": -9.1, "r": 1.95, "blades": 3, "spinner": 0.4},
		"engines": [
			{"x": -4.6, "y": -0.5, "z0": -4.4, "z1": 1.0, "r": 0.7, "prop_r": 1.9, "blades": 3},
			{"x": 4.6, "y": -0.5, "z0": -4.4, "z1": 1.0, "r": 0.7, "prop_r": 1.9, "blades": 3}],
		"canopies": [[[-7.4, 0.2, 0.2, 0.9], [-6.6, 0.6, 0.55, 1.2], [-5.8, 0.55, 0.45, 1.3], [-5.0, 0.2, 0.15, 1.25]]],
		"extras": [{"t": "box", "pos": Vector3(0, -1.5, 0.5), "size": Vector3(0.5, 0.3, 4.4), "col": "dark"}],
		"gear": {"x": 3.0, "y": -1.1, "z": -1.0, "len": 1.3, "r": 0.85},
		"tail_wheel": [-0.9, 9.4],
		"guns": [0.0, 1.2, -1.0], "eye": Vector3(0, 1.3, -6.0),
		"mark_z": 6.8, "mark_t": 0.9, "mark_size": 1.0, "wing_mark_size": 1.3,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func fw200() -> Dictionary:
	return {
		"scale": 1.1, "nation": "Luftwaffe", "outline": 0.02,
		"colors": {"top": Color(0.2, 0.27, 0.24), "under": Color(0.45, 0.58, 0.7), "patch": LW_PATCH},
		"fus": {"z0": -11.0, "z1": 12.5, "hw": 1.25, "hh": 1.45, "cy": 0.2, "profile": "bomber"},
		"wing": {"root_x": 1.1, "half": 16.5, "y": -0.7, "dihedral": 0.3, "cr": 4.6, "ct": 2.2, "le_z": -2.4, "sweep": 0.2, "thick": 0.14},
		"tail": {"z": 11.2, "span": 6.4, "cr": 3.0, "ct": 1.6, "y": 0.6},
		"fin": {"z": 10.8, "y": 0.6, "h": 4.0, "cr": 3.6, "ct": 1.8},
		"engines": [
			{"x": -4.8, "y": -0.5, "z0": -4.8, "z1": 1.2, "r": 0.7, "prop_r": 1.9, "blades": 3},
			{"x": 4.8, "y": -0.5, "z0": -4.8, "z1": 1.2, "r": 0.7, "prop_r": 1.9, "blades": 3},
			{"x": -9.6, "y": -0.3, "z0": -4.4, "z1": 1.0, "r": 0.7, "prop_r": 1.9, "blades": 3},
			{"x": 9.6, "y": -0.3, "z0": -4.4, "z1": 1.0, "r": 0.7, "prop_r": 1.9, "blades": 3}],
		"canopies": [[[-9.6, 0.2, 0.2, 0.7], [-8.6, 0.7, 0.6, 1.1], [-7.4, 0.8, 0.7, 1.3], [-6.2, 0.5, 0.4, 1.3]]],
		"extras": [
			{"t": "box", "pos": Vector3(0, -1.5, -2.0), "size": Vector3(0.9, 0.5, 4.0), "col": "dark"},
			{"t": "sphere", "pos": Vector3(0, 1.5, -3.0), "size": Vector3(0.55, 0, 0), "col": "grey"}],
		"gear": {"x": 5.0, "y": -1.1, "z": -0.6, "len": 1.3, "r": 0.7},
		"tail_wheel": [-0.9, 11.8],
		"guns": [0.0, 0.0, -10.4], "eye": Vector3(0, 1.3, -8.0),
		"mark_z": 8.6, "mark_t": 0.9, "mark_size": 1.0, "wing_mark_size": 1.3,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func blenheim() -> Dictionary:
	return {
		"scale": 1.1, "nation": "RAF", "outline": 0.02,
		"colors": {"top": RAF_TOP, "under": RAF_UNDER, "patch": RAF_PATCH},
		"fus": {"z0": -5.4, "z1": 7.4, "hw": 0.8, "hh": 1.0, "cy": 0.1, "profile": "bomber"},
		"wing": {"root_x": 0.8, "half": 8.6, "y": -0.1, "dihedral": 0.15, "cr": 3.4, "ct": 1.7, "le_z": -1.4, "sweep": 0.15, "thick": 0.13},
		"tail": {"z": 6.2, "span": 4.0, "cr": 1.9, "ct": 1.0, "y": 0.5},
		"fin": {"z": 6.0, "y": 0.5, "h": 2.4, "cr": 2.2, "ct": 1.1},
		"engines": [
			{"x": -2.8, "y": -0.2, "z0": -3.4, "z1": 1.6, "r": 0.62, "prop_r": 1.7, "blades": 3},
			{"x": 2.8, "y": -0.2, "z0": -3.4, "z1": 1.6, "r": 0.62, "prop_r": 1.7, "blades": 3}],
		"canopies": [[[-5.4, 0.15, 0.15, 0.4], [-4.6, 0.55, 0.5, 0.7], [-3.4, 0.7, 0.6, 1.0], [-1.8, 0.55, 0.4, 1.1], [-0.6, 0.3, 0.2, 1.1]]],
		"extras": [{"t": "sphere", "pos": Vector3(0.9, 1.2, 0.8), "size": Vector3(0.4, 0, 0), "col": "grey"}],
		"gear": {"x": 2.8, "y": -0.7, "z": -0.6, "len": 1.0, "r": 0.5},
		"tail_wheel": [-0.5, 6.8],
		"guns": [-0.6, -0.1, -4.2], "eye": Vector3(0, 1.0, -3.4),
		"mark_z": 4.8, "mark_t": 0.8, "mark_size": 0.75, "wing_mark_size": 1.0,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func tempest() -> Dictionary:
	var d: Dictionary = typhoon()
	d["wing"] = {"root_x": 0.6, "half": 5.65, "y": -0.45, "dihedral": 0.25, "cr": 2.9, "ct": 1.0, "le_z": -1.4, "sweep": 0.2, "thick": 0.11, "round_tip": true}
	d["fus"] = {"z0": -4.15, "z1": 5.3, "hw": 0.6, "hh": 0.8, "cy": 0.05, "profile": "inline"}
	d["tail"] = {"z": 4.8, "span": 2.6, "cr": 1.6, "ct": 0.8, "y": 0.3}
	d["fin"] = {"z": 4.3, "y": 0.35, "h": 2.1, "cr": 2.4, "ct": 1.2, "fillet": 1.2}
	d["gear"] = {"x": 1.9, "y": -0.5, "z": -0.6, "len": 1.0, "r": 0.4}
	d["mark_z"] = 3.4
	d["nose_prop"] = {"z": -4.25, "r": 2.1, "blades": 4, "spinner": 0.34}
	d["tail_wheel"] = [-0.1, 5.1]
	d["extras"] = []
	return d


static func p38() -> Dictionary:
	return {
		"scale": 1.1, "nation": "USAAF", "stripes": true, "outline": 0.02,
		"colors": {"top": Color(0.52, 0.55, 0.56), "under": Color(0.66, 0.69, 0.7), "patch": Color(0.42, 0.45, 0.46)},
		"fus": {"z0": -2.6, "z1": 3.4, "hw": 0.55, "hh": 0.65, "cy": 0.2, "profile": "inline"},
		"wing": {"root_x": 0.5, "half": 7.9, "y": -0.2, "dihedral": 0.1, "cr": 3.0, "ct": 1.5, "le_z": -1.2, "sweep": 0.0, "thick": 0.14},
		"tail": {"z": 6.4, "span": 5.4, "cr": 1.6, "ct": 1.0, "y": 0.6},
		"fin": {"twin": true, "x": 2.9, "z": 6.0, "y": 0.5, "h": 2.0, "cr": 1.8, "ct": 1.0},
		"engines": [
			{"x": -2.9, "y": -0.2, "z0": -3.0, "z1": 6.8, "r": 0.55, "prop_r": 1.7, "blades": 3},
			{"x": 2.9, "y": -0.2, "z0": -3.0, "z1": 6.8, "r": 0.55, "prop_r": 1.7, "blades": 3}],
		"canopies": [[[-1.6, 0.1, 0.1, 0.7], [-1.0, 0.4, 0.35, 0.85], [0.2, 0.42, 0.38, 0.9], [1.4, 0.25, 0.2, 0.8], [2.2, 0.06, 0.08, 0.7]]],
		"extras": [],
		"gear": {"x": 2.9, "y": -0.6, "z": -0.6, "len": 1.0, "r": 0.4},
		"tail_wheel": [-0.1, 6.6],
		"guns": [0.0, -0.1, -2.6], "eye": Vector3(0, 1.0, -0.4),
		"mark_z": 1.8, "mark_t": 0.5, "mark_size": 0.55, "wing_mark_size": 0.8,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func defiant() -> Dictionary:
	var d: Dictionary = hurricane()
	d["extras"] = []
	d["turret"] = {"pos": Vector3(0, 0.92, 1.45), "r": 0.55}
	return d


static func b25() -> Dictionary:
	return {
		"scale": 1.1, "nation": "USAAF", "stripes": true, "outline": 0.02,
		"colors": {"top": OD_TOP, "under": OD_UNDER, "patch": OD_PATCH},
		"fus": {"z0": -7.2, "z1": 8.8, "hw": 0.9, "hh": 1.1, "cy": 0.1, "profile": "bomber"},
		"wing": {"root_x": 0.9, "half": 10.3, "y": 0.1, "dihedral": 0.2, "cr": 3.6, "ct": 1.8, "le_z": -1.6, "sweep": 0.2, "thick": 0.14},
		"tail": {"z": 7.6, "span": 5.0, "cr": 2.0, "ct": 1.0, "y": 0.7},
		"fin": {"twin": true, "x": 2.3, "z": 7.4, "y": 0.6, "h": 2.6, "cr": 2.2, "ct": 1.2},
		"engines": [
			{"x": -3.5, "y": -0.2, "z0": -3.8, "z1": 1.6, "r": 0.7, "prop_r": 1.8, "blades": 3},
			{"x": 3.5, "y": -0.2, "z0": -3.8, "z1": 1.6, "r": 0.7, "prop_r": 1.8, "blades": 3}],
		"canopies": [[[-6.8, 0.15, 0.15, 0.6], [-6.0, 0.6, 0.5, 0.9], [-4.4, 0.8, 0.6, 1.2], [-3.0, 0.5, 0.35, 1.25]]],
		"extras": [{"t": "sphere", "pos": Vector3(0, 1.4, 1.8), "size": Vector3(0.45, 0, 0), "col": "grey"}],
		"gear": {"x": 3.5, "y": -0.7, "z": -0.6, "len": 1.2, "r": 0.55},
		"tail_wheel": [-0.6, 8.4],
		"guns": [0.0, 0.0, -6.6], "eye": Vector3(0, 1.0, -5.2),
		"mark_z": 6.2, "mark_t": 0.8, "mark_size": 0.8, "wing_mark_size": 1.1,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func a20() -> Dictionary:
	return {
		"scale": 1.1, "nation": "USAAF", "stripes": true, "outline": 0.02,
		"colors": {"top": OD_TOP, "under": OD_UNDER, "patch": OD_PATCH},
		"fus": {"z0": -6.0, "z1": 7.8, "hw": 0.75, "hh": 0.95, "cy": 0.1, "profile": "bomber"},
		"wing": {"root_x": 0.8, "half": 9.35, "y": 0.4, "dihedral": 0.1, "cr": 3.3, "ct": 1.6, "le_z": -1.3, "sweep": 0.1, "thick": 0.13},
		"tail": {"z": 6.8, "span": 4.0, "cr": 1.9, "ct": 1.0, "y": 0.6},
		"fin": {"z": 6.6, "y": 0.6, "h": 2.6, "cr": 2.3, "ct": 1.2},
		"engines": [
			{"x": -3.0, "y": 0.1, "z0": -3.4, "z1": 1.6, "r": 0.65, "prop_r": 1.7, "blades": 3},
			{"x": 3.0, "y": 0.1, "z0": -3.4, "z1": 1.6, "r": 0.65, "prop_r": 1.7, "blades": 3}],
		"canopies": [[[-5.6, 0.15, 0.15, 0.4], [-4.8, 0.55, 0.5, 0.7], [-3.4, 0.7, 0.6, 1.0], [-1.8, 0.5, 0.35, 1.05]]],
		"extras": [],
		"gear": {"x": 3.0, "y": -0.5, "z": -0.4, "len": 1.0, "r": 0.5},
		"tail_wheel": [-0.4, 7.2],
		"guns": [0.5, -0.1, -5.0], "eye": Vector3(0, 1.0, -4.0),
		"mark_z": 5.4, "mark_t": 0.8, "mark_size": 0.7, "wing_mark_size": 1.0,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


static func c47() -> Dictionary:
	return {
		"scale": 1.1, "nation": "USAAF", "stripes": true, "outline": 0.02,
		"colors": {"top": OD_TOP, "under": Color(0.6, 0.62, 0.6), "patch": OD_PATCH},
		"fus": {"z0": -7.6, "z1": 12.1, "hw": 1.25, "hh": 1.4, "cy": 0.2, "profile": "bomber"},
		"wing": {"root_x": 1.1, "half": 14.5, "y": -0.7, "dihedral": 0.25, "cr": 4.4, "ct": 2.0, "le_z": -1.9, "sweep": 0.15, "thick": 0.14},
		"tail": {"z": 10.6, "span": 6.6, "cr": 2.8, "ct": 1.4, "y": 0.7},
		"fin": {"z": 10.3, "y": 0.7, "h": 3.6, "cr": 3.4, "ct": 1.6},
		"engines": [
			{"x": -4.8, "y": -0.5, "z0": -4.0, "z1": 1.2, "r": 0.72, "prop_r": 1.85, "blades": 3},
			{"x": 4.8, "y": -0.5, "z0": -4.0, "z1": 1.2, "r": 0.72, "prop_r": 1.85, "blades": 3}],
		"canopies": [[[-6.6, 0.2, 0.2, 0.9], [-5.8, 0.6, 0.55, 1.2], [-4.8, 0.55, 0.45, 1.3], [-4.0, 0.2, 0.15, 1.25]]],
		"extras": [],
		"gear": {"x": 4.8, "y": -1.1, "z": -0.6, "len": 1.2, "r": 0.7},
		"tail_wheel": [-0.9, 11.2],
		"guns": [0.0, 0.0, -6.8], "eye": Vector3(0, 1.3, -5.6),
		"mark_z": 8.4, "mark_t": 0.9, "mark_size": 0.9, "wing_mark_size": 1.2,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}


## de Havilland DH.89 Dragon Rapide: the civil twin-engine biplane airliner (see tools/models/data/dh89.md for the
## published figures). Scale 1.0, so it is a true 1:1 airframe: length 10.52 m, upper span 14.63 m, 8 passengers.
static func dh89() -> Dictionary:
	var silver := Color(0.74, 0.76, 0.78)
	var extras: Array = []
	# cabane struts from the cabin roof to the upper wing, then the two pairs of interplane struts per side
	for sx in [-1.0, 1.0]:
		extras.append({"t": "box", "size": Vector3(0.06, 0.62, 0.11), "pos": Vector3(sx * 0.46, 0.62, -0.95), "col": "dark"})
		extras.append({"t": "box", "size": Vector3(0.06, 0.62, 0.11), "pos": Vector3(sx * 0.46, 0.62, 0.20), "col": "dark"})
		for sp in [[2.05, -0.785], [2.05, -0.095], [4.55, -0.585], [4.55, 0.105]]:
			extras.append({"t": "box", "size": Vector3(0.065, 1.50, 0.13), "pos": Vector3(sx * float(sp[0]), 0.26, float(sp[1])), "col": "dark"})
		# five square cabin windows each side, and the wheel spat under each engine
		for i in 5:
			extras.append({"t": "box", "size": Vector3(0.04, 0.34, 0.40), "pos": Vector3(sx * 0.635, 0.12, -1.55 + float(i) * 0.62), "col": "dark"})
		extras.append({"t": "spat", "col": "top", "x": sx * 2.19, "y": -1.30, "z0": -0.95, "z1": 0.95, "r": 0.26})
		extras.append({"t": "box", "size": Vector3(0.035, 0.07, 2.6), "pos": Vector3(sx * 0.64, -0.28, -0.45), "col": Color(0.10, 0.16, 0.40)})
	return {
		"scale": 1.0, "nation": "Civil", "outline": 0.012,
		"colors": {"top": silver, "under": Color(0.70, 0.72, 0.75), "patch": Color(0.69, 0.71, 0.74)},
		"fus": {"z0": -3.85, "z1": 6.67, "hw": 0.63, "hh": 0.77, "cy": 0.0, "profile": "bomber"},
		"wing": {"root_x": 0.5, "half": 6.8, "y": 1.02, "dihedral": 0.0, "cr": 1.55, "ct": 0.95, "le_z": -1.10, "sweep": 0.15, "thick": 0.115},
		"wing2": {"root_x": 0.5, "half": 5.9, "y": -0.50, "dihedral": 0.28, "cr": 1.38, "ct": 0.76, "le_z": -0.80, "sweep": 0.12, "thick": 0.12},
		"tail": {"z": 5.39, "span": 2.2, "cr": 1.20, "ct": 0.55, "y": 0.36},
		"fin": {"z": 5.40, "y": 0.36, "h": 1.17, "cr": 1.18, "ct": 0.40, "twin": true, "x": 1.55},
		"engines": [
			{"x": -2.05, "y": -0.46, "z0": -1.85, "z1": 0.75, "r": 0.32, "prop_r": 1.10, "blades": 2},
			{"x": 2.05, "y": -0.46, "z0": -1.85, "z1": 0.75, "r": 0.32, "prop_r": 1.10, "blades": 2}],
		"canopies": [[[-3.50, 0.30, 0.10, 0.22], [-3.25, 0.44, 0.17, 0.36], [-2.95, 0.54, 0.22, 0.46], [-2.60, 0.58, 0.22, 0.50], [-2.25, 0.58, 0.18, 0.48]]],
		"extras": extras,
		"gear": {"x": 2.05, "y": -0.62, "z": -0.70, "len": 0.75, "r": 0.42, "leg_w": 0.10},
		"tail_wheel": [-0.62, 5.50],
		"guns": [0.30, -0.10, -3.45], "eye": Vector3(0, 0.42, -2.45),
		"mark_z": 3.2, "mark_t": 0.8, "mark_size": 0.30, "wing_mark_size": 0.4,
		"prop_tip": Color(0.1, 0.1, 0.1),
	}
