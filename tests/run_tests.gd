extends Node
## Headless test runner (no third-party framework needed). Runs as a scene so the
## autoloads exist exactly as in the game:
##
##   godot --headless --path . --fixed-fps 120 res://tests/test_runner.tscn -- [options]
##
## Options: --quick         shorten the long autoplay acceptance tests
##          --only=a,b      run only the named tests
## With --fixed-fps 120 every frame advances exactly one 120 Hz physics tick, so the
## autoplay tests simulate game time as fast as the machine allows.

const TESTS := [
	"fnv1a64", "seed_parsing", "speed_curve", "catalogue", "chunk_validation",
	"determinism_500", "pure_generate", "selection_rules", "difficulty_ramp", "hazard_gaps", "seam_geometry",
	"custom_track_parsing", "custom_and_practice_plans", "moving_hazard_replay",
	"steering_response", "chunk_traversal", "demo_bot", "restart_time", "autoplay_flat", "ccd_hazards", "ui_flow",
]

var quick := false
var failures: PackedStringArray = PackedStringArray()
var _current := ""
var _checks := 0
var _logger := ErrorCounter.new()
## Autoloads, resolved at runtime (their names are not compiled into -s scripts).
var game: Node
var save: Node
var GS: Script


func _ready() -> void:
	OS.add_logger(_logger)
	_main.call_deferred()


func _main() -> void:
	await get_tree().process_frame
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg == "--quick":
			quick = true
		elif arg.begins_with("--only="):
			only = arg.get_slice("=", 1).split(",")
	game = get_tree().root.get_node("Game")
	save = get_tree().root.get_node("Save")
	GS = game.get_script()
	save.reset_for_tests()
	var started := Time.get_ticks_msec()
	for t: String in TESTS:
		if not only.is_empty() and not only.has(t):
			continue
		_current = t
		var before := failures.size()
		var errors_before := _logger.errors
		var t0 := Time.get_ticks_msec()
		await call("test_" + t)
		if _logger.errors > errors_before:
			failures.append("%s: %d engine/script error(s) logged" % [t, _logger.errors - errors_before])
		var status := "ok" if failures.size() == before else "FAIL"
		print("[%s] %s (%.1f s)" % [status, t, (Time.get_ticks_msec() - t0) / 1000.0])
	print("")
	for m in _logger.messages:
		print(m)
	print("%d checks, %d failure(s), %d engine error(s), %d warning(s) in %.1f s" % [
		_checks, failures.size(), _logger.errors, _logger.warnings, (Time.get_ticks_msec() - started) / 1000.0])
	for f in failures:
		print("  FAIL ", f)
	ChunkCatalogue.release_default()
	TrackGeometry.clear_caches()
	game.quit_game(0 if failures.is_empty() and _logger.errors == 0 else 1)


func check(cond: bool, what: String) -> bool:
	_checks += 1
	if not cond:
		failures.append("%s: %s" % [_current, what])
	return cond


func info(text: String) -> void:
	print("    ", text)


# --- Unit tests ---------------------------------------------------------------------

func test_fnv1a64() -> void:
	check(game.fnv1a64_hex("") == "cbf29ce484222325", "FNV-1a 64 of empty string")
	check(game.fnv1a64_hex("a") == "af63dc4c8601ec8c", "FNV-1a 64 of 'a'")
	check(game.fnv1a64_hex("foobar") == "85944171f73967e8", "FNV-1a 64 of 'foobar'")
	check(game.fnv1a64("foobar") == game.fnv1a64("foobar"), "stable")
	# 0xcbf29ce484222325 as a signed 64-bit integer.
	check(game.fnv1a64("") == -3750763034362895579, "signed conversion")


