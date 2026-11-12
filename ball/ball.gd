class_name Ball
extends RigidBody3D
## The player's ball: a Jolt rigid body with a custom steering force, a forward-speed
## governor and snap-to-floor to remove seam bumps.

signal died(cause: String)
signal airborne_started

## Assigned in Ball.tscn (BallTuning.tres); a default is loaded if missing.
@export var tuning: BallTuning

var generator: TrackGenerator
## Optional Callable(ball: Ball, frame: TrackFrame) -> float steering in [-1, 1].
var autopilot: Callable
var alive := false
var grounded := false
var steer: float = 0.0
var frame: TrackFrame
## Statistics for the acceptance tests.
var airborne_ticks: int = 0
var ticks: int = 0

var _key_steer: float = 0.0
var _pending_reset := false
var _reset_transform := Transform3D.IDENTITY
var _reset_velocity := Vector3.ZERO
var _prev_right := Vector3.ZERO
var _launch_timer: float = 0.0
var _launched := false
var _air_time: float = 0.0
var _whoosh_sent := false
var _gravity: float = 9.8


func _ready() -> void:
	if tuning == null:
		tuning = load("res://ball/BallTuning.tres") as BallTuning
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	mass = tuning.mass
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = tuning.linear_damp
	angular_damp = tuning.angular_damp
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	collision_layer = Layers.BALL
	collision_mask = Layers.TRACK | Layers.HAZARD
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.0
	mat.friction = 0.8
	physics_material_override = mat
	($CollisionShape3D.shape as SphereShape3D).radius = tuning.radius
	($Mesh.mesh as SphereMesh).radius = tuning.radius
	($Mesh.mesh as SphereMesh).height = tuning.radius * 2.0
	$Mesh.material_override = Look.ball_material


## Places the ball (alive) at a transform with a velocity. Applied immediately.
func spawn(at: Transform3D, velocity: Vector3) -> void:
	alive = true
	freeze = false
	visible = true
	_key_steer = 0.0
	steer = 0.0
	_launch_timer = 0.0
	_launched = false
	_air_time = 0.0
	_whoosh_sent = false
	_prev_right = Vector3.ZERO
	airborne_ticks = 0
	ticks = 0
	grounded = true
	frame = null
	global_transform = at
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, at)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	_reset_transform = at
	_reset_velocity = velocity
	_pending_reset = true
	reset_physics_interpolation()


## Teleports by an offset without touching velocity (floating origin shift).
func shift(offset: Vector3) -> void:
	var t := global_transform
	t.origin += offset
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	if _pending_reset:
		_reset_transform.origin += offset
	reset_physics_interpolation()


func kill(cause: String) -> void:
	if not alive:
		return
	alive = false
	set_deferred(&"freeze", true)
	visible = false
	died.emit(cause)


func arm_launch() -> void:
	_launch_timer = tuning.launch_grace
	_launched = true


