extends Node
## Run state machine (MENU, RUNNING, PAUSED, DEAD), current mode and seed.

enum State { MENU, RUNNING, PAUSED, DEAD }
enum Mode { ENDLESS, SEEDED, PRACTICE, CUSTOM }

signal state_changed(state: State)
signal run_started(seed: int, mode: Mode)
signal run_ended(score: int)
signal score_changed(score: int)

const MODE_KEYS := {Mode.ENDLESS: "endless", Mode.SEEDED: "seeded", Mode.PRACTICE: "practice", Mode.CUSTOM: "custom"}
const MAX_SEED := 999_999_999

var state: State = State.MENU
var mode: Mode = Mode.ENDLESS
var run_seed: int = 0
## What the player typed for a seeded run ("" for numeric/random seeds).
var seed_text: String = ""
var score: int = 0
var new_best := false
var finished := false
var dying := false
var death_cause: String = ""
## -1..1 from touch input (HUD), read by the ball.
var touch_steer: float = 0.0
var practice_target: String = ""
var practice_speed: float = 30.0
var custom_track: Dictionary = {}
var world: World
var runs_started: int = 0
## Off for unattended runs (--autoplay / benchmarks).
var pause_on_focus_loss := true

var _seed_rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	_seed_rng.seed = hash(str(Time.get_unix_time_from_system()) + ":" + str(Time.get_ticks_usec()))
	Controls.apply(Save.get_setting("keybinds"))


func _exit_tree() -> void:
	# Cached meshes/shapes live in Engine metadata; release them while the servers
	# still exist, whatever path the program quits through.
	ChunkCatalogue.release_default()
	TrackGeometry.clear_caches()
	UiKit.release_theme()


func register_world(w: World) -> void:
	world = w
	w.ball_died.connect(_on_ball_died)
	w.death_finished.connect(_on_death_finished)
	w.gate_passed.connect(_on_gate_passed)
	w.finish_reached.connect(_on_finish)


func mode_key(m: Mode = mode) -> String:
	return MODE_KEYS[m]


func best(m: Mode = mode) -> int:
	return Save.get_best(mode_key(m))


# --- Starting runs -----------------------------------------------------------------

func play_endless() -> void:
	run_seed = _seed_rng.randi_range(0, MAX_SEED)
	seed_text = ""
	_start(Mode.ENDLESS)


func play_seeded(text: String) -> void:
	seed_text = text.strip_edges()
	run_seed = parse_seed(seed_text)
	_start(Mode.SEEDED)


## `target` is "chunk:<id>" or "tag:<tag>".
func play_practice(target: String, speed: float) -> void:
	practice_target = target
	practice_speed = speed
	run_seed = _seed_rng.randi_range(0, MAX_SEED)
	seed_text = ""
	_start(Mode.PRACTICE)


func play_custom(track: Dictionary) -> void:
	custom_track = track
	run_seed = int(track.get("seed", 0))
	seed_text = str(track.get("seed_text", ""))
	_start(Mode.CUSTOM)


## Death screen "Play again": a fresh seed in endless, the same track otherwise.
func play_again() -> void:
	match mode:
		Mode.ENDLESS:
			play_endless()
		_:
			_start(mode)


## Death screen "Same seed": replays this seed (counts as a seeded run).
func replay_same_seed() -> void:
	if mode == Mode.ENDLESS:
		seed_text = str(run_seed)
		_start(Mode.SEEDED)
	else:
		_start(mode)


func build_plan(m: Mode) -> TrackPlan:
	var cat := ChunkCatalogue.get_default()
	match m:
		Mode.PRACTICE:
			return TrackPlan.practice(run_seed, practice_pool(practice_target), practice_speed, cat)
		Mode.CUSTOM:
			var ids: Array[StringName] = []
			for id in custom_track.get("chunks", []):
				ids.append(StringName(id))
			return TrackPlan.custom(run_seed, ids, bool(custom_track.get("loop", false)),
				float(custom_track.get("start_speed", 0.0)), cat)
		_:
			return TrackPlan.endless(run_seed, cat)


func practice_pool(target: String) -> Array[StringName]:
	var cat := ChunkCatalogue.get_default()
	var pool: Array[StringName] = []
	if target.begins_with("tag:"):
		for info in cat.with_tag(StringName(target.substr(4))):
			pool.append(info.id)
	elif cat.has(StringName(target.trim_prefix("chunk:"))):
		pool.append(StringName(target.trim_prefix("chunk:")))
	if pool.is_empty():
		pool.append(TrackPlan.START_CHUNK)
	return pool


func _start(m: Mode) -> void:
	mode = m
	score = 0
	new_best = false
	finished = false
	dying = false
	death_cause = ""
	touch_steer = 0.0
	get_tree().paused = false
	runs_started += 1
	if world != null:
		world.start_run(build_plan(m))
	_set_state(State.RUNNING)
	score_changed.emit(score)
	run_started.emit(run_seed, mode)


# --- Run events --------------------------------------------------------------------

func _on_gate_passed() -> void:
	if state != State.RUNNING or dying:
		return
	score += 1
	score_changed.emit(score)
	Audio.play_chime()


func _on_ball_died(cause: String) -> void:
	if state != State.RUNNING:
		return  # Attract-mode demo behind the menus.
	death_cause = cause
	if mode == Mode.PRACTICE:
		# Practice: restart the drill instantly.
		_start.call_deferred(Mode.PRACTICE)
		return
	dying = true


