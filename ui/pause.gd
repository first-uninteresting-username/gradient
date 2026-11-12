class_name PauseMenu
extends Screen

var _resume: Button


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var box := UiKit.centered_panel(self, 420)
	box.add_child(UiKit.label("PAUSED", 40, UiKit.CYAN))
	_resume = UiKit.button("Resume", func() -> void: Game.resume())
	box.add_child(_resume)
	box.add_child(UiKit.button("Restart", func() -> void: Game.restart()))
	box.add_child(UiKit.button("Settings", func() -> void: navigate.emit("settings_from_pause")))
	box.add_child(UiKit.button("Menu", func() -> void: Game.to_menu()))


func opened() -> void:
	focus_first(_resume)