func is_airborne() -> bool:
	return not grounded


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if autopilot.is_valid():
		steer = clampf(float(autopilot.call(self, frame)), -1.0, 1.0)
		return
	var target := Input.get_action_strength(&"steer_right") - Input.get_action_strength(&"steer_left")
	target = clampf(target + Game.touch_steer, -1.0, 1.0)
	_key_steer = move_toward(_key_steer, target, delta / tuning.key_ramp_time)
	var stick := 0.0
	for device in Input.get_connected_joypads():
		var raw := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if absf(raw) > tuning.stick_deadzone:
			stick = signf(raw) * (absf(raw) - tuning.stick_deadzone) / (1.0 - tuning.stick_deadzone)
			break
	steer = stick if stick != 0.0 else _key_steer


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_reset:
		state.transform = _reset_transform
		state.linear_velocity = _reset_velocity
		state.angular_velocity = Vector3.ZERO
		_pending_reset = false
		return
	if not alive or generator == null:
		return
	var dt := state.step
	var pos := state.transform.origin
	var f := generator.query(pos)
	if f == null:
		return
	frame = f
	ticks += 1

	var on_track := false
	var contact_normal := Vector3.ZERO
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as Node
		if other == null:
			continue
		if other.is_in_group(&"hazard"):
			_die_deferred("hazard")
			return
		if other.is_in_group(&"track"):
			on_track = true
			var cn_i := state.get_contact_local_normal(i)
			contact_normal += cn_i

	if pos.y < f.kill_y - 8.0:
		_die_deferred("fell")
		return

	var b := f.transform.basis
	var right := b.x
	var up := b.y
	var fwd := -b.z

	# Short down ray for snap-to-floor; follows the contact normal on curved walls.
	var down := -up
	if on_track and contact_normal.length_squared() > 0.0:
		var cn := contact_normal.normalized()
		if cn.dot(up) < 0.0:
			cn = -cn
		down = -cn
	var hit := _probe_floor(state, pos, down, right, fwd)
	var ray_ground := not hit.is_empty()
	grounded = on_track or (ray_ground and pos.distance_to(hit["position"]) <= tuning.radius + 0.05)

	if f.launch:
		arm_launch()
	_launch_timer = maxf(_launch_timer - dt, 0.0)
	if grounded:
		# A launch ends once the ball is back on the floor outside the ramp.
		if _launched and _launch_timer <= 0.0:
			_launched = false
		_air_time = 0.0
		_whoosh_sent = false
	else:
		_air_time += dt
		airborne_ticks += 1
		if _air_time > 0.2 and not _whoosh_sent:
			_whoosh_sent = true
			airborne_started.emit()
	var launching := _launch_timer > 0.0 or _launched

	var v := state.linear_velocity
	if not grounded:
		v += Vector3.DOWN * _gravity * (tuning.air_gravity_multiplier - 1.0) * dt

	# Lateral: steering along the track's right vector, damped when there is no input.
	var lat_now := v.dot(right)
	var lat_prev := v.dot(_prev_right) if _prev_right != Vector3.ZERO else lat_now
	var lat := lerpf(lat_prev, lat_now, tuning.centrifugal)
	_prev_right = right
	if absf(steer) > 0.01:
		lat += steer * tuning.lateral_accel * (1.0 if grounded else tuning.air_control) * dt
	else:
		lat *= exp(-tuning.lateral_damping * dt)
	lat = clampf(lat, -tuning.max_lateral_speed, tuning.max_lateral_speed)

	# Forward-speed governor along the path tangent.
	var target := f.target_speed
	var fw := clampf(v.dot(fwd), target, target * tuning.governor_headroom)
	var vu := v.dot(up)
	fw = _join_guard(f, fw, dt)
	v = fwd * fw + right * lat + up * vu

	# Anti-bounce: kill small upward velocity off the floor and pull back onto it.
	if ray_ground and not launching:
		var n: Vector3 = hit["normal"]
		var vn := v.dot(n)
		# Real launches only come from ramp volumes, so with the floor in reach and no
		# launch armed, upward velocity off the floor is a contact artefact (seam or
		# mesh-edge kick). Kicks up to snap_max_up_speed are always removed; larger ones
		# too when strict_snap is on (edge kicks grow with speed).
		if vn > 0.0 and (tuning.strict_snap or vn < tuning.snap_max_up_speed):
			v -= n * vn
			vn = 0.0
		var gap := pos.distance_to(hit["position"]) - tuning.radius
		if gap > 0.002 and vn <= 0.0:
			v -= n * minf(gap / dt * 0.5, tuning.snap_pull_speed)

	state.linear_velocity = v


## Keeps a physics step from starting just before a chunk join (see BallTuning).
func _join_guard(f: TrackFrame, fw: float, dt: float) -> float:
	if fw < tuning.join_guard_min_speed:
		return fw
	var to_join := f.chunk_length - f.offset
	var travel := fw * dt
	var zone := tuning.join_guard_zone
	if to_join > zone and to_join - travel < zone and to_join - travel > 0.0:
		return (to_join - zone - 0.01) / dt
	return fw


## Short ray toward the floor. A ray that lands exactly on a shared triangle edge can
## miss both triangles, so two slightly offset rays back up the first one.
func _probe_floor(state: PhysicsDirectBodyState3D, pos: Vector3, down: Vector3, right: Vector3, fwd: Vector3) -> Dictionary:
	var reach := tuning.radius + tuning.snap_distance
	var space := state.get_space_state()
	for offset: Vector3 in [Vector3.ZERO, right * 0.023 + fwd * 0.011, right * -0.019 + fwd * -0.013]:
		var from := pos + offset
		var q := PhysicsRayQueryParameters3D.create(from, from + down * reach, Layers.TRACK, [get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return hit
	return {}


func _die_deferred(cause: String) -> void:
	call_deferred(&"kill", cause)
