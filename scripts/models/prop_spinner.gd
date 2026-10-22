class_name PropSpinner
extends Node3D
## Spins secondary propellers (the aircraft script only drives the node named "Propeller").
## Fast secondary props strobe exactly like the primary one does, so they get the same blades -> PropDisc
## blur swap (see AircraftModels.prop_blur).

@export var rate: float = 55.0

var _blades: Node3D
var _discs: Array[Node3D] = []


func _ready() -> void:
	_blades = find_child("Blades", true, false) as Node3D
	for d in find_children("PropDisc*", "MeshInstance3D", true, false):
		_discs.append(d as Node3D)


func _process(delta: float) -> void:
	rotate_object_local(Vector3.BACK, rate * delta)
	var blur: bool = AircraftModels.prop_blur(rate, delta)
	if _blades:
		_blades.visible = not blur
	for d in _discs:
		d.visible = blur
