class_name TrackPlan
extends RefCounted
## Deterministic chunk sequence for one run. All generation randomness comes from a
## single RandomNumberGenerator seeded with the run seed; nothing at runtime feeds back
## into it. `generate(seed, index)` is a pure function of its arguments.

enum Kind { ENDLESS, PRACTICE, CUSTOM }

const START_CHUNK := &"straight_wide"
const BASE_SPEED := 14.0
const SPEED_PER_METRE := 0.035
const SOFT_CAP := 60.0
## Hard ceiling (tuning; the spec's numbers are starting points). Above the soft cap
## speed keeps growing at a quarter rate, which is exponential in time (~390 m/s after
## 10 minutes). It is capped at 120 m/s: far beyond reaction limits, and the highest
## speed where 120 Hz physics is verified seam-free (about 1 m per tick; above ~150 m/s
## speculative contacts against chunk-join edges start to kick the ball).
const HARD_CAP := 120.0
const BREATHER_MIN := 6
const BREATHER_MAX := 9
const SIGMA := 2.0

var run_seed: int = 0
var kind: Kind = Kind.ENDLESS
var catalogue: ChunkCatalogue
## Extra distance fed to the speed formula only (custom start speed).
var speed_offset: float = 0.0
## Practice: constant target speed (> 0 overrides the speed curve).
var fixed_speed: float = 0.0
## Practice: chunk ids to loop (one, or every chunk with a tag).
var practice_pool: Array[StringName] = []
## Custom track: ordered ids and loop flag.
var custom_chunks: Array[StringName] = []
var custom_loop: bool = false
## Index of the first finish chunk on a non-looping custom track (-1 = none).
var finish_index: int = -1

var _rng := RandomNumberGenerator.new()
var _specs: Array[ChunkSpec] = []
var _recent: Array[StringName] = []
var _queue: Array[StringName] = []
var _custom_pos: int = 0
var _breather_countdown: int = 0
var _distance: float = 0.0
var _profile: StringName = &"flat_wide"


func _init(p_seed: int = 0, p_catalogue: ChunkCatalogue = null) -> void:
	run_seed = p_seed
	catalogue = p_catalogue if p_catalogue != null else ChunkCatalogue.get_default()
	_rng.seed = p_seed


static func endless(p_seed: int, p_catalogue: ChunkCatalogue = null) -> TrackPlan:
	return TrackPlan.new(p_seed, p_catalogue)


static func practice(p_seed: int, pool: Array[StringName], speed: float,
		p_catalogue: ChunkCatalogue = null) -> TrackPlan:
	var plan := TrackPlan.new(p_seed, p_catalogue)
	plan.kind = Kind.PRACTICE
	plan.practice_pool = pool
	plan.fixed_speed = speed
	return plan


static func custom(p_seed: int, chunks: Array[StringName], loop: bool, start_speed: float,
		p_catalogue: ChunkCatalogue = null) -> TrackPlan:
	var plan := TrackPlan.new(p_seed, p_catalogue)
	plan.kind = Kind.CUSTOM
	plan.custom_chunks = chunks
	plan.custom_loop = loop
	plan.speed_offset = distance_for_speed(start_speed) if start_speed > 0.0 else 0.0
	return plan


## Pure: the spec at `index` for an endless run with `p_seed`.
static func generate(p_seed: int, index: int, p_catalogue: ChunkCatalogue = null) -> ChunkSpec:
	return TrackPlan.new(p_seed, p_catalogue).get_spec(index)


static func speed_for_distance(distance: float) -> float:
	var s := BASE_SPEED + SPEED_PER_METRE * maxf(distance, 0.0)
	if s <= SOFT_CAP:
		return s
	var cap_distance := (SOFT_CAP - BASE_SPEED) / SPEED_PER_METRE
	return minf(SOFT_CAP + SPEED_PER_METRE * 0.25 * (distance - cap_distance), HARD_CAP)