func test_seed_parsing() -> void:
	check(game.parse_seed("1234") == 1234, "numeric seed used directly")
	check(game.parse_seed("  42 ") == 42, "whitespace stripped")
	check(game.parse_seed("-7") == -7, "negative numbers")
	check(game.parse_seed("sunset run") == game.fnv1a64("sunset run"), "text hashed with FNV-1a 64")
	check(game.parse_seed("12ab") == game.fnv1a64("12ab"), "mixed text is hashed")


func test_speed_curve() -> void:
	check(is_equal_approx(TrackPlan.speed_for_distance(0.0), 14.0), "base speed 14")
	check(is_equal_approx(TrackPlan.speed_for_distance(10.0), 14.35), "+0.35 per 10 m")
	var cap_d := (60.0 - 14.0) / 0.035
	check(is_equal_approx(TrackPlan.speed_for_distance(cap_d), 60.0), "soft cap at 60")
	check(is_equal_approx(TrackPlan.speed_for_distance(cap_d + 400.0), 63.5), "quarter rate above cap")
	check(is_equal_approx(TrackPlan.speed_for_distance(1e7), TrackPlan.HARD_CAP), "hard ceiling")
	for s in [14.0, 30.0, 60.0, 80.0, 120.0]:
		check(is_equal_approx(TrackPlan.speed_for_distance(TrackPlan.distance_for_speed(s)), s),
			"distance_for_speed inverts speed_for_distance at %d" % s)
	check(is_equal_approx(TrackPlan.difficulty_for_distance(0.0), 1.0), "difficulty starts at 1")
	check(is_equal_approx(TrackPlan.difficulty_for_distance(400.0), 2.0), "difficulty +1 per 400 m")
	check(is_equal_approx(TrackPlan.difficulty_for_distance(99999.0), 10.0), "difficulty capped at 10")


func test_catalogue() -> void:
	var cat := ChunkCatalogue.get_default()
	check(cat.errors.is_empty(), "catalogue loads without errors: %s" % ", ".join(cat.errors))
	var plain := 0
	for i in cat.infos:
		if not i.adapter:
			plain += 1
	check(plain >= 16, "at least 16 non-adapter chunks (have %d)" % plain)
	for id in ["straight_wide", "straight_narrow", "s_bend", "turn_left", "turn_right", "banked_sweeper",
			"step_down", "ramp_gap", "double_hump", "halfpipe_run", "tube", "tube_hole",
			"scatter_blocks", "picket", "sliding_block", "rising_block"]:
		check(cat.has(StringName(id)), "starter chunk %s exists" % id)
	for prof in TrackGeometry.PROFILES:
		check(prof == &"flat_wide" or not cat.adapter_path(prof, &"flat_wide").is_empty(), "adapter %s -> flat_wide" % prof)
		check(prof == &"flat_wide" or not cat.adapter_path(&"flat_wide", prof).is_empty(), "adapter flat_wide -> %s" % prof)
		var has_breather := false
		for i in cat.infos:
			if i.is_breather() and i.entry_profile == prof and i.exit_profile == prof:
				has_breather = true
		check(has_breather, "breather chunk for profile %s" % prof)


func test_chunk_validation() -> void:
	var report := ChunkValidationReport.run()
	check(report["count"] >= 22, "all chunk scenes found (%d)" % report["count"])
	check((report["errors"] as PackedStringArray).is_empty(), "chunks valid: %s" % ", ".join(report["errors"]))
	# The validator must catch a broken join.
	var bad := ChunkInfo.new()
	bad.id = &"bad"
	bad.sections = [{"len": 20.0, "pitch": 5.0}]
	bad.length = 20.0
	check(not ChunkValidator.validate(bad, "bad").is_empty(), "validator rejects pitch mismatch at exit")
	var bad2 := ChunkInfo.new()
	bad2.id = &"bad2"
	bad2.sections = [{"len": 20.0, "profile": "tube"}]
	bad2.length = 20.0
	check(not ChunkValidator.validate(bad2, "bad2").is_empty(), "validator rejects exit profile mismatch")


