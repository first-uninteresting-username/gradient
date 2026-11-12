class_name SettingsMenu
extends Screen
## Audio, palette, camera comfort, HUD readouts and key bindings.

var _first: Control
var _bind_buttons: Dictionary = {}
var _capturing: String = ""
var _back_target: String = "title"


func _ready() -> void:
	var box := UiKit.centered_panel(self, 600)
	box.add_child(UiKit.label("SETTINGS", 36, UiKit.CYAN))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(_section("Audio"))
	_first = _slider(list, "Master", "master_volume")
	_slider(list, "Music", "music_volume")
	_slider(list, "Effects", "sfx_volume")

	list.add_child(_section("Look"))
	var pal := OptionButton.new()
	pal.add_item("Default (cyan / orange)")
	pal.add_item("Colour-blind (yellow / striped white)")
	pal.selected = 1 if Save.get_setting("palette") == "colorblind" else 0
	pal.item_selected.connect(func(i: int) -> void: Save.set_setting("palette", "colorblind" if i == 1 else "default"))
	list.add_child(_row("Palette", pal))
	_check(list, "High contrast", "high_contrast")
	_check(list, "Reduced glow", "reduced_glow")

	list.add_child(_section("Camera comfort"))
	_check(list, "Reduce roll and FOV kick", "reduced_motion")

	list.add_child(_section("HUD"))
	_check(list, "Show speed", "show_speed")
	_check(list, "Show FPS", "show_fps")

	list.add_child(_section("Keys"))
	for action: String in Controls.REBINDABLE:
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 40)
		b.pressed.connect(_begin_capture.bind(action))
		_bind_buttons[action] = b
		list.add_child(_row(Controls.LABELS[action], b))
	var reset := UiKit.button("Reset keys", _reset_keys)
	list.add_child(reset)
	_refresh_binds()

	box.add_child(UiKit.button("Back", _back))


func open_from(target: String) -> void:
	_back_target = target


func opened() -> void:
	_capturing = ""
	_refresh_binds()
	focus_first(_first)


func _back() -> void:
	_capturing = ""
	navigate.emit(_back_target)


func _section(text: String) -> Label:
	var l := UiKit.label(text.to_upper(), 16, UiKit.VIOLET, HORIZONTAL_ALIGNMENT_LEFT)
	return l


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UiKit.label(text, 18, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _slider(list: VBoxContainer, text: String, key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Save.get_setting(key))
	s.custom_minimum_size = Vector2(240, 32)
	s.value_changed.connect(func(v: float) -> void: Save.set_setting(key, v))
	list.add_child(_row(text, s))
	return s


func _check(list: VBoxContainer, text: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = bool(Save.get_setting(key))
	c.toggled.connect(func(on: bool) -> void: Save.set_setting(key, on))
	list.add_child(_row(text, c))
	return c


func _binds() -> Dictionary:
	var b = Save.get_setting("keybinds")
	return (b as Dictionary).duplicate() if b is Dictionary else {}


func _refresh_binds() -> void:
	var binds := _binds()
	for action: String in _bind_buttons:
		var b: Button = _bind_buttons[action]
		b.text = "press a key…" if _capturing == action else Controls.key_name(Controls.primary_key(action, binds))


func _begin_capture(action: String) -> void:
	_capturing = action
	_refresh_binds()


func _reset_keys() -> void:
	Save.set_setting("keybinds", {})
	Controls.apply({})
	_refresh_binds()


func _input(event: InputEvent) -> void:
	if _capturing.is_empty() or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_NONE:
			key = (event as InputEventKey).keycode
		var binds := _binds()
		binds[_capturing] = int(key)
		Save.set_setting("keybinds", binds)
		Controls.apply(binds)
		_capturing = ""
		_refresh_binds()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _capturing.is_empty() and event.is_action_pressed(&"ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
