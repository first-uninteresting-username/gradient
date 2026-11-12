class_name Hud
extends Screen
## In-run HUD: score (large, top centre), personal best, optional speed and FPS,
## a pause button, and touch steering (hold the left or right half of the screen).

var _score: Label
var _best: Label
var _speed: Label
var _fps: Label
var _seed: Label
var _touches: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.position.y = 18
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.add_theme_constant_override(&"separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_score = UiKit.label("0", 72, Color.WHITE)
	_score.add_theme_font_override(&"font", load("res://assets/fonts/SpaceMono-Bold.ttf"))
	_score.add_theme_color_override(&"font_outline_color", Color(UiKit.CYAN, 0.5))
	_score.add_theme_constant_override(&"outline_size", 6)
	top.add_child(_score)
	_best = UiKit.label("", 16, UiKit.DIM)
	top.add_child(_best)

	_speed = UiKit.label("", 22, UiKit.CYAN, HORIZONTAL_ALIGNMENT_LEFT)
	_speed.anchor_top = 1.0
	_speed.anchor_bottom = 1.0
	_speed.offset_left = 24.0
	_speed.offset_right = 324.0
	_speed.offset_top = -56.0
	_speed.offset_bottom = -20.0
	add_child(_speed)
	_fps = UiKit.label("", 16, UiKit.DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_fps.position = Vector2(20, 16)
	add_child(_fps)
	_seed = UiKit.label("", 14, Color(UiKit.DIM, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	_seed.anchor_left = 1.0
	_seed.anchor_right = 1.0
	_seed.anchor_top = 1.0
	_seed.anchor_bottom = 1.0
	_seed.offset_left = -420.0
	_seed.offset_right = -20.0
	_seed.offset_top = -40.0
	_seed.offset_bottom = -16.0
	add_child(_seed)

	var pause := Button.new()
	pause.text = "II"
	pause.focus_mode = Control.FOCUS_NONE
	pause.custom_minimum_size = Vector2(56, 56)
	pause.anchor_left = 1.0
	pause.anchor_right = 1.0
	pause.offset_left = -76.0
	pause.offset_right = -20.0
	pause.offset_top = 16.0
	pause.offset_bottom = 72.0
	pause.pressed.connect(func() -> void: Game.pause())
	add_child(pause)

	Game.score_changed.connect(_on_score)


func opened() -> void:
	_touches.clear()
	Game.touch_steer = 0.0
	_on_score(Game.score)
	_seed.text = "seed " + Game.seed_label()


func _on_score(s: int) -> void:
	_score.text = str(s)
	if Game.mode == Game.Mode.PRACTICE:
		_best.text = "practice"
	else:
		_best.text = "best %d" % maxi(Game.best(), s)


func _process(_delta: float) -> void:
	if not visible:
		return
	_speed.visible = bool(Save.get_setting("show_speed"))
	if _speed.visible and Game.world != null:
		_speed.text = "%d m/s" % roundi(Game.world.speed())
	_fps.visible = bool(Save.get_setting("show_fps"))
	if _fps.visible:
		_fps.text = "%d fps" % Engine.get_frames_per_second()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position.x
		else:
			_touches.erase(t.index)
		_update_touch()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position.x
		_update_touch()


func _update_touch() -> void:
	var half := get_viewport_rect().size.x * 0.5
	var left := false
	var right := false
	for x: float in _touches.values():
		if x < half:
			left = true
		else:
			right = true
	Game.touch_steer = (1.0 if right else 0.0) - (1.0 if left else 0.0)