func test_determinism_500() -> void:
	for s in [12345, game.parse_seed("gradient"), -99]:
		var a := TrackPlan.endless(s)
		var b := TrackPlan.endless(s)
		var same := true
		for i in 500:
			if not a.get_spec(i).equals(b.get_spec(i)):
				same = false
				info("seed %d differs at %d" % [s, i])
				break
		check(same, "seed %d: first 500 ChunkSpecs identical" % s)
	var x := TrackPlan.endless(1)
	var y := TrackPlan.endless(2)
	var differs := false
	for i in 50:
		if not x.get_spec(i).equals(y.get_spec(i)):
			differs = true
			break
	check(differs, "different seeds give different tracks")


func test_pure_generate() -> void:
	var plan := TrackPlan.endless(777)
	for i in [0, 1, 17, 120, 499]:
		check(TrackPlan.generate(777, i).equals(plan.get_spec(i)), "generate(777, %d) matches the plan" % i)


func test_selection_rules() -> void:
	var cat := ChunkCatalogue.get_default()
	var fallbacks := 0
	var hazard_chunks := 0
	for s in [1, 2, 3, 4, 5]:
		var plan := TrackPlan.endless(s)
		var prev: ChunkSpec = null
		var prev2: ChunkSpec = null
		var last_breather := 0
		for i in 500:
			var spec := plan.get_spec(i)
			var inf := cat.get_info(spec.id)
			if prev != null:
				var pinf := cat.get_info(prev.id)
				if not check(pinf.exit_profile == inf.entry_profile, "seed %d #%d: profile chain %s -> %s" % [s, i, prev.id, spec.id]):
					return
				check(is_equal_approx(spec.start_distance, prev.start_distance + prev.length), "distances accumulate")
			if spec.fallback > 0:
				fallbacks += 1
			elif i > 0 and not spec.forced_breather:
				check(float(inf.difficulty) <= spec.difficulty + 1.0, "difficulty <= d + 1 (%s)" % spec.id)
				check(spec.target_speed >= inf.min_speed and spec.target_speed <= inf.max_speed, "speed band (%s)" % spec.id)
				check((prev == null or prev.id != spec.id) and (prev2 == null or prev2.id != spec.id),
					"no repeat of the previous two (%s at #%d)" % [spec.id, i])
			if spec.forced_breather:
				check(inf.is_breather(), "breather has no hazards")
				var gap := i - last_breather
				check(gap >= 6 and gap <= 9, "breather every 6-9 chunks (gap %d)" % gap)
				last_breather = i
			if not spec.hazards.is_empty():
				hazard_chunks += 1
			prev2 = prev
			prev = spec
	info("fallback picks: %d of 2500, hazard chunks: %d" % [fallbacks, hazard_chunks])
	check(hazard_chunks > 100, "hazards appear")


func test_difficulty_ramp() -> void:
	# Obstacles show up right away and get denser as the difficulty rises.
	var early_runs := 0
	var early_density := 0.0
	var early_len := 0.0
	var late_density := 0.0
	var late_len := 0.0
	for s in 40:
		var plan := TrackPlan.endless(1000 + s)
		var seen_early := false
		for i in 300:
			var spec := plan.get_spec(i)
			if i <= 4 and not spec.hazards.is_empty():
				seen_early = true
			if spec.hazards.is_empty():
				continue
			if spec.difficulty < 2.0:
				early_density += spec.hazards.size()
				early_len += spec.length
			elif spec.difficulty >= 8.0:
				late_density += spec.hazards.size()
				late_len += spec.length
		if seen_early:
			early_runs += 1
	var e := early_density / maxf(early_len, 1.0) * 100.0
	var l := late_density / maxf(late_len, 1.0) * 100.0
	info("runs with an obstacle in the first 4 chunks: %d/40; obstacles per 100 m of hazard chunk: %.1f at d<2, %.1f at d>=8" % [early_runs, e, l])
	check(early_runs >= 32, "obstacles appear within the first few chunks in most runs")
	check(l > e * 1.3, "hazard density ramps up with difficulty")


