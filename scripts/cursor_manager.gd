extends Node
## Hide the OS pointer while the player is using a gamepad, and bring it back the moment the mouse moves
## or is clicked. Runs always so it works in the menu, pause screen and in flight.

const STICK_DEADZONE := 0.45       # ignore resting-stick noise
const MOUSE_GRACE_MS := 350        # a held stick must not immediately re-hide after a mouse nudge
const MOUSE_MOVE_SQ := 0.25        # ~0.5 px: ignore zero/quantised mouse events

var _mouse_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_hide_for_pad()
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > STICK_DEADZONE:
			if Time.get_ticks_msec() - _mouse_ms > MOUSE_GRACE_MS:
				_hide_for_pad()
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > MOUSE_MOVE_SQ:
			_mouse_ms = Time.get_ticks_msec()
			_show_for_mouse()
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_mouse_ms = Time.get_ticks_msec()
			_show_for_mouse()


func _hide_for_pad() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _show_for_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
