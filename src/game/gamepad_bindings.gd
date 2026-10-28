class_name GamepadBindings
extends RefCounted

# Gamepad actions (issue #68, D-048). Added in code rather than in project.godot: redefining ui_accept and ui_cancel
# there means rewriting their keys too, and a missing key would break the keyboard. The map polls the stick, the
# triggers and the demolish hold; the rest are presses.
const BUTTONS: Dictionary[StringName, JoyButton] = {
	&"map_cursor_up": JOY_BUTTON_DPAD_UP,
	&"map_cursor_down": JOY_BUTTON_DPAD_DOWN,
	&"map_cursor_left": JOY_BUTTON_DPAD_LEFT,
	&"map_cursor_right": JOY_BUTTON_DPAD_RIGHT,
	&"map_place": JOY_BUTTON_A,
	&"map_demolish": JOY_BUTTON_X,
	# Repairs the damaged wharf under the cursor (issue #178).
	&"map_repair": JOY_BUTTON_Y,
	&"map_build_prev": JOY_BUTTON_LEFT_SHOULDER,
	&"map_build_next": JOY_BUTTON_RIGHT_SHOULDER,
	&"gamepad_panel": JOY_BUTTON_START,
	&"gamepad_pause": JOY_BUTTON_BACK,
	# The need layers and the "why?" of the selection (issue #73), on the two stick clicks no other action takes.
	&"map_overlay_next": JOY_BUTTON_LEFT_STICK,
	&"map_why": JOY_BUTTON_RIGHT_STICK,
	# Godot 4.7 has no gamepad button on these two; the panel needs them to press and to go back.
	&"ui_accept": JOY_BUTTON_A,
	&"ui_cancel": JOY_BUTTON_B,
}
const AXES: Dictionary[StringName, Array] = {
	&"map_pan_left": [JOY_AXIS_LEFT_X, -1.0],
	&"map_pan_right": [JOY_AXIS_LEFT_X, 1.0],
	&"map_pan_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"map_pan_down": [JOY_AXIS_LEFT_Y, 1.0],
	&"map_zoom_out": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	&"map_zoom_in": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	# Only the 3D city turns (issue #65); the 2D map ignores them.
	&"map_rotate_left": [JOY_AXIS_RIGHT_X, -1.0],
	&"map_rotate_right": [JOY_AXIS_RIGHT_X, 1.0],
}
const CURSOR: Dictionary[StringName, Vector2i] = {
	&"map_cursor_up": Vector2i.UP,
	&"map_cursor_down": Vector2i.DOWN,
	&"map_cursor_left": Vector2i.LEFT,
	&"map_cursor_right": Vector2i.RIGHT,
}


# Safe to call more than once: an event already bound is not added again.
static func install() -> void:
	for action: StringName in BUTTONS:
		var button: InputEventJoypadButton = InputEventJoypadButton.new()
		button.button_index = BUTTONS[action]
		_bind(action, button)
	for action: StringName in AXES:
		var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
		motion.axis = AXES[action][0]
		motion.axis_value = AXES[action][1]
		_bind(action, motion)


static func _bind(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


# A resting stick still sends small motions; only a real push (the engine's half-way mark) counts as using the pad.
static func is_gamepad(event: InputEvent) -> bool:
	return (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.is_pressed()
