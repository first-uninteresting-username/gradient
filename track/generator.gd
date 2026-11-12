class_name TrackGenerator
extends Node3D
## Streams chunks from a TrackPlan around the ball, answers track queries and shifts
## the world origin on long runs.

signal chunk_entered(info: ChunkInfo)
signal gate_passed
signal origin_shifted(offset: Vector3)
signal finish_reached

const AHEAD := 6
const BEHIND := 2
const ORIGIN_SHIFT_DISTANCE := 2000.0

var plan: TrackPlan
var ball: Ball
var chunks: Dictionary = {}
var current_index: int = 0
var origin_shifts: int = 0
var progress: float = 0.0
## Single static body that hosts every streamed chunk's floor shape.
var floor_body: StaticBody3D

var _next_index: int = 0
var _next_transform := Transform3D.IDENTITY
var _finish_sent := false


func _ready() -> void:
	floor_body = StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = Layers.TRACK
	floor_body.collision_mask = 0
	floor_body.add_to_group(&"track")
	add_child(floor_body)


func start(p_plan: TrackPlan) -> void:
	clear()
	plan = p_plan
	_next_index = 0
	_next_transform = Transform3D.IDENTITY
	current_index = 0
	progress = 0.0
	origin_shifts = 0
	_finish_sent = false
	_stream()


func clear() -> void:
	for c: Chunk in chunks.values():
		_free_chunk(c)
	chunks.clear()
	plan = null


func get_chunk(index: int) -> Chunk:
	return chunks.get(index)


func current_chunk() -> Chunk:
	return chunks.get(current_index)


## Spawn transform and velocity for the ball at the start of the run.
func spawn_transform(radius: float) -> Transform3D:
	var c := get_chunk(0)
	var f := c.global_frame_at(3.0)
	return Transform3D(f.basis, f.origin + f.basis.y * (radius + 0.002))


func query(world_pos: Vector3) -> TrackFrame:
	if plan == null:
		return null
	var idx := current_index
	var c := get_chunk(idx)
	if c == null:
		return null
	var off := c.locate(world_pos)
	# Walk forward/backward while the point lies outside this chunk.
	var guard := 0
	while off > c.length and chunks.has(idx + 1) and guard < 4:
		idx += 1
		c = get_chunk(idx)
		off = c.locate(world_pos)
		guard += 1
	while off < 0.0 and chunks.has(idx - 1) and guard < 8:
		idx -= 1
		c = get_chunk(idx)
		off = c.locate(world_pos)
		guard += 1
	var f := TrackFrame.new()
	f.chunk_index = idx
	f.offset = off
	f.chunk_length = c.length
	f.progress = c.start_distance + off
	f.transform = c.global_frame_at(off)
	f.curvature = c.curvature_at(off)
	f.kill_y = c.kill_plane_y_at(off)
	f.target_speed = plan.target_speed(f.progress)
	f.launch = c.is_launch_at(off)
	return f


## Global frame at a run distance (extrapolates beyond the streamed chunks).
func frame_at_progress(p: float) -> Transform3D:
	var c := _chunk_for_progress(p)
	if c == null:
		return Transform3D.IDENTITY
	return c.global_frame_at(p - c.start_distance)


func curvature_at_progress(p: float) -> float:
	var c := _chunk_for_progress(p)
	return c.curvature_at(p - c.start_distance) if c != null else 0.0


func _chunk_for_progress(p: float) -> Chunk:
	var best: Chunk = null
	var first: Chunk = null
	for c: Chunk in chunks.values():
		if first == null or c.start_distance < first.start_distance:
			first = c
		if c.start_distance <= p and (best == null or c.start_distance > best.start_distance):
			best = c
	return best if best != null else first


func _physics_process(delta: float) -> void:
	if plan == null or ball == null or not ball.alive:
		return
	var f := query(ball.global_position)
	if f == null:
		return
	progress = f.progress
	if f.chunk_index != current_index:
		var forward := f.chunk_index > current_index
		current_index = f.chunk_index
		if forward:
			chunk_entered.emit(get_chunk(current_index).info)
		_stream()
	var c := current_chunk()
	if c.spec.finish and not _finish_sent:
		_finish_sent = true
		finish_reached.emit()
	for ch: Chunk in chunks.values():
		ch.update_hazards(progress, f.target_speed, delta)
	if ball.global_position.length() > ORIGIN_SHIFT_DISTANCE:
		_shift_origin(-ball.global_position)


func _stream() -> void:
	while _next_index <= current_index + AHEAD:
		_spawn_next()
	for idx in chunks.keys():
		if idx < current_index - BEHIND:
			var c: Chunk = chunks[idx]
			chunks.erase(idx)
			_free_chunk(c)


func _spawn_next() -> void:
	var spec := plan.get_spec(_next_index)
	var scene := plan.catalogue.get_scene(spec.id)
	var c := scene.instantiate() as Chunk
	c.name = "Chunk%d_%s" % [spec.index, spec.id]
	c.transform = _next_transform
	add_child(c)
	c.build(spec)
	floor_body.add_child(c.floor_shape)
	c.floor_shape.transform = c.transform
	c.gate_passed.connect(func() -> void: gate_passed.emit())
	chunks[spec.index] = c
	_next_transform = _next_transform * c.exit_transform
	_next_transform.basis = _next_transform.basis.orthonormalized()
	_next_index += 1


func _free_chunk(c: Chunk) -> void:
	if c.floor_shape != null and c.floor_shape.get_parent() == floor_body:
		floor_body.remove_child(c.floor_shape)
		c.floor_shape.queue_free()
	remove_child(c)
	c.queue_free()


func _shift_origin(offset: Vector3) -> void:
	for c: Chunk in chunks.values():
		c.position += offset
		c.floor_shape.position += offset
		c.reset_physics_interpolation()
	_next_transform.origin += offset
	ball.shift(offset)
	origin_shifts += 1
	origin_shifted.emit(offset)
