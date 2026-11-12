class_name World
extends Node3D
## The 3D side of a run: track generator, ball, chase camera, environment and the
## death sequence (shatter + slow motion).

signal ball_died(cause: String)
signal death_finished
signal gate_passed
signal finish_reached

const SLOWMO_SCALE := 0.3
const SLOWMO_TIME := 0.4

@onready var generator: TrackGenerator = $Generator
@onready var ball: Ball = $Ball
@onready var camera: ChaseCam = $ChaseCam
@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var effects: Node3D = $Effects

var running := false
var deaths: int = 0
var _death_token: int = 0


func _ready() -> void:
	Look.configure_environment(environment.environment)
	generator.ball = ball
	ball.generator = generator
	camera.generator = generator
	camera.ball = ball
	ball.died.connect(_on_ball_died)
	ball.airborne_started.connect(func() -> void: Audio.play_whoosh())
	generator.gate_passed.connect(func() -> void: gate_passed.emit())
	generator.finish_reached.connect(func() -> void: finish_reached.emit())
	generator.origin_shifted.connect(_on_origin_shifted)
	ball.freeze = true
	ball.visible = false


func start_run(plan: TrackPlan) -> void:
	_death_token += 1
	Engine.time_scale = 1.0
	for c in effects.get_children():
		c.queue_free()
	generator.start(plan)
	var t := generator.spawn_transform(ball.tuning.radius)
	ball.spawn(t, -t.basis.z * plan.target_speed(0.0))
	camera.snap()
	running = true


func stop_run() -> void:
	_death_token += 1
	running = false
	Engine.time_scale = 1.0
	ball.alive = false
	ball.set_deferred(&"freeze", true)
	camera.follow = false


func speed() -> float:
	return ball.linear_velocity.length() if ball.alive else 0.0


func _physics_process(_delta: float) -> void:
	if running and ball.alive:
		var t := (speed() - TrackPlan.BASE_SPEED) / (TrackPlan.SOFT_CAP - TrackPlan.BASE_SPEED)
		Audio.set_intensity(t)


func _on_ball_died(cause: String) -> void:
	running = false
	deaths += 1
	camera.follow = false
	Shatter.spawn(effects, ball.global_position, ball.linear_velocity, deaths)
	if Game.state != Game.State.MENU:
		Audio.play_shatter()
	Audio.set_intensity(0.15)
	var token := _death_token
	ball_died.emit(cause)
	if token != _death_token:
		return  # A restart already happened (practice mode).
	Engine.time_scale = SLOWMO_SCALE
	await get_tree().create_timer(SLOWMO_TIME, true, false, true).timeout
	if token != _death_token:
		return
	Engine.time_scale = 1.0
	death_finished.emit()


func _on_origin_shifted(offset: Vector3) -> void:
	camera.shift(offset)
	for c in effects.get_children():
		if c is Node3D:
			(c as Node3D).global_position += offset
