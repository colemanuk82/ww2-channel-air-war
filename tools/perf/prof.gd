class_name Prof
## Debug: a tiny inclusive-time accumulator (enabled only by --site-sweep). Not shipped instrumented.
static var on: bool = false
static var acc: Dictionary = {}


static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(tag: String, t0: int) -> void:
	if not on:
		return
	var a: Array = acc.get(tag, [0, 0])
	a[0] += Time.get_ticks_usec() - t0
	a[1] += 1
	acc[tag] = a


static func dump(min_ms: float) -> String:
	var out: PackedStringArray = []
	for k in acc.keys():
		var a: Array = acc[k]
		if float(a[0]) / 1000.0 >= min_ms:
			out.append("%s=%.1fms/%d" % [k, float(a[0]) / 1000.0, a[1]])
	acc.clear()
	return " ".join(out)
