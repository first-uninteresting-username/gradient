class_name UiKit
extends RefCounted
## Theme and small widget helpers shared by every screen.

const CYAN := Color("#2CF6FF")
const VIOLET := Color("#8A5CFF")
const ORANGE := Color("#FF5A1F")
const BG := Color("#05070F")
const TEXT := Color("#E6FBFF")
const DIM := Color("#7F9AB0")

static var _theme: Theme


static func release_theme() -> void:
	_theme = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var regular := load("res://assets/fonts/SpaceMono-Regular.ttf") as FontFile
	var bold := load("res://assets/fonts/SpaceMono-Bold.ttf") as FontFile
	t.default_font = regular
	t.default_font_size = 20
	t.set_font(&"font", &"Button", bold)
	t.set_color(&"font_color", &"Label", TEXT)
	for cls: StringName in [&"Button", &"OptionButton", &"CheckBox", &"CheckButton"]:
		t.set_color(&"font_color", cls, TEXT)
		t.set_color(&"font_hover_color", cls, CYAN)
		t.set_color(&"font_focus_color", cls, CYAN)
		t.set_color(&"font_pressed_color", cls, BG)
	t.set_stylebox(&"normal", &"Button", _box(Color(BG, 0.6), Color(CYAN, 0.55), 2))
	t.set_stylebox(&"hover", &"Button", _box(Color(CYAN, 0.12), CYAN, 2))
	t.set_stylebox(&"pressed", &"Button", _box(CYAN, CYAN, 2))
	t.set_stylebox(&"focus", &"Button", _box(Color(0, 0, 0, 0), Color.WHITE, 2))
	t.set_stylebox(&"disabled", &"Button", _box(Color(BG, 0.4), Color(DIM, 0.4), 2))
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		t.set_stylebox(state, &"OptionButton", t.get_stylebox(state, &"Button"))
	t.set_stylebox(&"normal", &"LineEdit", _box(Color(BG, 0.8), Color(CYAN, 0.55), 2))
	t.set_stylebox(&"focus", &"LineEdit", _box(Color(0, 0, 0, 0), Color.WHITE, 2))
	t.set_stylebox(&"normal", &"TextEdit", _box(Color(BG, 0.85), Color(CYAN, 0.55), 2))
	t.set_stylebox(&"focus", &"TextEdit", _box(Color(0, 0, 0, 0), Color.WHITE, 2))
	t.set_stylebox(&"panel", &"PanelContainer", _box(Color(BG, 0.82), Color(VIOLET, 0.6), 2, 24))
	t.set_color(&"font_color", &"LineEdit", TEXT)
	t.set_color(&"caret_color", &"LineEdit", CYAN)
	t.set_color(&"font_color", &"TextEdit", TEXT)
	t.set_constant(&"separation", &"VBoxContainer", 12)
	t.set_constant(&"separation", &"HBoxContainer", 12)
	_theme = t
	return t


static func _box(fill: Color, border: Color, width: int, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(2)
	s.content_margin_left = margin + 6
	s.content_margin_right = margin + 6
	s.content_margin_top = margin * 0.5
	s.content_margin_bottom = margin * 0.5
	return s


static func label(text: String, size: int = 20, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 46)
	b.pressed.connect(on_press)
	return b


## A centred, padded panel holding a vertical stack. Returns the VBoxContainer.
static func centered_panel(parent: Control, min_width: float = 420.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	return box


static func is_web() -> bool:
	return OS.has_feature("web")
