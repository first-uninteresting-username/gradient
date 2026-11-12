class_name SeedEntry
extends Screen

var _edit: LineEdit
var _preview: Label


func _ready() -> void:
	var box := UiKit.centered_panel(self, 520)
	box.add_child(UiKit.label("SEED", 36, UiKit.CYAN))
	box.add_child(UiKit.label("Type a number or any text", 16, UiKit.DIM))
	_edit = LineEdit.new()
	_edit.placeholder_text = "e.g. 1234 or sunset run"
	_edit.custom_minimum_size = Vector2(440, 48)
	_edit.text_submitted.connect(func(_t: String) -> void: _play())
	_edit.text_changed.connect(func(_t: String) -> void: _update_preview())
	box.add_child(_edit)
	_preview = UiKit.label("", 14, UiKit.DIM)
	box.add_child(_preview)
	box.add_child(UiKit.button("Play", _play))
	box.add_child(UiKit.button("Back", func() -> void: navigate.emit("title")))


func opened() -> void:
	_update_preview()
	focus_first(_edit)


func _update_preview() -> void:
	var t := _edit.text.strip_edges()
	_preview.text = "" if t.is_empty() else "seed #%d" % Game.parse_seed(t)


func _play() -> void:
	if _edit.text.strip_edges().is_empty():
		_edit.grab_focus()
		return
	Game.play_seeded(_edit.text)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		navigate.emit("title")
		get_viewport().set_input_as_handled()