func _on_death_finished() -> void:
	if not dying:
		return
	_end_run()


func _on_finish() -> void:
	if state != State.RUNNING or dying:
		return
	finished = true
	world.stop_run()
	_end_run()


func _end_run() -> void:
	dying = false
	if mode != Mode.PRACTICE:
		new_best = Save.submit_score(mode_key(), score)
	_set_state(State.DEAD)
	run_ended.emit(score)


func pause() -> void:
	if state != State.RUNNING or dying:
		return
	get_tree().paused = true
	_set_state(State.PAUSED)


func resume() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	_set_state(State.RUNNING)


func restart() -> void:
	_start(mode)


func to_menu() -> void:
	get_tree().paused = false
	dying = false
	Engine.time_scale = 1.0
	if world != null:
		world.stop_run()
	_set_state(State.MENU)


## Quits after letting the audio thread release its playbacks.
func quit_game(code: int = 0) -> void:
	Audio.shutdown()
	await get_tree().process_frame
	# Give the mixing thread real time to drop the stopped playbacks.
	OS.delay_msec(60)
	await get_tree().process_frame
	get_tree().quit(code)


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	match state:
		State.RUNNING:
			if event.is_action_pressed(&"pause"):
				pause()
				get_viewport().set_input_as_handled()
		State.PAUSED:
			if event.is_action_pressed(&"pause"):
				resume()
				get_viewport().set_input_as_handled()
		State.DEAD:
			if event.is_action_pressed(&"restart"):
				play_again()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(&"same_seed"):
				replay_same_seed()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(&"pause"):
				to_menu()
				get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.RUNNING and pause_on_focus_loss:
		pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


# --- Seeds -------------------------------------------------------------------------

## Numeric input is used directly; any other text is hashed with FNV-1a 64.
static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t.is_valid_int():
		return t.to_int()
	return fnv1a64(t)


static func fnv1a64(text: String) -> int:
	return _limbs_to_int(fnv1a64_limbs(text))


static func fnv1a64_hex(text: String) -> String:
	var h := fnv1a64_limbs(text)
	return "%04x%04x%04x%04x" % [h[3], h[2], h[1], h[0]]


## FNV-1a 64 over UTF-8 bytes, computed in 16-bit limbs so no step overflows int64.
static func fnv1a64_limbs(text: String) -> Array[int]:
	var h: Array[int] = [0x2325, 0x8422, 0x9ce4, 0xcbf2]  # 0xcbf29ce484222325
	var prime: Array[int] = [0x01b3, 0x0000, 0x0100, 0x0000]  # 0x00000100000001b3
	for byte in text.to_utf8_buffer():
		h[0] = h[0] ^ byte
		var r: Array[int] = [0, 0, 0, 0]
		for i in 4:
			var carry := 0
			for j in 4 - i:
				var cur := r[i + j] + h[i] * prime[j] + carry
				r[i + j] = cur & 0xFFFF
				carry = cur >> 16
		h = r
	return h


static func _limbs_to_int(h: Array[int]) -> int:
	var hi := h[3]
	if hi >= 0x8000:
		hi -= 0x10000
	return hi * 0x1000000000000 + h[2] * 0x100000000 + h[1] * 0x10000 + h[0]


## Display string for the current seed.
func seed_label() -> String:
	if seed_text.is_empty() or seed_text == str(run_seed):
		return str(run_seed)
	return "%s  (#%d)" % [seed_text, run_seed]


func seed_copy_text() -> String:
	return seed_text if not seed_text.is_empty() else str(run_seed)


# --- Custom tracks -----------------------------------------------------------------

## Parses a *.gradient.json document. Returns {"ok": bool, "error": String, ...track}.
static func parse_custom_track(json_text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return {"ok": false, "error": "JSON error on line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	var d = json.data
	if not (d is Dictionary):
		return {"ok": false, "error": "The file must contain a JSON object."}
	if int(d.get("version", 0)) != 1:
		return {"ok": false, "error": "Unsupported version (expected 1)."}
	var chunks = d.get("chunks")
	if not (chunks is Array) or (chunks as Array).is_empty():
		return {"ok": false, "error": "\"chunks\" must be a non-empty list of chunk ids."}
	var cat := ChunkCatalogue.get_default()
	var ids: Array[String] = []
	for c in chunks:
		if not (c is String) or not cat.has(StringName(c)):
			return {"ok": false, "error": "Unknown chunk id: %s" % str(c)}
		ids.append(c)
	var start_speed := 0.0
	if d.has("start_speed"):
		if not (d["start_speed"] is float or d["start_speed"] is int) or float(d["start_speed"]) < 0.0:
			return {"ok": false, "error": "\"start_speed\" must be a positive number."}
		start_speed = clampf(float(d["start_speed"]), 0.0, TrackPlan.HARD_CAP)
	var seed_value := 0
	var seed_str := ""
	if d.has("seed"):
		var s = d["seed"]
		if s is float or s is int:
			seed_value = int(s)
		elif s is String:
			seed_str = s
			seed_value = parse_seed(s)
		else:
			return {"ok": false, "error": "\"seed\" must be a number or a string."}
	return {
		"ok": true, "error": "",
		"name": str(d.get("name", "Custom track")),
		"chunks": ids,
		"start_speed": start_speed,
		"seed": seed_value,
		"seed_text": seed_str,
		"loop": bool(d.get("loop", false)),
	}
