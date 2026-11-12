class_name DeathScreen
extends Screen
## Score, best, seed with a copy button, Play again (Space), Same seed (S), Menu.

var _title: Label
var _score: Label
var _best: Label
var _seed: Label
var _copy: Button
var _again: Button
var _panel: Control


func _ready() -> void:
	var box := UiKit.centered_panel(self, 480)
	_panel = box.get_parent() as Control
	_title = UiKit.label("", 30, UiKit.ORANGE)
	box.add_child(_title)
	_score = UiKit.label("0", 84, Color.WHITE)
	_score.add_theme_font_override(&"font", load("res://assets/fonts/SpaceMono-Bold.ttf"))
	box.add_child(_score)
	_best = UiKit.label("", 20, UiKit.DIM)
	box.add_child(_best)
	var seed_row := HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_seed = UiKit.label("", 18, UiKit.CYAN)
	seed_row.add_child(_seed)
	_copy = Button.new()
	_copy.text = "copy"
	_copy.pressed.connect(_copy_seed)
	seed_row.add_child(_copy)
	box.add_child(seed_row)
	_again = UiKit.button("Play again  [Space]", func() -> void: Game.play_again())
	box.add_child(_again)
	box.add_child(UiKit.button("Same seed  [S]", func() -> void: Game.replay_same_seed()))
	box.add_child(UiKit.button("Menu  [Esc]", func() -> void: Game.to_menu()))


func opened() -> void:
	_title.text = "TRACK COMPLETE" if Game.finished else ("CRASHED" if Game.death_cause == "hazard" else "FELL OFF")
	_title.add_theme_color_override(&"font_color", UiKit.CYAN if Game.finished else UiKit.ORANGE)
	_score.text = str(Game.score)
	var best := Game.best()
	_best.text = ("NEW BEST · %s" if Game.new_best else "best %s") % best
	if Game.mode == Game.Mode.SEEDED:
		_best.text += "  (seeded)"
	elif Game.mode == Game.Mode.CUSTOM:
		_best.text += "  (custom)"
	_seed.text = "seed " + Game.seed_label()
	_copy.text = "copy"
	focus_first(_again)


func _copy_seed() -> void:
	DisplayServer.clipboard_set(Game.seed_copy_text())
	_copy.text = "copied"


func _input(event: InputEvent) -> void:
	# Touch: tap anywhere outside the panel to play again.
	if not visible or not (event is InputEventScreenTouch):
		return
	var t := event as InputEventScreenTouch
	if t.pressed and not _panel.get_global_rect().has_point(t.position):
		get_viewport().set_input_as_handled()
		Game.play_again()
