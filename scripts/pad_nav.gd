extends Node
## Shared gamepad (and keyboard) menu navigation. Autoload `PadNav`.
##
## Every menu / overlay registers itself with `PadNav.screen(self, {...})` (and `PadNav.unscreen(self)` when it hides,
## if it is a persistent node such as the pause menu). The helper then provides, for all of them alike:
##  * a screen stack: only the top screen can take focus (screens below get `focus_behavior_recursive = DISABLED`),
##    and when it closes the screen beneath gets its focus back on the button that opened the sub-menu;
##  * an initial focus when a screen opens (the `first` Control / Callable, else the first enabled focusable one);
##  * B = ui_cancel only while a screen is open (in flight B stays "weapon toggle"), plus a `back` fallback;
##  * stick / D-pad key repeat (Godot has none for sticks), LB / RB for tabs (TabContainer or a `tabs` callable);
##  * a virtual pointer for map controls (`pointer(control)`): right stick moves, A clicks, LT / RT zoom;
##  * a consistent focus highlight in the game's theme (default theme), ScrollContainer.follow_focus, and
##  * button hints (A Select / B Back ...) while the pad was the last device used.
## Mouse and keyboard are untouched: the same controls and signals are used.

signal device_changed(using_pad: bool)

const STICK_ON := 0.55
const REPEAT_DELAY := 0.42
const REPEAT_RATE := 0.11
const CURSOR_SPEED := 620.0
const DIRS := ["ui_up", "ui_down", "ui_left", "ui_right"]

var using_pad: bool = false
var _stack: Array = []             # registered screens, bottom -> top (Node)
var _opts: Dictionary = {}         # instance id -> options Dictionary
var _saved_focus: Dictionary = {}  # instance id -> NodePath of the focused control when the screen was covered
var _b_added: bool = false
var _b_event: InputEventJoypadButton
var _held: String = ""
var _held_t: float = 0.0
var _rep_t: float = 0.0
var _hints_layer: CanvasLayer
var _hints_box: HBoxContainer
var _pointers: Array = []          # map controls with a virtual pointer
var _cursor: Vector2 = Vector2.ZERO
var _cursor_for: Control
var _cursor_layer: CanvasLayer
var _cursor_node: Control
var _a_down: bool = false
var _x_down: bool = false
var _stick_state: Dictionary = {}     # left-stick axis -> -1 / 0 / +1 (past the threshold)
var _dpad_held: Dictionary = {}       # D-pad button -> held


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_b_event = InputEventJoypadButton.new()
	_b_event.button_index = JOY_BUTTON_B
	_setup_theme()
	get_tree().node_added.connect(_on_node_added)
	_hints_layer = CanvasLayer.new()
	_hints_layer.layer = 100
	_hints_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hints_layer)
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints_layer.add_child(anchor)
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.025, 0.78)
	sb.border_color = Color(UIKit.PANEL_EDGE, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.offset_right = -18.0
	pc.offset_bottom = -14.0
	anchor.add_child(pc)
	_hints_box = HBoxContainer.new()
	_hints_box.add_theme_constant_override("separation", 6)
	pc.add_child(_hints_box)
	pc.visible = false
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.layer = 101
	_cursor_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_cursor_layer)
	_cursor_node = Control.new()
	_cursor_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cursor_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_node.draw.connect(_draw_cursor)
	_cursor_layer.add_child(_cursor_node)
	_cursor_node.visible = false


# ------------------------------------------------------------------ registration

## Register a menu / overlay. opts: back (Callable, called on B / Start when the screen itself does not handle it),
## tabs (Callable(dir: int) for LB / RB), first (Control or Callable returning one), hints (Array of [glyph, text]).
func screen(node: Node, opts: Dictionary = {}) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _stack.has(node):
		_stack.erase(node)
	var prev: Node = top()
	if prev != null and prev != node:
		_cover(prev, node)
	_stack.append(node)
	_opts[node.get_instance_id()] = opts
	if not node.tree_exiting.is_connected(_on_exiting):
		node.tree_exiting.connect(_on_exiting.bind(node))
	_enable_roots(node)
	_sync_actions()
	_refresh_hints()
	_focus_new.call_deferred(node)


