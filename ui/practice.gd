class_name PracticeMenu
extends Screen
## Pick one chunk (or a tag) and a speed; the drill loops forever.

var _picker: OptionButton
var _slider: HSlider
var _speed_label: Label
var _targets: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var box := UiKit.centered_panel(self, 520)
	box.add_child(UiKit.label("PRACTICE", 36, UiKit.CYAN))
	_picker = OptionButton.new()
	_picker.custom_minimum_size = Vector2(440, 46)
	var cat := ChunkCatalogue.get_default()
	for info in cat.infos:
		if info.adapter:
			continue
		_picker.add_item(info.display_name if not info.display_name.is_empty() else String(info.id))
		_targets.append("chunk:" + String(info.id))
	for tag in cat.all_tags():
		_picker.add_item("Tag: " + tag)
		_targets.append("tag:" + tag)
	box.add_child(_picker)
	_speed_label = UiKit.label("", 18)
	box.add_child(_speed_label)
	_slider = HSlider.new()
	_slider.min_value = 14
	_slider.max_value = 80
	_slider.step = 1
	_slider.value = 30
	_slider.custom_minimum_size = Vector2(440, 32)
	_slider.value_changed.connect(func(_v: float) -> void: _update_label())
	box.add_child(_slider)
	box.add_child(UiKit.button("Start", _start))
	box.add_child(UiKit.button("Back", func() -> void: navigate.emit("title")))
	_update_label()


func opened() -> void:
	focus_first(_picker)


func _update_label() -> void:
	_speed_label.text = "speed %d m/s" % int(_slider.value)


func _start() -> void:
	Game.play_practice(_targets[maxi(_picker.selected, 0)], _slider.value)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		navigate.emit("title")
		get_viewport().set_input_as_handled()
