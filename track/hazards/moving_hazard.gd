class_name MovingHazard
extends AnimatableBody3D
## A lethal hazard that moves once the ball gets close. It telegraphs with a pulsing
## outline for TELEGRAPH seconds before it starts and is lethal the whole time.
## Motion runs on physics-tick track time since activation, so replays at the same
## speed line up identically.

const TELEGRAPH := 0.5
## Seconds of ball travel before arrival at which the hazard starts moving.
const START_LEAD := 1.6

var size := Vector3.ONE
var params: Dictionary = {}
var along_distance: float = 0.0
var base_transform := Transform3D.IDENTITY
var active := false
var telegraphing := false
var track_time: float = 0.0
var _material: ShaderMaterial
var _mesh: MeshInstance3D


func setup(p_size: Vector3, p_params: Dictionary, p_along: float) -> void:
	size = p_size
	params = p_params
	along_distance = p_along
	base_transform = transform
	sync_to_physics = false
	collision_layer = Layers.HAZARD
	collision_mask = 0
	add_to_group(&"hazard")
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = Look.unit_box
	_mesh.scale = size
	_material = Look.make_hazard_instance_material()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	transform = _pose(0.0)
	Look.changed.connect(_on_look_changed)


func _on_look_changed() -> void:
	Look.apply_hazard_params(_material)


## Called every physics tick by the generator with the ball's run progress.
func advance(progress: float, speed: float, delta: float) -> void:
	var arrival := (along_distance - progress) / maxf(speed, 1.0)
	if not active:
		telegraphing = arrival <= START_LEAD + TELEGRAPH
		if arrival <= START_LEAD:
			active = true
			telegraphing = false
	else:
		track_time += delta
	_material.set_shader_parameter(&"telegraph", 1.0 if telegraphing else 0.0)
	transform = _pose(track_time)


## Predicted local pose `seconds` from now, given the ball's progress and speed
## (used by the demo bot; mirrors advance()).
func predicted_pose(seconds: float, progress: float, speed: float) -> Transform3D:
	if active:
		return _pose(track_time + seconds)
	var arrival := (along_distance - progress) / maxf(speed, 1.0)
	return _pose(maxf(0.0, seconds - (arrival - START_LEAD)))


## Local pose at a track time. Overridden by the slider and riser.
func _pose(_t: float) -> Transform3D:
	return base_transform