static func distance_for_speed(speed: float) -> float:
	speed = minf(speed, HARD_CAP)
	if speed <= BASE_SPEED:
		return 0.0
	var cap_distance := (SOFT_CAP - BASE_SPEED) / SPEED_PER_METRE
	if speed <= SOFT_CAP:
		return (speed - BASE_SPEED) / SPEED_PER_METRE
	return cap_distance + (speed - SOFT_CAP) / (SPEED_PER_METRE * 0.25)


static func difficulty_for_distance(distance: float) -> float:
	return clampf(1.0 + distance / 400.0, 1.0, 10.0)


static func bell(x: float, mu: float, sigma: float) -> float:
	return exp(-((x - mu) * (x - mu)) / (2.0 * sigma * sigma))


## Target forward speed at a run distance (scoring distance, starting at 0).
func target_speed(distance: float) -> float:
	if fixed_speed > 0.0:
		return fixed_speed
	return speed_for_distance(distance + speed_offset)


func get_spec(index: int) -> ChunkSpec:
	while _specs.size() <= index:
		_generate_next()
	return _specs[index]


func generated_count() -> int:
	return _specs.size()


func _generate_next() -> void:
	var index := _specs.size()
	var id: StringName
	var forced := false
	var fallback := 0
	var d := difficulty_for_distance(_distance)
	var speed := target_speed(_distance)
	if index == 0:
		id = START_CHUNK
		_breather_countdown = _rng.randi_range(BREATHER_MIN, BREATHER_MAX)
	else:
		match kind:
			Kind.ENDLESS:
				_breather_countdown -= 1
				if _breather_countdown <= 0:
					id = _pick_breather()
					forced = true
					_breather_countdown = _rng.randi_range(BREATHER_MIN, BREATHER_MAX)
				else:
					var pick := _pick_weighted(d, speed)
					id = pick[0]
					fallback = pick[1]
			Kind.PRACTICE:
				id = _next_practice()
			Kind.CUSTOM:
				id = _next_custom(index)

	var info := catalogue.get_info(id)
	var spec := ChunkSpec.new()
	spec.index = index
	spec.id = id
	spec.start_distance = _distance
	spec.length = info.length
	spec.difficulty = d
	spec.target_speed = speed
	spec.forced_breather = forced
	spec.fallback = fallback
	spec.finish = finish_index >= 0 and index >= finish_index
	_resolve_layout(spec, info)
	_specs.append(spec)

	_distance += info.length
	_profile = info.exit_profile
	_recent.append(id)
	if _recent.size() > 2:
		_recent.pop_front()


func _pick_breather() -> StringName:
	var options: Array[ChunkInfo] = []
	for info in catalogue.infos:
		if info.is_breather() and info.entry_profile == _profile and info.exit_profile == _profile:
			options.append(info)
	var fresh: Array[ChunkInfo] = []
	for o in options:
		if not _recent.has(o.id):
			fresh.append(o)
	if not fresh.is_empty():
		options = fresh
	if options.is_empty():
		return _pick_weighted(difficulty_for_distance(_distance), target_speed(_distance))[0]
	var weights := PackedFloat32Array()
	for info in options:
		weights.append(info.weight)
	return options[_weighted_index(weights)].id


## Returns [id, fallback_level].
func _pick_weighted(d: float, speed: float) -> Array:
	for level in 3:
		var options: Array[ChunkInfo] = []
		var weights := PackedFloat32Array()
		for info in catalogue.infos:
			if info.entry_profile != _profile:
				continue
			if level < 2 and float(info.difficulty) > d + 1.0:
				continue
			if level < 2 and (speed < info.min_speed or speed > info.max_speed):
				continue
			if level < 1 and _recent.has(info.id):
				continue
			var w := info.weight * bell(float(info.difficulty), d, SIGMA)
			if w > 0.0:
				options.append(info)
				weights.append(w)
		if not options.is_empty():
			return [options[_weighted_index(weights)].id, level]
	var path := catalogue.adapter_path(_profile, &"flat_wide")
	return [path[0] if not path.is_empty() else START_CHUNK, 3]