func unscreen(node: Node) -> void:
	if not _stack.has(node):
		return
	var was_top: bool = top() == node
	_stack.erase(node)
	_opts.erase(node.get_instance_id())
	_saved_focus.erase(node.get_instance_id())
	if is_instance_valid(node) and node.is_inside_tree():
		_enable_roots(node)
	_sync_actions()
	_refresh_hints()
	if was_top and top() != null:
		_uncover.call_deferred(top())


func top() -> Node:
	while not _stack.is_empty() and not is_instance_valid(_stack.back()):
		_stack.pop_back()
	return _stack.back() if not _stack.is_empty() else null


func is_active() -> bool:
	return top() != null


func _on_exiting(node: Node) -> void:
	unscreen(node)


func _roots(node: Node) -> Array:
	if node is Control:
		return [node]
	var out: Array = []
	for c in node.get_children():
		if c is Control:
			out.append(c)
	return out


func _cover(node: Node, newcomer: Node = null) -> void:
	var fo: Control = get_viewport().gui_get_focus_owner()
	# a focus that already moved into the new screen (it grabbed it before registering) is not the opener's
	if fo != null and newcomer != null and (newcomer == fo or newcomer.is_ancestor_of(fo)):
		fo = null
	if fo != null and (node == fo or node.is_ancestor_of(fo)):
		_saved_focus[node.get_instance_id()] = node.get_path_to(fo)
	for r in _roots(node):
		(r as Control).focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	if fo != null and (node == fo or node.is_ancestor_of(fo)):
		fo.release_focus()


func _enable_roots(node: Node) -> void:
	for r in _roots(node):
		(r as Control).focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED if top() == node else Control.FOCUS_BEHAVIOR_INHERITED


