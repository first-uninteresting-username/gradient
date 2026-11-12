class_name ChaseCam
extends Camera3D
## Chase camera locked to the path tangent (not ball velocity) so it never wobbles.
## Only the lateral/vertical offset from the path follows the ball, through a
## critically damped spring.

const BEHIND := 6.0
const ABOVE := 2.2
const LOOK_AHEAD := 10.0
const HALF_LIFE := 0.08
const FOV_MIN := 70.0
const FOV_MAX := 85.0
const FOV_MIN_REDUCED := 74.0
const ROLL_MAX_DEG := 6.0
const ROLL_MAX_REDUCED_DEG := 1.5

var generator: TrackGenerator
var ball: Ball
var follow := false

var _offset := Vector2.ZERO
var _offset_vel := Vector2.ZERO
var _roll: float = 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = FOV_MIN
	far = 600.0


func snap() -> void:
	_offset = Vector2.ZERO
	_offset_vel = Vector2.ZERO
	_roll = 0.0
	follow = true
	_update(0.0, true)


func _process(delta: float) -> void:
	if follow:
		_update(delta, false)


## Exact critically damped spring step (Holden, "Spring-It-On").
static func spring_step(x: Vector2, v: Vector2, goal: Vector2, half_life: float, dt: float) -> Array:
	var y := (4.0 * log(2.0)) / (half_life + 1e-5) / 2.0
	var j0 := x - goal
	var j1 := v + j0 * y
	var eydt := exp(-y * dt)
	return [eydt * (j0 + j1 * dt) + goal, eydt * (v - j1 * y * dt)]


func _update(delta: float, instant: bool) -> void:
	if generator == null or ball == null or generator.plan == null or generator.chunks.is_empty():
		return
	var bpos := ball.get_global_transform_interpolated().origin
	var p := generator.progress
	if ball.frame != null:
		p = ball.frame.progress
	var here := generator.frame_at_progress(p)
	var rel := bpos - here.origin
	var goal := Vector2(rel.dot(here.basis.x), rel.dot(here.basis.y) - ball.tuning.radius)
	if instant:
		_offset = goal
		_offset_vel = Vector2.ZERO
	else:
		var r := spring_step(_offset, _offset_vel, goal, HALF_LIFE, delta)
		_offset = r[0]
		_offset_vel = r[1]

	var back := generator.frame_at_progress(p - BEHIND)
	var ahead := generator.frame_at_progress(p + LOOK_AHEAD)
	var cam_pos := back.origin + back.basis.x * _offset.x + Vector3.UP * (ABOVE + 0.5) \
		+ back.basis.y * maxf(_offset.y, 0.0)
	var target := ahead.origin + ahead.basis.x * (_offset.x * 0.6) \
		+ Vector3.UP * (0.5 + maxf(_offset.y, 0.0) * 0.5)

	var reduced := bool(Save.get_setting("reduced_motion"))
	var roll_max := deg_to_rad(ROLL_MAX_REDUCED_DEG if reduced else ROLL_MAX_DEG)
	var curv := generator.curvature_at_progress(p + LOOK_AHEAD * 0.5)
	var roll_goal := clampf(-curv * 12.0, -1.0, 1.0) * roll_max
	_roll = roll_goal if instant else lerpf(_roll, roll_goal, 1.0 - exp(-6.0 * delta))

	global_position = cam_pos
	if cam_pos.distance_squared_to(target) > 0.01:
		look_at(target, Vector3.UP)
		rotate_object_local(Vector3.BACK, _roll)

	var speed := ball.linear_velocity.length() if ball.alive else 0.0
	var t := clampf((speed - TrackPlan.BASE_SPEED) / (TrackPlan.SOFT_CAP - TrackPlan.BASE_SPEED), 0.0, 1.0)
	var fov_lo := FOV_MIN
	var fov_hi := FOV_MIN_REDUCED if reduced else FOV_MAX
	var fov_goal := lerpf(fov_lo, fov_hi, t)
	fov = fov_goal if instant else lerpf(fov, fov_goal, 1.0 - exp(-4.0 * delta))


func shift(offset: Vector3) -> void:
	global_position += offset