func test_hazard_gaps() -> void:
	# Every static row of blocks leaves a gap the ball (1 m) can pass through.
	var cat := ChunkCatalogue.get_default()
	var rows_checked := 0
	for s in 30:
		var plan := TrackPlan.endless(500 + s)
		for i in 200:
			var spec := plan.get_spec(i)
			var data := TrackGeometry.get_samples(cat.get_info(spec.id))
			var rows := {}
			for h in spec.hazards:
				if h["kind"] == "block":
					var key := snappedf(float(h["along"]), 0.01)
					if not rows.has(key):
						rows[key] = []
					rows[key].append(Vector2(float(h["x"]) - float(h["w"]) * 0.5, float(h["x"]) + float(h["w"]) * 0.5))
			for key in rows:
				var width := TrackGeometry.flat_width(data["cross"][TrackGeometry.sample_index(data, key)])
				var spans: Array = rows[key]
				spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
				var best := 0.0
				var x := -width * 0.5
				for sp: Vector2 in spans:
					best = maxf(best, sp.x - x)
					x = maxf(x, sp.y)
				best = maxf(best, width * 0.5 - x)
				rows_checked += 1
				if not check(best >= 1.5, "%s row at %.1f m leaves a gap >= 1.5 m (%.2f)" % [spec.id, key, best]):
					return
	info("%d obstacle rows checked" % rows_checked)


func test_seam_geometry() -> void:
	# Joins are compared in the local frame of the join (the floating origin keeps the
	# world near 0, so absolute coordinates never get large in a real run).
	var cat := ChunkCatalogue.get_default()
	var plan := TrackPlan.endless(4242)
	var worst := 0.0
	for i in 300:
		var inf := cat.get_info(plan.get_spec(i).id)
		var nxt := cat.get_info(plan.get_spec(i + 1).id)
		var exit_pts := TrackGeometry.end_cross_section(inf, true)
		var exit_xf: Transform3D = TrackGeometry.get_samples(inf)["exit"]
		var entry_pts := TrackGeometry.end_cross_section(nxt, false)
		for k in exit_pts.size():
			worst = maxf(worst, exit_pts[k].distance_to(exit_xf * entry_pts[k]))
	info("worst join mismatch over 300 joins: %.7f m" % worst)
	check(worst < 1e-4, "join vertices coincide (worst %.7f m)" % worst)
	# The streamed world (chained transforms + origin shift) stays within 2 km of 0.
	var xf := Transform3D.IDENTITY
	var far := 0.0
	for i in 300:
		xf = xf * (TrackGeometry.get_samples(cat.get_info(plan.get_spec(i).id))["exit"] as Transform3D)
		far = maxf(far, xf.origin.length())
	info("without origin shifting the track would reach %.0f m from the origin" % far)
	# Every chunk's collision is a single merged concave shape.
	for inf in cat.infos:
		var built := TrackGeometry.get_mesh(inf)
		check(built["shape"] is ConcavePolygonShape3D and (built["faces"] as PackedVector3Array).size() > 0,
			"%s has merged concave collision" % inf.id)


func test_custom_track_parsing() -> void:
	var f := FileAccess.open("res://data/custom_tracks/example.gradient.json", FileAccess.READ)
	var t: Dictionary = game.parse_custom_track(f.get_as_text())
	check(t["ok"], "example parses: %s" % t["error"])
	check(t["chunks"] == ["straight_wide", "ramp_gap", "tube", "picket"], "chunk list kept")
	check(is_equal_approx(t["start_speed"], 30.0) and t["seed"] == 1234 and t["loop"] == false, "fields parsed")
	check(not game.parse_custom_track("{").ok, "bad JSON rejected")
	check(not game.parse_custom_track('{"version": 2, "chunks": ["tube"]}').ok, "bad version rejected")
	check(not game.parse_custom_track('{"version": 1, "chunks": ["nope"]}').ok, "unknown chunk rejected")
	check(not game.parse_custom_track('{"version": 1, "chunks": []}').ok, "empty list rejected")
	check(game.parse_custom_track('{"version": 1, "chunks": ["tube"], "seed": "abc"}')["seed"] == game.fnv1a64("abc"),
		"string seed hashed")


