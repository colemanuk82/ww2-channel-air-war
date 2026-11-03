class_name AircraftList
extends RefCounted
## Prune a typed aircraft list safely. A lambda typed `func(a: Aircraft)` cannot even receive an aircraft that has
## been freed (the call fails with "Cannot convert argument 1 from Object to Object" and the filter is abandoned),
## so dead entries stayed in the list - and a release build crashes when it later calls a method on one.


## The entries still valid (and, with alive_only, still flying), as a new typed list.
static func alive_or_valid(list: Array[Aircraft], alive_only: bool) -> Array[Aircraft]:
	var out: Array[Aircraft] = []
	for i in list.size():
		var v: Variant = list[i]          # untyped: reading a freed entry this way is safe, is_instance_valid decides
		if not is_instance_valid(v):
			continue
		var a: Aircraft = v as Aircraft
		if a == null or (alive_only and a.state != Aircraft.State.ALIVE):
			continue
		out.append(a)
	return out
