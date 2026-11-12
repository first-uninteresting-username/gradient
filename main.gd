extends Node
## Root scene: owns the World and the UI layer and switches pages with Game.state.
## Command-line (after "--"):
##   --autoplay          a centre-seeking bot plays endless runs
##   --bench=SECONDS     print frame-time statistics after SECONDS and quit
##   --screenshot=PATH   save a screenshot shortly before quitting (with --bench)
##   --seed=TEXT         start a seeded run immediately
##   --practice=TARGET   start practice on chunk:<id> or tag:<tag> (at --speed=M/S, default 30)

@onready var world: World = $World

var ui: Control
var pages: Dictionary = {}
var current_page: String = ""
var autoplay := false
var _bench_seconds: float = 0.0
var _bench_elapsed: float = 0.0
var _bench_frames: int = 0
var _bench_worst: float = 0.0
var _screenshot_path: String = ""
var _demo_timer: float = 0.0


func _ready() -> void:
	# Keeps the attract demo and benchmark timing running independent of pausing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.register_world(world)
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UiKit.theme()
	layer.add_child(ui)
	pages = {
		"title": TitleScreen.new(),
		"seed": SeedEntry.new(),
		"practice": PracticeMenu.new(),
		"custom": CustomTrackMenu.new(),
		"settings": SettingsMenu.new(),
		"hud": Hud.new(),
		"pause": PauseMenu.new(),
		"death": DeathScreen.new(),
	}
	for key: String in pages:
		var page: Screen = pages[key]
		page.name = key.capitalize().replace(" ", "")
		page.visible = false
		ui.add_child(page)
		page.navigate.connect(_navigate)
	Game.state_changed.connect(_on_state)
	Game.run_started.connect(func(_s: int, _m: Game.Mode) -> void: world.ball.autopilot = Autopilot.dodger if autoplay else Callable())
	_parse_args()
	_on_state(Game.state)


func _parse_args() -> void:
	var start_seed := ""
	var practice := ""
	var practice_speed := 30.0
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
			Game.pause_on_focus_loss = false
		elif arg.begins_with("--bench="):
			_bench_seconds = float(arg.get_slice("=", 1))
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="):
			start_seed = arg.get_slice("=", 1)
		elif arg.begins_with("--practice="):
			practice = arg.get_slice("=", 1)
		elif arg.begins_with("--speed="):
			practice_speed = float(arg.get_slice("=", 1))
	if not practice.is_empty():
		Game.play_practice.call_deferred(practice, practice_speed)
	elif not start_seed.is_empty():
		Game.play_seeded.call_deferred(start_seed)
	elif autoplay:
		Game.play_endless.call_deferred()


func _navigate(to: String) -> void:
	if to == "settings_from_pause":
		(pages["settings"] as SettingsMenu).open_from("pause")
		_show("settings")
		return
	if to == "settings":
		(pages["settings"] as SettingsMenu).open_from("title")
	if to == "pause":
		_show("pause")
		return
	_show(to)


func _show(page: String) -> void:
	for key: String in pages:
		(pages[key] as Control).visible = key == page
	current_page = page
	(pages[page] as Screen).opened()


func _on_state(state: Game.State) -> void:
	match state:
		Game.State.MENU:
			_show("title")
			_start_demo()
		Game.State.RUNNING:
			_show("hud")
		Game.State.PAUSED:
			_show("pause")
		Game.State.DEAD:
			if autoplay:
				Game.play_again.call_deferred()
			_show("death")


## Attract mode behind the menus: the dodging bot plays a real endless run.
func _start_demo() -> void:
	world.start_run(TrackPlan.endless(randi_range(0, Game.MAX_SEED)))
	world.ball.autopilot = Autopilot.dodger


func _process(delta: float) -> void:
	if Game.state == Game.State.MENU and not world.running:
		_demo_timer += delta
		if _demo_timer > 1.0:
			_demo_timer = 0.0
			_start_demo()
	if _bench_seconds > 0.0:
		_bench_elapsed += delta
		if _bench_elapsed > 2.0:  # skip warm-up
			_bench_frames += 1
			_bench_worst = maxf(_bench_worst, delta)
			if delta > 0.02:
				print("BENCH slow frame %.1f ms at %.2f s (state %d, run %d, chunks streamed %d)" % [
					delta * 1000.0, _bench_elapsed, Game.state, Game.runs_started,
					world.generator.current_index])
		if _bench_elapsed >= _bench_seconds + 2.0:
			_finish_bench()


func _finish_bench() -> void:
	var avg := _bench_frames / maxf(_bench_elapsed - 2.0, 0.001)
	print("BENCH frames=%d avg_fps=%.1f worst_frame_ms=%.2f renderer=%s adapter=%s" % [
		_bench_frames, avg, _bench_worst * 1000.0,
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	if not _screenshot_path.is_empty():
		var img := get_viewport().get_texture().get_image()
		img.save_png(_screenshot_path)
		print("BENCH screenshot ", _screenshot_path)
	_bench_seconds = 0.0
	Game.quit_game()