func test_custom_and_practice_plans() -> void:
	var cat := ChunkCatalogue.get_default()
	var ids: Array[StringName] = [&"straight_wide", &"ramp_gap", &"tube", &"picket"]
	var plan := TrackPlan.custom(1234, ids, false, 30.0)
	var seq: Array[String] = []
	for i in 9:
		seq.append(String(plan.get_spec(i).id))
	info("custom sequence: %s" % ", ".join(seq))
	# Index 0 is the lead-in; listed chunks follow with adapters inserted where needed.
	check(seq.slice(1, 7) == ["straight_wide", "ramp_gap", "adapter_wide_tube", "tube", "adapter_tube_wide", "picket"],
		"custom order with adapters")
	check(plan.finish_index == 7 and plan.get_spec(7).finish, "finish after the last chunk")
	check(is_equal_approx(plan.target_speed(0.0), 30.0), "custom start speed")
	for i in range(1, 12):
		var a := cat.get_info(plan.get_spec(i - 1).id)
		var b := cat.get_info(plan.get_spec(i).id)
		check(a.exit_profile == b.entry_profile, "custom joins match")
	var looped := TrackPlan.custom(5, [&"picket", &"tube"] as Array[StringName], true, 0.0)
	for i in 30:
		looped.get_spec(i)
	check(looped.finish_index == -1, "looping track never finishes")
	var practice := TrackPlan.practice(9, [&"tube_hole"] as Array[StringName], 33.0)
	var count := 0
	for i in 20:
		if practice.get_spec(i).id == &"tube_hole":
			count += 1
		if i > 0:
			check(cat.get_info(practice.get_spec(i - 1).id).exit_profile == cat.get_info(practice.get_spec(i).id).entry_profile,
				"practice joins match")
	check(count >= 9, "practice loops the chosen chunk (%d of 20)" % count)
	check(is_equal_approx(practice.target_speed(5000.0), 33.0), "practice speed is fixed")


# --- Simulation tests ------------------------------------------------------------------

func _make_world() -> World:
	var w := (load("res://game/world.tscn") as PackedScene).instantiate() as World
	get_tree().root.add_child(w)
	await get_tree().process_frame
	return w


func _free_world(w: World) -> void:
	w.stop_run()
	w.generator.clear()
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func test_moving_hazard_replay() -> void:
	var samples: Array = []
	for run in 2:
		var w: World = await _make_world()
		w.start_run(TrackPlan.practice(31337, [&"sliding_block", &"rising_block"] as Array[StringName], 40.0))
		w.ball.autopilot = func(_b: Ball, _f: TrackFrame) -> float: return 0.0
		var record := PackedFloat32Array()
		for tick in 360:
			await get_tree().physics_frame
			if tick % 30 == 0:
				for c: Chunk in w.generator.chunks.values():
					for h in c.moving_hazards:
						record.append(h.position.x)
						record.append(h.position.y)
		samples.append(record)
		await _free_world(w)
	check(samples[0].size() > 0 and samples[0] == samples[1], "moving hazards line up identically on replay")