func _uncover(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	_enable_roots(node)
	var key: int = node.get_instance_id()
	if _saved_focus.has(key):
		var c: Node = node.get_node_or_null(_saved_focus[key])
		_saved_focus.erase(key)
		if c is Control and _can_focus(c as Control):
			(c as Control).grab_focus()
			return
	focus_first(node)


## Call after a screen rebuilt its contents (the old focused control is gone): focus `first` or the first control.
func refocus(node: Node, first: Control = null) -> void:
	if first != null:
		_opts[node.get_instance_id()] = (_opts.get(node.get_instance_id(), {}) as Dictionary).merged({"first": first}, true)
	_refocus_later(node)


func _refocus_later(node: Node) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_focus_new(node)


func _focus_new(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or top() != node:
		return
	var fo: Control = get_viewport().gui_get_focus_owner()
	if fo != null and fo.is_queued_for_deletion():
		fo = null
	var opts: Dictionary = _opts.get(node.get_instance_id(), {})
	var want: Control = null
	var first: Variant = opts.get("first", null)
	if first is Callable and (first as Callable).is_valid():
		want = (first as Callable).call()
	elif typeof(first) == TYPE_OBJECT and is_instance_valid(first) and first is Control:
		want = first
	if want != null and is_instance_valid(want) and _can_focus(want):
		want.grab_focus()
		return
	if fo != null and is_instance_valid(fo) and node.is_ancestor_of(fo) and _can_focus(fo):
		return        # the screen already took a sensible focus itself
	focus_first(node)


## Focus the first visible, enabled, focusable control (tree order) under `node`.
func focus_first(node: Node) -> void:
	var c: Control = first_focusable(node)
	if c != null:
		c.grab_focus()


func first_focusable(node: Node) -> Control:
	if node is Control:
		var ctl: Control = node
		if not ctl.visible:
			return null
		if _can_focus(ctl) and not _is_text(ctl):
			return ctl
	for ch in node.get_children():
		if ch is CanvasItem and not (ch as CanvasItem).visible:
			continue
		var r: Control = first_focusable(ch)
		if r != null:
			return r
	return null


func _is_text(c: Control) -> bool:
	return c is LineEdit or c is TextEdit


func _can_focus(c: Control) -> bool:
	if not c.is_inside_tree() or not c.is_visible_in_tree():
		return false
	if c.get_focus_mode_with_override() == Control.FOCUS_NONE:
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	return true


## Pointer-style map controls (Flight planner map, mission editor map).
func pointer(c: Control) -> void:
	if not _pointers.has(c):
		_pointers.append(c)


# ------------------------------------------------------------------ actions (B only while a menu is up)

func _sync_actions() -> void:
	var want: bool = top() != null
	if want == _b_added:
		return
	_b_added = want
	if not InputMap.has_action("ui_cancel"):
		return
	if want:
		InputMap.action_add_event("ui_cancel", _b_event)
	else:
		InputMap.action_erase_event("ui_cancel", _b_event)


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_set_pad(true)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > STICK_ON:
			_set_pad(true)
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_set_pad(false)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > 1.0 and not _a_down:
			_set_pad(false)
	elif event is InputEventKey:
		if (event as InputEventKey).pressed:
			_set_pad(false)
	if top() == null:
		_stick_state.clear()
		_dpad_held.clear()
		return
	if event is InputEventJoypadMotion:
		# A held (jittery) stick sends a stream of "pressed" events: only the crossing of the threshold moves the
		# focus; the repeat is generated in _process.
		var jm: InputEventJoypadMotion = event
		if jm.axis == JOY_AXIS_LEFT_X or jm.axis == JOY_AXIS_LEFT_Y:
			var s: int = 0 if absf(jm.axis_value) < STICK_ON else (1 if jm.axis_value > 0.0 else -1)
			if s != 0 and _stick_state.get(jm.axis, 0) == s:
				get_viewport().set_input_as_handled()
			_stick_state[jm.axis] = s
	var captured: bool = top().has_meta("pad_capture")
	if event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event
		if jb.button_index >= JOY_BUTTON_DPAD_UP and jb.button_index <= JOY_BUTTON_DPAD_RIGHT:
			_dpad_held[jb.button_index] = jb.pressed
		# a press that a menu consumes must not leak into flight actions when the menu closes
		if jb.pressed and jb.button_index == JOY_BUTTON_B:
			Input.action_release("weapon_toggle")
		if jb.pressed and jb.button_index == JOY_BUTTON_A:
			Input.action_release("fire")
		if captured:
			return
		# bumpers switch tabs / jump between map markers
		if jb.pressed and (jb.button_index == JOY_BUTTON_LEFT_SHOULDER or jb.button_index == JOY_BUTTON_RIGHT_SHOULDER):
			var dir: int = -1 if jb.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
			if _pointer_cycle(dir) or _step_tabs(dir):
				get_viewport().set_input_as_handled()
				return
		# virtual pointer: A / X act as left / right mouse buttons on a map control
		var pc: Control = _active_pointer()
		if pc != null and (jb.button_index == JOY_BUTTON_A or jb.button_index == JOY_BUTTON_X):
			_pointer_button(pc, MOUSE_BUTTON_LEFT if jb.button_index == JOY_BUTTON_A else MOUSE_BUTTON_RIGHT, jb.pressed)
			get_viewport().set_input_as_handled()
			return
	if captured or event is InputEventKey or event is InputEventMouse:
		return
	# text fields and spin boxes must not trap the pad: up / down / B step out of them, left / right on a
	# spin box change its value
	var fo: Control = get_viewport().gui_get_focus_owner()
	if fo != null and (fo is TextEdit or fo is LineEdit):
		var spin: SpinBox = fo.get_parent() as SpinBox
		if spin != null and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
			spin.value += spin.step * (-1.0 if event.is_action_pressed("ui_left") else 1.0)
			get_viewport().set_input_as_handled()
			return
		var side: int = -1
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_cancel"):
			side = SIDE_TOP
		elif event.is_action_pressed("ui_down"):
			side = SIDE_BOTTOM
		if side >= 0 and (event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction):
			var n: Control = fo.find_valid_focus_neighbor(side)
			if n == null and side == SIDE_TOP:
				n = fo.find_valid_focus_neighbor(SIDE_BOTTOM)
			if n != null:
				n.grab_focus()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if top() == null:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		var opts: Dictionary = _opts.get(top().get_instance_id(), {})
		var back: Variant = opts.get("back", null)
		if back is Callable and (back as Callable).is_valid():
			(back as Callable).call()
			get_viewport().set_input_as_handled()


func _set_pad(on: bool) -> void:
	if on == using_pad:
		return
	using_pad = on
	_refresh_hints()
	device_changed.emit(on)


func _step_tabs(dir: int) -> bool:
	var fo: Control = get_viewport().gui_get_focus_owner()
	var n: Node = fo
	while n != null:
		if n is TabContainer:
			var tc: TabContainer = n
			var cnt: int = tc.get_tab_count()
			if cnt > 1:
				tc.current_tab = posmod(tc.current_tab + dir, cnt)
				return true
		n = n.get_parent()
	var t: Node = top()
	if t == null:
		return false
	var opts: Dictionary = _opts.get(t.get_instance_id(), {})
	var tabs: Variant = opts.get("tabs", null)
	if tabs is Callable and (tabs as Callable).is_valid():
		(tabs as Callable).call(dir)
		return true
	for tc2 in t.find_children("*", "TabContainer", true, false):
		if (tc2 as TabContainer).is_visible_in_tree() and (tc2 as TabContainer).get_tab_count() > 1:
			var tcc: TabContainer = tc2
			tcc.current_tab = posmod(tcc.current_tab + dir, tcc.get_tab_count())
			return true
	return false


# ------------------------------------------------------------------ key repeat, pointer

func _process(delta: float) -> void:
	_pointer_process(delta)
	_scroll_process(delta)
	if top() == null or get_viewport().gui_get_focus_owner() == null or top().has_meta("pad_capture"):
		_held = ""
		return
	# Godot repeats the keyboard but not a held stick or D-pad: do it here for menus.
	var cur: String = ""
	for a in DIRS:
		if Input.is_action_pressed(a):
			cur = a
			break
	if cur == "" or not _pad_dir_held():
		_held = ""
		return
	if cur != _held:
		_held = cur
		_held_t = 0.0
		_rep_t = 0.0
		return
	_held_t += delta
	if _held_t < REPEAT_DELAY:
		return
	_rep_t += delta
	if _rep_t >= REPEAT_RATE:
		_rep_t = 0.0
		var ev := InputEventAction.new()
		ev.action = _held
		ev.pressed = true
		ev.strength = 1.0
		get_viewport().push_input(ev)      # GUI only: the Input action state (held stick) is left alone


## Right stick (up / down) scrolls long text and panels: the scroll area around the focused control, else the
## first one on the top screen that has something to scroll (credits, licence text, logbook).
func _scroll_process(delta: float) -> void:
	if top() == null or _active_pointer() != null:
		return
	var st: Vector2 = _right_stick()
	if absf(st.y) < 0.3:
		return
	var bar: ScrollBar = _scroll_target()
	if bar != null:
		bar.value += st.y * absf(st.y) * 900.0 * delta


func _scroll_target() -> ScrollBar:
	var n: Node = get_viewport().gui_get_focus_owner()
	while n != null:
		var b: ScrollBar = _bar_of(n)
		if b != null:
			return b
		n = n.get_parent()
	return _find_scrollable(top())


func _find_scrollable(n: Node) -> ScrollBar:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return null
	var b: ScrollBar = _bar_of(n)
	if b != null:
		return b
	for c in n.get_children():
		var r: ScrollBar = _find_scrollable(c)
		if r != null:
			return r
	return null


func _bar_of(n: Node) -> ScrollBar:
	var bar: ScrollBar = null
	if n is ScrollContainer and (n as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		bar = (n as ScrollContainer).get_v_scroll_bar()
	elif n is RichTextLabel and (n as RichTextLabel).scroll_active:
		bar = (n as RichTextLabel).get_v_scroll_bar()
	elif n is TextEdit:
		bar = (n as TextEdit).get_v_scroll_bar()
	if bar != null and bar.visible and bar.max_value - bar.page > 1.0:
		return bar
	return null


## True while the held direction comes from a pad (keyboard has its own repeat).
func _pad_dir_held() -> bool:
	for k in _dpad_held.keys():
		if _dpad_held[k]:
			return true
	for ax in _stick_state.keys():
		if int(_stick_state[ax]) != 0:
			return true
	return false


func _active_pointer() -> Control:
	var fo: Control = get_viewport().gui_get_focus_owner()
	if fo != null and _pointers.has(fo) and is_instance_valid(fo) and fo.is_visible_in_tree() and using_pad:
		return fo
	return null


func _right_stick() -> Vector2:
	var v := Vector2.ZERO
	for dev in Input.get_connected_joypads():
		var s := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if s.length() > 0.25 and s.length() > v.length():
			v = s
	return v


func _triggers() -> float:
	var z: float = 0.0
	for dev in Input.get_connected_joypads():
		z += maxf(Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT), 0.0) - maxf(Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT), 0.0)
	return z


func _pointer_process(delta: float) -> void:
	var pc: Control = _active_pointer()
	if pc == null:
		if _cursor_node.visible:
			_cursor_node.visible = false
		_cursor_for = null
		return
	if _cursor_for != pc:
		_cursor_for = pc
		_cursor = pc.size * 0.5
	var st: Vector2 = _right_stick()
	if st != Vector2.ZERO:
		var rel: Vector2 = st * st.length() * CURSOR_SPEED * delta
		_cursor = (_cursor + rel).clamp(Vector2(4, 4), pc.size - Vector2(4, 4))
		var mm := InputEventMouseMotion.new()
		mm.position = _cursor
		mm.global_position = pc.get_global_transform_with_canvas() * _cursor
		mm.relative = rel
		mm.button_mask = (MOUSE_BUTTON_MASK_LEFT if _a_down else 0) | (MOUSE_BUTTON_MASK_RIGHT if _x_down else 0)
		pc._gui_input(mm)
	var z: float = _triggers()
	if absf(z) > 0.35 and pc.has_method("pad_zoom"):
		pc.call("pad_zoom", z * delta * 2.2, _cursor)
	_cursor_node.visible = true
	_cursor_node.queue_redraw()


func _pointer_button(pc: Control, button: int, pressed: bool) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_a_down = pressed
	else:
		_x_down = pressed
	var mb := InputEventMouseButton.new()
	mb.button_index = button
	mb.pressed = pressed
	mb.position = _cursor
	mb.global_position = pc.get_global_transform_with_canvas() * _cursor
	mb.button_mask = (MOUSE_BUTTON_MASK_LEFT if _a_down else 0) | (MOUSE_BUTTON_MASK_RIGHT if _x_down else 0)
	pc._gui_input(mb)
	_cursor_node.queue_redraw()


func _pointer_cycle(dir: int) -> bool:
	var pc: Control = _active_pointer()
	if pc == null or not pc.has_method("pad_cycle"):
		return false
	var p: Variant = pc.call("pad_cycle", dir, _cursor)
	if p is Vector2:
		_cursor = p
	return true


func _draw_cursor() -> void:
	if _cursor_for == null or not is_instance_valid(_cursor_for):
		return
	var p: Vector2 = _cursor_for.get_global_transform_with_canvas() * _cursor
	var col: Color = UIKit.ACCENT_HOT
	_cursor_node.draw_arc(p, 11.0, 0.0, TAU, 28, Color(0, 0, 0, 0.85), 5.0, true)
	_cursor_node.draw_arc(p, 11.0, 0.0, TAU, 28, col, 2.5, true)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_cursor_node.draw_line(p + d * 15.0, p + d * 23.0, Color(0, 0, 0, 0.85), 5.0)
		_cursor_node.draw_line(p + d * 15.0, p + d * 23.0, col, 2.5)


# ------------------------------------------------------------------ hints

func _refresh_hints() -> void:
	if _hints_box == null:
		return
	var pc: Control = _hints_box.get_parent()
	var t: Node = top()
	pc.visible = using_pad and t != null
	if not pc.visible:
		return
	for c in _hints_box.get_children():
		_hints_box.remove_child(c)
		c.queue_free()
	var opts: Dictionary = _opts.get(t.get_instance_id(), {})
	_place_hints(String(opts.get("hints_at", "bottom_right")))
	var items: Array = [["A", String(opts.get("a_label", "Select"))], ["B", String(opts.get("b_label", "Back"))]]
	if opts.get("tabs", null) is Callable:
		items.append(["LB", "Page"])
		items.append(["RB", ""])
	for h in opts.get("hints", []):
		items.append(h)
	for it in items:
		_hints_box.add_child(PadGlyph.make(String(it[0]), 24.0))
		if String(it[1]) != "":
			var l: Label = UIKit.label(String(it[1]), 16, UIKit.TEXT, true)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_hints_box.add_child(l)
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(8, 0)
			_hints_box.add_child(gap)


## Screens choose the corner / edge that is free on their layout: bottom_right (default), top_left, top_center.
func _place_hints(at: String) -> void:
	var pc: Control = _hints_box.get_parent()
	match at:
		"top_center":
			pc.anchor_left = 0.5
			pc.anchor_right = 0.5
			pc.anchor_top = 0.0
			pc.anchor_bottom = 0.0
			pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
			pc.grow_vertical = Control.GROW_DIRECTION_END
			pc.offset_left = 0.0
			pc.offset_right = 0.0
			pc.offset_top = 10.0
			pc.offset_bottom = 10.0
		"top_left":
			pc.anchor_left = 0.0
			pc.anchor_right = 0.0
			pc.anchor_top = 0.0
			pc.anchor_bottom = 0.0
			pc.grow_horizontal = Control.GROW_DIRECTION_END
			pc.grow_vertical = Control.GROW_DIRECTION_END
			pc.offset_left = 18.0
			pc.offset_right = 18.0
			pc.offset_top = 10.0
			pc.offset_bottom = 10.0
		_:
			pc.anchor_left = 1.0
			pc.anchor_right = 1.0
			pc.anchor_top = 1.0
			pc.anchor_bottom = 1.0
			pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
			pc.offset_left = 0.0
			pc.offset_right = -18.0
			pc.offset_top = 0.0
			pc.offset_bottom = -14.0


# ------------------------------------------------------------------ look and per-node setup

func _on_node_added(n: Node) -> void:
	if n is ScrollContainer:
		(n as ScrollContainer).follow_focus = true


## One obvious focus highlight (brass border + warm fill) for every control type, set on the default theme so
## code-built controls that do not override it get it too. UIKit's buttons / dropdowns keep their own, matching one.
func _setup_theme() -> void:
	var th: Theme = ThemeDB.get_default_theme()
	if th == null:
		return
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.14)
	fb.border_color = UIKit.ACCENT_HOT
	fb.set_border_width_all(3)
	fb.set_corner_radius_all(4)
	fb.set_expand_margin_all(2.0)
	fb.draw_center = true
	var ring := fb.duplicate() as StyleBoxFlat     # outline only, for big containers
	ring.draw_center = false
	for t in ["Button", "CheckBox", "CheckButton", "OptionButton", "MenuButton", "LinkButton", "ColorPickerButton", "HSlider", "VSlider", "SpinBox", "TabBar"]:
		th.set_stylebox("focus", t, fb)
	th.set_stylebox("tab_focus", "TabBar", fb)
	th.set_stylebox("tab_focus", "TabContainer", fb)
	for t2 in ["LineEdit", "TextEdit", "ItemList", "Tree", "ScrollContainer", "HScrollBar", "VScrollBar"]:
		th.set_stylebox("focus", t2, ring)
