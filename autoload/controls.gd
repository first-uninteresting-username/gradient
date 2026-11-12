class_name Controls
extends RefCounted
## Input actions are defined in code so defaults and saved rebinds live in one place.

const REBINDABLE := ["steer_left", "steer_right", "pause", "restart", "same_seed"]
const LABELS := {
	"steer_left": "Steer left",
	"steer_right": "Steer right",
	"pause": "Pause",
	"restart": "Play again",
	"same_seed": "Same seed",
}
const DEFAULT_KEYS := {
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"pause": [KEY_ESCAPE, KEY_P],
	"restart": [KEY_R, KEY_SPACE],
	"same_seed": [KEY_S],
}
const DEFAULT_PADS := {
	"steer_left": [JOY_BUTTON_DPAD_LEFT],
	"steer_right": [JOY_BUTTON_DPAD_RIGHT],
	"pause": [JOY_BUTTON_START],
	"restart": [JOY_BUTTON_A],
	"same_seed": [JOY_BUTTON_Y],
}


## (Re)builds every action. `binds` maps action -> physical keycode replacing the
## first default key.
static func apply(binds: Dictionary) -> void:
	for action: String in DEFAULT_KEYS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.5)
		var keys: Array = DEFAULT_KEYS[action].duplicate()
		if binds.has(action) and int(binds[action]) != 0:
			keys[0] = int(binds[action])
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for b in DEFAULT_PADS[action]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)


static func primary_key(action: String, binds: Dictionary) -> int:
	if binds.has(action) and int(binds[action]) != 0:
		return int(binds[action])
	return int(DEFAULT_KEYS[action][0])


static func key_name(keycode: int) -> String:
	return OS.get_keycode_string(keycode)