func test_steering_response() -> void:
	for speed in [14.0, 50.0]:
		var w: World = await _make_world()
		w.start_run(TrackPlan.practice(1, [&"straight_wide"] as Array[StringName], speed))
		w.ball.autopilot = func(_b: Ball, _f: TrackFrame) -> float: return 0.0
		for tick in 60:
			await get_tree().physics_frame
		var right := w.ball.frame.transform.basis.x
		var x0 := (w.ball.global_position - w.ball.frame.transform.origin).dot(right)
		w.ball.autopilot = func(_b: Ball, _f: TrackFrame) -> float: return 1.0
		var reached := -1
		for tick in 60:
			await get_tree().physics_frame
			if reached < 0 and w.ball.linear_velocity.dot(w.ball.frame.transform.basis.x) > 11.5:
				reached = tick
		var x1 := (w.ball.global_position - w.ball.frame.transform.origin).dot(w.ball.frame.transform.basis.x)
		var fwd := -w.ball.frame.transform.basis.z
		var vf := w.ball.linear_velocity.dot(fwd)
		info("speed %d: full lateral speed after %d ticks, moved %.2f m right, forward %.1f m/s" % [speed, reached, x1 - x0, vf])
		check(w.ball.alive, "ball alive while steering at %d m/s" % speed)
		check(reached > 0 and reached < 50, "reaches max lateral speed in < 0.42 s at %d m/s" % speed)
		check(vf >= speed - 0.01 and vf <= speed * 1.15 + 0.01, "governor keeps forward speed in band at %d" % speed)
		await _free_world(w)


func test_chunk_traversal() -> void:
	# Every hazard-free chunk must be survivable by a simple bot at low, mid and top
	# speed of its band (the tube with a hole is ridden on the side wall).
	var cat := ChunkCatalogue.get_default()
	for inf in cat.infos:
		if inf.adapter or not inf.hazard_slots.is_empty():
			continue
		for speed in [14.0, 45.0, minf(inf.max_speed, TrackPlan.HARD_CAP)]:
			var w: World = await _make_world()
			w.start_run(TrackPlan.practice(3, [inf.id] as Array[StringName], speed))
			var lane := 2.3 if inf.id == &"tube_hole" else 0.0
			w.ball.autopilot = func(b: Ball, f: TrackFrame) -> float:
				if f == null:
					return 0.0
				var off := (b.global_position - f.transform.origin).dot(f.transform.basis.x) - lane
				return clampf(-(off * 1.2 + b.linear_velocity.dot(f.transform.basis.x) * 0.3), -1.0, 1.0)
			var air := 0
			var loops_len := (inf.length + 60.0) * 3.0
			var ticks := int((loops_len / speed + 1.0) * 120.0)
			var died := ""
			for tick in ticks:
				await get_tree().physics_frame
				if not w.ball.alive:
					died = "died at %.0f m" % w.generator.progress
					break
				if w.ball.is_airborne():
					air += 1
			check(died.is_empty(), "%s at %d m/s survivable (%s)" % [inf.id, speed, died])
			if inf.id == &"ramp_gap":
				check(air > 10, "ramp_gap launches the ball at %d m/s (%d airborne ticks)" % [speed, air])
			await _free_world(w)


func test_demo_bot() -> void:
	# The attract-mode bot should get well into a hazard-filled endless run.
	var distances: Array[float] = []
	for s in 6:
		var w: World = await _make_world()
		w.start_run(TrackPlan.endless(4000 + s))
		w.ball.autopilot = Autopilot.dodger
		for tick in 120 * 90:
			await get_tree().physics_frame
			if not w.ball.alive:
				break
		distances.append(w.generator.progress)
		await _free_world(w)
	distances.sort()
	info("dodger distances (m): %s" % ", ".join(distances.map(func(d: float) -> String: return "%.0f" % d)))
	check(distances[distances.size() / 2] > 500.0, "demo bot median distance > 500 m")