func _weighted_index(weights: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := _rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r < 0.0:
			return i
	return weights.size() - 1


func _enqueue_with_adapters(id: StringName) -> void:
	var info := catalogue.get_info(id)
	var from := _profile
	if not _queue.is_empty():
		from = catalogue.get_info(_queue.back()).exit_profile
	_queue.append_array(catalogue.adapter_path(from, info.entry_profile))
	_queue.append(id)


func _next_practice() -> StringName:
	if _queue.is_empty():
		var pick: StringName
		if practice_pool.size() == 1:
			pick = practice_pool[0]
		else:
			var weights := PackedFloat32Array()
			for id in practice_pool:
				weights.append(catalogue.get_info(id).weight)
			pick = practice_pool[_weighted_index(weights)]
		_enqueue_with_adapters(pick)
	return _queue.pop_front()


func _next_custom(index: int) -> StringName:
	if _queue.is_empty():
		if _custom_pos < custom_chunks.size():
			_enqueue_with_adapters(custom_chunks[_custom_pos])
			_custom_pos += 1
			if custom_loop and _custom_pos >= custom_chunks.size():
				_custom_pos = 0
		else:
			# Run-out after the last chunk; reaching it completes the track.
			_enqueue_with_adapters(START_CHUNK)
			if finish_index < 0:
				finish_index = index + _queue.size() - 1
	return _queue.pop_front()


# --- Hazard, gate and decor layout (all from the run RNG) ---------------------------

func _resolve_layout(spec: ChunkSpec, info: ChunkInfo) -> void:
	var data := TrackGeometry.get_samples(info)
	var speed := spec.target_speed
	var d := spec.difficulty
	# 0 at difficulty 1, 1 at difficulty 10: drives hazard density and tempo.
	var t := clampf((d - 1.0) / 9.0, 0.0, 1.0)
	var groups := PackedFloat32Array()
	for slot in info.hazard_slots:
		match String(slot["type"]):
			"scatter":
				var along := float(slot["from"])
				var to := float(slot["to"])
				# Rows get closer with difficulty but never closer than ~0.45 s of travel.
				var spacing := maxf(lerpf(20.0, 9.0, t), speed * 0.45)
				var lanes_x := _lanes(data, along)
				while along <= to:
					var count := 1
					if _rng.randf() < lerpf(0.2, 0.75, t):
						count += 1
					if d >= 6.0 and lanes_x.size() >= 5 and _rng.randf() < lerpf(0.0, 0.5, t):
						count += 1
					var free: Array = range(lanes_x.size())
					for c in count:
						if free.size() <= 1:
							break  # Always leave at least one open lane.
						var li := _rng.randi_range(0, free.size() - 1)
						var lane: int = free[li]
						free.remove_at(li)
						# Neighbouring lanes stay open so no two blocks merge into a wall.
						free.erase(lane - 1)
						free.erase(lane + 1)
						spec.hazards.append({"kind": "block", "along": along, "x": lanes_x[lane],
							"w": 1.4, "h": 1.2, "d": 1.4})
					groups.append(along)
					along += spacing + _rng.randf_range(0.0, 3.0)
			"slalom":
				var along := float(slot["from"])
				var to := float(slot["to"])
				var side := -1.0 if _rng.randf() < 0.5 else 1.0
				# Lateral travel needs time: keep walls at least ~0.55 s apart.
				var spacing := maxf(lerpf(22.0, 12.0, t), speed * 0.55 + 4.0)
				while along <= to:
					var width := TrackGeometry.flat_width(data["cross"][TrackGeometry.sample_index(data, along)])
					var half := width * 0.5
					var cover := width * lerpf(0.48, 0.62, t)
					var x0 := -half if side < 0.0 else half - cover
					spec.hazards.append({"kind": "block", "along": along, "x": x0 + cover * 0.5,
						"w": cover, "h": 1.3, "d": 0.8})
					groups.append(along)
					side = -side
					along += spacing + _rng.randf_range(0.0, 4.0)
			"picket":
				for a in slot["at"]:
					var along := float(a)
					var width := TrackGeometry.flat_width(data["cross"][TrackGeometry.sample_index(data, along)])
					var openings := 2 if (d < 5.0 or _rng.randf() < 0.35) else 1
					var ow := lerpf(2.8, 1.7, t)
					var centres: Array[float] = []
					var half := width * 0.5
					var tries := 0
					while centres.size() < openings and tries < 32:
						tries += 1
						var c := _rng.randf_range(-half + ow * 0.5 + 0.2, half - ow * 0.5 - 0.2)
						var ok := true
						for e in centres:
							if absf(e - c) < ow + 0.8:
								ok = false
						if ok:
							centres.append(c)
					centres.sort()
					var x := -half
					for c in centres:
						_add_post(spec, along, x, c - ow * 0.5)
						x = c + ow * 0.5
					_add_post(spec, along, x, half)
					groups.append(along)
			"slider":
				for a in slot["at"]:
					spec.hazards.append({"kind": "slider", "along": float(a), "x": 0.0,
						"w": 1.8, "h": 1.2, "d": 1.2,
						"amp": 2.4, "period": lerpf(2.8, 1.4, t) * _rng.randf_range(0.85, 1.15),
						"phase": _rng.randf_range(0.0, TAU)})
					groups.append(float(a))
			"riser":
				for a in slot["at"]:
					var base := _rng.randf_range(0.0, TAU)
					var period := lerpf(2.8, 1.6, t) * _rng.randf_range(0.9, 1.1)
					for k in 3:
						spec.hazards.append({"kind": "riser", "along": float(a), "x": (k - 1) * 2.7,
							"w": 2.5, "h": 1.5, "d": 1.4,
							"period": period, "phase": base + TAU * k / 3.0})
					groups.append(float(a))

	# Score gates: just after every hazard group, or every gate_spacing metres.
	var dist_len := info.length
	if not groups.is_empty():
		for g in groups:
			var along := g + 3.0
			if along < dist_len - 1.0 and _gate_ok(data, along):
				spec.gates.append(along)
	elif info.gate_spacing > 0.0:
		var along := info.gate_spacing
		while along < dist_len - 0.5:
			if _gate_ok(data, along):
				spec.gates.append(along)
			along += info.gate_spacing

	# Decorative pillars beside the track.
	var count := _rng.randi_range(3, 6)
	for k in count:
		spec.decor.append({
			"along": _rng.randf_range(0.0, dist_len),
			"side": (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(9.0, 22.0),
			"height": _rng.randf_range(4.0, 16.0),
			"tint": _rng.randi_range(0, 7),
		})


## Five evenly spaced lanes across the rideable floor at `along`.
func _lanes(data: Dictionary, along: float) -> Array[float]:
	var width := TrackGeometry.flat_width(data["cross"][TrackGeometry.sample_index(data, along)])
	var usable := maxf(width - 1.6, 0.0)
	var out: Array[float] = []
	var n := 5 if width >= 6.0 else 3
	for i in n:
		out.append(snappedf(lerpf(-usable * 0.5, usable * 0.5, float(i) / (n - 1)), 0.001))
	return out


func _add_post(spec: ChunkSpec, along: float, x0: float, x1: float) -> void:
	if x1 - x0 < 0.05:
		return
	spec.hazards.append({"kind": "block", "along": along, "x": (x0 + x1) * 0.5,
		"w": x1 - x0, "h": 1.6, "d": 0.6})


func _gate_ok(data: Dictionary, along: float) -> bool:
	var i := TrackGeometry.sample_index(data, along) + 1
	var floor_on: PackedByteArray = data["floor"]
	var launch: PackedByteArray = data["launch"]
	var holes: Array[Vector2] = data["hole"]
	for k in range(maxi(i - 2, 1), mini(i + 3, floor_on.size())):
		if floor_on[k] == 0 or launch[k] == 1 or holes[k] != Vector2.ZERO:
			return false
	return true
