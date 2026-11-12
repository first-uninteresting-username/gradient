class_name TitleScreen
extends Screen

var _best: Label
var _play: Button


func _ready() -> void:
	var box := UiKit.centered_panel(self, 460)
	var title := UiKit.label("GRADIENT", 64, UiKit.CYAN)
	title.add_theme_font_override(&"font", load("res://assets/fonts/SpaceMono-Bold.ttf"))
	box.add_child(title)
	box.add_child(UiKit.label("endless downhill", 18, UiKit.VIOLET))
	_best = UiKit.label("", 18, UiKit.DIM)
	box.add_child(_best)
	_play = UiKit.button("Play", func() -> void: Game.play_endless())
	box.add_child(_play)
	box.add_child(UiKit.button("Seed…", func() -> void: navigate.emit("seed")))
	box.add_child(UiKit.button("Practice", func() -> void: navigate.emit("practice")))
	box.add_child(UiKit.button("Custom track", func() -> void: navigate.emit("custom")))
	box.add_child(UiKit.button("Settings", func() -> void: navigate.emit("settings")))
	if not UiKit.is_web():
		box.add_child(UiKit.button("Quit", func() -> void: Game.quit_game()))
	box.add_child(UiKit.label("A/D or ←/→ to steer · Esc to pause", 14, UiKit.DIM))


func opened() -> void:
	_best.text = "best %d" % Save.get_best("endless")
	focus_first(_play)