func test_restart_time() -> void:
	var w: World = await _make_world()
	var t0 := Time.get_ticks_usec()
	w.start_run(TrackPlan.endless(5))
	var cold := (Time.get_ticks_usec() - t0) / 1e6
	for tick in 120:
		await get_tree().physics_frame
	w.ball.kill("test")
	var t1 := Time.get_ticks_usec()
	w.start_run(TrackPlan.endless(6))
	var warm := (Time.get_ticks_usec() - t1) / 1e6
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rolling := w.ball.alive and w.ball.linear_velocity.length() >= 13.9
	info("track rebuild: cold %.0f ms, warm %.0f ms; death sequence %.1f s" % [cold * 1000.0, warm * 1000.0, w.SLOWMO_TIME])
	check(rolling, "ball rolling at base speed right after restart")
	check(w.SLOWMO_TIME + warm < 1.0, "death -> rolling again < 1 s (%.2f s)" % (w.SLOWMO_TIME + warm))
	check(w.SLOWMO_TIME + cold < 1.0, "even a cold rebuild fits in 1 s (%.2f s)" % (w.SLOWMO_TIME + cold))
	await _free_world(w)


func test_autoplay_flat() -> void:
	var seconds := 60.0 if quick else 600.0
	var w: World = await _make_world()
	var pool: Array[StringName] = [&"straight_wide", &"straight_narrow"]
	var plan := TrackPlan.practice(2024, pool, 0.0)  # fixed_speed 0 = normal speed curve
	w.start_run(plan)
	w.ball.autopilot = Autopilot.centre_seeking
	var ticks := int(seconds * 120.0)
	var deaths := 0
	var airborne := 0
	var max_gap := 0.0
	for tick in ticks:
		await get_tree().physics_frame
		if not w.ball.alive:
			deaths += 1
			info("death at tick %d (%.1f s), progress %.0f m" % [tick, tick / 120.0, w.generator.progress])
			plan = TrackPlan.practice(2024 + deaths, pool, 0.0)
			w.start_run(plan)
			w.ball.autopilot = Autopilot.centre_seeking
			continue
		if w.ball.ticks > 2 and w.ball.is_airborne():
			airborne += 1
		var f := w.ball.frame
		if f != null:
			max_gap = maxf(max_gap, (w.ball.global_position - f.transform.origin).dot(f.transform.basis.y) - 0.5)
	info("%.0f s simulated: %.1f km, end speed %.0f m/s, %d chunks, %d origin shifts, max height above floor %.3f m" % [
		seconds, w.generator.progress / 1000.0, w.ball.linear_velocity.length(), plan.generated_count(),
		w.generator.origin_shifts, max_gap])
	check(airborne == 0, "no airborne frames on flat chunks (%d)" % airborne)
	check(deaths == 0, "no deaths from seams (%d)" % deaths)
	check(w.generator.origin_shifts > 0, "origin shift exercised")
	await _free_world(w)


func test_ccd_hazards() -> void:
	var seconds := 120.0 if quick else 1800.0
	var w: World = await _make_world()
	var pool: Array[StringName] = []
	for inf in ChunkCatalogue.get_default().infos:
		if not inf.hazard_slots.is_empty():
			pool.append(inf.id)
	var plan_seed := 77
	w.start_run(TrackPlan.practice(plan_seed, pool, 60.0))
	w.ball.autopilot = Autopilot.centre_seeking
	var ticks := int(seconds * 120.0)
	var prev := w.ball.global_position
	var deaths := 0
	var tunnels := 0
	var suspects: Array = []  # [tick, hazard name]
	var hazard_ticks := 0
	for tick in ticks:
		await get_tree().physics_frame
		if not w.ball.alive:
			deaths += 1
			suspects.clear()
			plan_seed += 1
			w.start_run(TrackPlan.practice(plan_seed, pool, 60.0))
			w.ball.autopilot = Autopilot.centre_seeking
			prev = w.ball.global_position
			continue
		var cur := w.ball.global_position
		# A suspect that is still alive 4 ticks after its sweep crossed a hazard tunnelled.
		for s in suspects.duplicate():
			if tick - int(s[0]) >= 4:
				tunnels += 1
				info("tunnelled through %s at tick %d" % [s[1], s[0]])
				suspects.erase(s)
		if cur.distance_to(prev) < 5.0:
			for idx in [w.generator.current_index, w.generator.current_index + 1]:
				var ch := w.generator.get_chunk(idx)
				if ch == null:
					continue
				for body in ch.hazard_bodies:
					var hz := body as Node3D
					if hz.global_position.distance_to(cur) > 6.0:
						continue
					hazard_ticks += 1
					var size: Vector3 = body.get("size")
					var inv := hz.global_transform.affine_inverse()
					if _segment_hits_box(inv * prev, inv * cur, size * 0.5 + Vector3.ONE * (0.5 - 0.1)):
						suspects.append([tick, hz.name])
		prev = cur
	info("%.0f s at 60 m/s: %d hazard deaths, %d hazard proximity ticks, %d tunnelling events" % [
		seconds, deaths, hazard_ticks, tunnels])
	check(deaths > 10, "the centre-seeking bot actually hits hazards")
	check(tunnels == 0, "no tunnelling through hazards at 60 m/s")
	await _free_world(w)


