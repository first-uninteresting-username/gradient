extends Node
## Persistent personal bests and settings in user://save.cfg.

signal setting_changed(key: String, value: Variant)

const PATH := "user://save.cfg"
const MODES := ["endless", "seeded", "custom", "practice"]
const DEFAULTS := {
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"palette": "default",
	"high_contrast": false,
	"reduced_motion": false,
	"reduced_glow": false,
	"show_speed": false,
	"show_fps": false,
	"keybinds": {},
}

## Tests turn this off so they never touch the player's save file.
var persist := true
var _cfg := ConfigFile.new()


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--no-save"):
		persist = false
	if persist:
		_cfg.load(PATH)


func get_setting(key: String) -> Variant:
	return _cfg.get_value("settings", key, DEFAULTS.get(key))


func set_setting(key: String, value: Variant) -> void:
	_cfg.set_value("settings", key, value)
	_flush()
	setting_changed.emit(key, value)


func get_best(mode: String) -> int:
	return int(_cfg.get_value("best", mode, 0))


## Records a score; returns true if it is a new personal best for that mode.
func submit_score(mode: String, score: int) -> bool:
	if score > get_best(mode):
		_cfg.set_value("best", mode, score)
		_flush()
		return true
	return false


func reset_for_tests() -> void:
	persist = false
	_cfg = ConfigFile.new()


func _flush() -> void:
	if persist:
		_cfg.save(PATH)
