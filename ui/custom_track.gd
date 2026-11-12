class_name CustomTrackMenu
extends Screen
## Load a *.gradient.json track from disk (desktop) or paste its JSON (any platform).

const EXAMPLE := "res://data/custom_tracks/example.gradient.json"

var _text: TextEdit
var _status: Label
var _dialog: FileDialog


func _ready() -> void:
	var box := UiKit.centered_panel(self, 640)
	box.add_child(UiKit.label("CUSTOM TRACK", 36, UiKit.CYAN))
	box.add_child(UiKit.label("Paste a .gradient.json track", 16, UiKit.DIM))
	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(580, 220)
	_text.add_theme_font_size_override(&"font_size", 15)
	box.add_child(_text)
	_status = UiKit.label("", 15, UiKit.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(580, 0)
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	if not UiKit.is_web():
		var load_btn := UiKit.button("Load file…", _open_dialog)
		load_btn.custom_minimum_size = Vector2(200, 46)
		row.add_child(load_btn)
	var example := UiKit.button("Example", _load_example)
	example.custom_minimum_size = Vector2(200, 46)
	row.add_child(example)
	box.add_child(UiKit.button("Start", _start))
	box.add_child(UiKit.button("Back", func() -> void: navigate.emit("title")))
	if not UiKit.is_web():
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.filters = PackedStringArray(["*.gradient.json ; GRADIENT tracks", "*.json ; JSON"])
		_dialog.use_native_dialog = true
		_dialog.file_selected.connect(_on_file)
		add_child(_dialog)


func opened() -> void:
	if _text.text.strip_edges().is_empty():
		_load_example()
	_status.text = ""
	focus_first(_text)


func _open_dialog() -> void:
	_dialog.popup_centered_ratio(0.7)


func _on_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_status.text = "Could not open %s" % path
		return
	_text.text = f.get_as_text()
	_status.text = "Loaded %s" % path.get_file()


func _load_example() -> void:
	var f := FileAccess.open(EXAMPLE, FileAccess.READ)
	if f != null:
		_text.text = f.get_as_text()


func _start() -> void:
	var track := Game.parse_custom_track(_text.text)
	if not track["ok"]:
		_status.text = track["error"]
		_status.add_theme_color_override(&"font_color", UiKit.ORANGE)
		return
	_status.remove_theme_color_override(&"font_color")
	Game.play_custom(track)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		navigate.emit("title")
		get_viewport().set_input_as_handled()