static func _segment_hits_box(a: Vector3, b: Vector3, half: Vector3) -> bool:
	var tmin := 0.0
	var tmax := 1.0
	var d := b - a
	for axis in 3:
		if absf(d[axis]) < 1e-9:
			if absf(a[axis]) > half[axis]:
				return false
		else:
			var t1 := (-half[axis] - a[axis]) / d[axis]
			var t2 := (half[axis] - a[axis]) / d[axis]
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
			if tmin > tmax:
				return false
	return true


func test_ui_flow() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	check(game.state == GS.State.MENU and main.current_page == "title", "starts on the title screen")
	for page in ["seed", "practice", "custom", "settings", "title"]:
		main._navigate(page)
		await get_tree().process_frame
		check(main.current_page == page, "navigates to %s" % page)
	game.play_endless()
	for i in 30:
		await get_tree().physics_frame
	check(game.state == GS.State.RUNNING and main.current_page == "hud", "endless run starts with the HUD")
	var endless_seed: int = game.run_seed
	game.pause()
	await get_tree().process_frame
	check(game.state == GS.State.PAUSED and main.current_page == "pause", "pause")
	game.resume()
	await get_tree().process_frame
	check(game.state == GS.State.RUNNING, "resume")
	main.world.ball.kill("hazard")
	for i in 120:
		await get_tree().process_frame
		if game.state == GS.State.DEAD:
			break
	check(game.state == GS.State.DEAD and main.current_page == "death", "death screen after the slow-motion")
	check(is_equal_approx(Engine.time_scale, 1.0), "time scale restored")
	game.replay_same_seed()
	await get_tree().process_frame
	check(game.mode == GS.Mode.SEEDED and game.run_seed == endless_seed, "same seed replays as a seeded run")
	game.play_seeded("sunset run")
	check(game.run_seed == game.fnv1a64("sunset run"), "seeded run hashes text")
	game.play_practice("chunk:picket", 25.0)
	await get_tree().physics_frame
	main.world.ball.kill("hazard")
	for i in 4:
		await get_tree().physics_frame
	check(game.state == GS.State.RUNNING and main.world.ball.alive, "practice restarts instantly")
	var track: Dictionary = game.parse_custom_track('{"version":1,"chunks":["straight_wide"],"loop":false}')
	game.play_custom(track)
	# Lead-in + listed chunk = 100 m before the finish at 14 m/s: ~860 ticks.
	for i in 1500:
		await get_tree().physics_frame
		if game.state == GS.State.DEAD:
			break
	check(game.state == GS.State.DEAD and game.finished, "custom track completes")
	check(game.score > 0, "score gates counted on the custom track (%d)" % game.score)
	save.set_setting("palette", "colorblind")
	save.set_setting("high_contrast", true)
	await get_tree().process_frame
	save.set_setting("palette", "default")
	save.set_setting("high_contrast", false)
	game.to_menu()
	await get_tree().process_frame
	check(game.state == GS.State.MENU and main.current_page == "title", "back to menu")
	main.queue_free()
	await get_tree().process_frame
